pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Per-monitor info + brightness for the Control Center's display card, in one
// shared place rather than another popup-local copy of DisplaySettings.qml's
// helpers. Monitor facts come from `hyprctl monitors all -j` (not
// Hyprland.monitors.values -- see DisplaySettings' freshMonitors comment on
// that cache drifting after mirror toggling), brightness from the laptop's
// sysfs backlight or ddc-brightness.py for externals.
//
// Nothing here polls: DDC is slow I2C (seconds per `list`, see the script's
// header), so every probe only runs when `active` turns true (Control Center
// binds it to "card open") and on Hyprland monitor events while it stays
// true. The backlight FileView is the exception -- it's an inotify watch, not
// a probe, so it costs nothing to keep live.
QtObject {
    id: root

    property bool active: false

    // One entry per output, see _rebuild() for the shape.
    readonly property var monitors: root._monitors
    readonly property int externalCount: root._monitors.filter(m => !m.laptop).length
    readonly property string laptopName: {
        const m = root._monitors.find(m => m.laptop)
        return m ? m.name : ""
    }
    // "Docked" means some enabled screen besides the panel -- a plugged-in
    // but disabled (or lid-closed-only) external shouldn't flip any UI that
    // keys off this into its desk layout.
    readonly property bool docked: root._monitors.some(m => !m.laptop && !m.disabled)

    property var _monitors: []
    property var _hypr: []
    property var _ddc: []        // ddc-brightness.py list output
    // name -> true|false|null from hdr-capable.py. EDIDs don't change while a
    // monitor stays plugged in, so this is only re-run when the set of
    // outputs changes rather than on every open.
    property var _hdr: ({})
    property string _hdrKey: ""
    // name -> 0..1 the user just picked, shown until the next real read
    // comes back -- DDC has no change notification, and a slider snapping
    // back to the stale value mid-drag would fight the user.
    property var _optimistic: ({})

    onActiveChanged: if (root.active) root.refresh()

    function refresh() {
        monitorsProc.running = true
        ddcListProc.running = true
    }

    // Same rule keybindings.lua and DisplaySettings use -- the panel's own
    // connector name is the only reliable "this is the laptop" signal.
    function isLaptopPanel(name) {
        return /^(eDP|LVDS|DSI)/.test(name)
    }

    // EDID "make" is the legal entity, not the brand (DP-2 reports "Lenovo
    // Group Limited"). Copied from DisplaySettings.qml's friendlyMake --
    // alias table for what's actually on this desk, suffix-stripping
    // fallback so a new monitor still reads reasonably.
    readonly property var _makeAliases: ({
        "Lenovo Group Limited": "Lenovo",
        "Iiyama North America": "Iiyama"
    })

    function friendlyMake(make) {
        if (!make) return ""
        if (root._makeAliases[make]) return root._makeAliases[make]
        const stripped = make.replace(
            /\s*\b(Group Limited|North America|Corporation|Co\.,? Ltd\.?|Inc\.?|Technology|Electronics|Company)\b\s*/gi, " ").trim()
        return stripped || make
    }

    function _ddcFor(name) {
        for (const d of root._ddc) if (d.output === name) return d
        return null
    }

    function _rebuild() {
        const out = []
        for (const m of root._hypr) {
            const laptop = root.isLaptopPanel(m.name)
            const ddc = laptop ? null : root._ddcFor(m.name)
            let kind = ""
            let brightness = -1
            if (laptop && root.hasBacklight) {
                kind = "backlight"
                brightness = root.backlight
            } else if (ddc && ddc.max > 0) {
                kind = "ddc"
                brightness = ddc.brightness / ddc.max
            }
            if (kind !== "" && root._optimistic[m.name] !== undefined)
                brightness = root._optimistic[m.name]
            const hdr = root._hdr[m.name]
            out.push({
                name: m.name,
                friendly: laptop ? "Laptop" : root.friendlyMake(m.make),
                laptop: laptop,
                disabled: !!m.disabled,
                width: m.width,
                height: m.height,
                refreshRate: Math.round(m.refreshRate),
                vrr: !!m.vrr,
                mirrorOf: m.mirrorOf,
                hdrCapable: hdr === undefined ? null : hdr,
                hdrApplied: m.colorManagementPreset === "hdr",
                brightness: brightness,
                brightnessKind: kind
            })
        }
        root._monitors = out
    }

    // --- Monitors ---------------------------------------------------------

    property Process _monitorsProc: Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._hypr = JSON.parse(text)
                } catch (e) { return /* keep the previous list */ }
                // A different set of outputs may mean a different EDID
                // behind a name -- only then is hdr-capable.py worth re-running.
                const key = root._hypr.map(m => m.name + ":" + m.serial).sort().join(",")
                if (key !== root._hdrKey) {
                    root._hdrKey = key
                    hdrCapableProc.running = true
                }
                root._rebuild()
            }
        }
    }

    property Process _hdrCapableProc: Process {
        id: hdrCapableProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/hdr-capable.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._hdr = JSON.parse(text)
                    root._rebuild()
                } catch (e) { /* leave the previous (or empty) map in place */ }
            }
        }
    }

    // Coalesces the burst of raw events a single plug/unplug produces, and
    // gives Hyprland a moment to settle before reading it back -- same 400ms
    // DisplaySettings uses.
    property Timer _refreshTimer: Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
    }

    // Live while active: a monitor plugged in or out, the lid turning the
    // panel off or on, a config reload. Re-runs the DDC list too since a new
    // external brings a new bus.
    property Connections _hyprEvents: Connections {
        target: Hyprland
        enabled: root.active
        function onRawEvent(event) {
            if (/^(monitoradded|monitorremoved|configreloaded)/.test(event.name))
                refreshTimer.restart()
        }
    }

    // --- Laptop backlight -------------------------------------------------

    // Device name looked up once rather than hard-coding amdgpu_bl1 like
    // QuickSettings does, so an Intel (intel_backlight) or a renumbered
    // amdgpu node still works. First entry wins -- laptops with two
    // backlight nodes (hybrid GPUs) expose the same panel through both.
    property string _blDevice: ""
    property Process _blListProc: Process {
        running: true
        command: ["ls", "/sys/class/backlight"]
        stdout: StdioCollector {
            onStreamFinished: root._blDevice = text.split("\n").filter(s => s.length > 0)[0] || ""
        }
    }

    readonly property bool hasBacklight: root._blDevice !== "" && blMax.text().length > 0
    readonly property real backlight: root.hasBacklight && blBrightness.text().length > 0
        ? Number(blBrightness.text()) / Number(blMax.text()) : 0
    onBacklightChanged: {
        // A real sysfs change (ours landing, or the brightness keys) is
        // ground truth again -- drop the optimistic override for the panel.
        if (root.laptopName !== "" && root._optimistic[root.laptopName] !== undefined
                && root._pendingBacklight < 0) {
            const next = Object.assign({}, root._optimistic)
            delete next[root.laptopName]
            root._optimistic = next
        }
        root._rebuild()
    }

    property FileView _blBrightness: FileView {
        id: blBrightness
        path: root._blDevice ? "/sys/class/backlight/" + root._blDevice + "/brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    property FileView _blMax: FileView {
        id: blMax
        path: root._blDevice ? "/sys/class/backlight/" + root._blDevice + "/max_brightness" : ""
        printErrors: false
    }

    // Same debounce as QuickSettings.setBacklight: a drag fires far more
    // changes than brightnessctl calls are worth; only the latest per tick
    // gets written.
    property int _pendingBacklight: -1
    property Timer _backlightTimer: Timer {
        id: backlightTimer
        interval: 40
        onTriggered: {
            if (root._pendingBacklight < 0) return
            Quickshell.execDetached(["brightnessctl", "-n2", "set", root._pendingBacklight + "%"])
            root._pendingBacklight = -1
        }
    }

    // --- External DDC -----------------------------------------------------

    property Process _ddcListProc: Process {
        id: ddcListProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/ddc-brightness.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._ddc = JSON.parse(text)
                } catch (e) { return /* leave the previous (or empty) list in place */ }
                // Fresh readings supersede anything optimistic for externals,
                // unless a write is still queued (it'd be reverted on screen).
                const next = {}
                for (const n in root._optimistic)
                    if (root.isLaptopPanel(n) || root._pendingDdc[n] !== undefined) next[n] = root._optimistic[n]
                root._optimistic = next
                root._rebuild()
            }
        }
    }

    // bus -> raw VCP value still to be written. Keyed by bus so dragging two
    // monitors' sliders back to back doesn't drop the first one's write.
    // Longer than the backlight's 40ms since each setvcp is a slow I2C
    // round-trip and queued ones would otherwise pile up behind each other.
    property var _pendingDdc: ({})
    property Timer _ddcTimer: Timer {
        id: ddcTimer
        interval: 300
        onTriggered: {
            const pending = root._pendingDdc
            root._pendingDdc = {}
            for (const name in pending) {
                const p = pending[name]
                Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/ddc-brightness.py",
                    "set", String(p.bus), String(p.value)])
            }
        }
    }

    // v is 0..1. Updates `monitors` right away; the actual write is
    // debounced per kind (see the timers above).
    function setBrightness(name, v) {
        const clamped = Math.max(0, Math.min(1, v))
        if (root.isLaptopPanel(name)) {
            if (!root.hasBacklight) return
            // 1% floor like QuickSettings -- 0 turns the panel fully dark on
            // amdgpu, which looks like the screen died.
            const pct = Math.round(Math.max(0.01, clamped) * 100)
            root._pendingBacklight = pct
            if (!backlightTimer.running) backlightTimer.start()
        } else {
            const ddc = root._ddcFor(name)
            if (!ddc || !(ddc.max > 0)) return
            const pending = Object.assign({}, root._pendingDdc)
            pending[name] = { bus: ddc.bus, value: Math.round(clamped * ddc.max) }
            root._pendingDdc = pending
            ddcTimer.restart()
            // Keep the cached reading in step so a rebuild (e.g. a monitor
            // event) before the next `list` doesn't snap the slider back.
            root._ddc = root._ddc.map(d => d.output === name ? Object.assign({}, d, { brightness: pending[name].value }) : d)
        }
        const next = Object.assign({}, root._optimistic)
        next[name] = clamped
        root._optimistic = next
        root._rebuild()
    }
}
