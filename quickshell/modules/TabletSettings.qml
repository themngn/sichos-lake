pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pen tablet settings: the Control Center's Pen tablet page (TabletPage.qml,
// "qs-tablet") and tile, plus the Display page's per-monitor row. All of it
// is Hyprland's own input.tablet / input.tablettool / cursor options, set
// live with `hyprctl eval` (each checked live to switch at once, no reload)
// and read back by hypr/input.lua from tablet.json on every config load, so
// a reload or restart keeps them. Covers every tablet libinput sees,
// whichever way it's connected -- over Bluetooth OpenTabletDriver can't
// open a tablet at all (its HID backend only lists USB devices), so this is
// the mapping that works there.
//
// Keep proportions and Area size need the tablet's size in mm (the active
// area options are in mm): scripts/tablet-info.py reads it from the HID
// descriptor. It's remembered in the file, along with the area computed
// from it, because a Bluetooth tablet drops off the bus when it sleeps --
// input.lua just applies the stored numbers, and they're recomputed here
// whenever a setting, the monitors or the tablet change.
QtObject {
    id: root

    readonly property string output: _a.output          // "" = every monitor
    readonly property bool keepRatio: _a.keepRatio
    readonly property real area: _a.area                 // 0.3..1 of the tablet
    readonly property int rotation: _a.rotation          // 0/90/180/270
    readonly property bool relative: _a.relative         // mouse mode
    readonly property bool hideCursor: _a.hideCursor
    readonly property real pressureMin: _a.pressureMin   // 0..0.3
    readonly property real pressureMax: _a.pressureMax   // 0.3..1
    // Side buttons: an action id each (see scripts/pen-buttons.py and
    // `actions` below). "default" = what the pen does by itself.
    readonly property string lowerButton: (_a.buttons || {}).lower || "default"
    readonly property string upperButton: (_a.buttons || {}).upper || "default"
    // The pen's upper button is an eraser switch, so "eraser" there is its
    // default; anything else needs pen-buttons.py running.
    readonly property bool remapping: root.lowerButton !== "default"
        || (root.upperButton !== "default" && root.upperButton !== "eraser")

    // What a button can do: id, label, a hint and a glyph; `only` limits
    // one to a button (lower's default is already middle click, upper's
    // already the eraser).
    readonly property var actions: [
        { id: "default", label: "Pen default", hint: "", glyph: "\u{f03ea}" },
        { id: "right", label: "Right click", hint: "", glyph: "\u{f037d}" },
        { id: "middle", label: "Middle click", hint: "", glyph: "\u{f037d}", only: "upper" },
        { id: "eraser", label: "Eraser", hint: "While held", glyph: "\u{f01fe}", only: "lower" },
        { id: "undo", label: "Undo", hint: "Ctrl+Z", glyph: "\u{f030c}" },
        { id: "redo", label: "Redo", hint: "Ctrl+Shift+Z", glyph: "\u{f030c}" },
        { id: "space", label: "Hold Space", hint: "Pan the canvas", glyph: "\u{f030c}" },
        { id: "ctrl", label: "Hold Ctrl", hint: "Colour picker in Krita", glyph: "\u{f030c}" },
        { id: "shift", label: "Hold Shift", hint: "", glyph: "\u{f030c}" },
        { id: "alt", label: "Hold Alt", hint: "", glyph: "\u{f030c}" },
        { id: "off", label: "Off", hint: "Does nothing", glyph: "\u{f073a}" }
    ]
    function actionsFor(which) { return root.actions.filter(a => !a.only || a.only === which) }
    function actionLabel(which) {
        const id = which === "upper" ? root.upperButton : root.lowerButton
        if (id === "default") return which === "upper" ? "Eraser" : "Middle click"
        const a = root.actions.find(a => a.id === id)
        return a ? a.label : id
    }
    function setButton(which, id) {
        const b = Object.assign({ lower: "default", upper: "default" }, _a.buttons || {})
        b[which] = id
        _a.buttons = b
    }

    // Tablets Hyprland knows about right now (`hyprctl devices -j`).
    property var tablets: []
    readonly property bool connected: root.tablets.length > 0
    // The connected one's name/bus/size (tablet-info.py), else the last one.
    property var _info: ({})
    readonly property var current: {
        for (const t of root.tablets) if (root._info[t.name]) return root._info[t.name]
        return null
    }
    readonly property string tabletName: root.current ? root.current.name : _a.tabletName
    readonly property real tabletWidth: root.current ? root.current.width : _a.tabletWidth
    readonly property real tabletHeight: root.current ? root.current.height : _a.tabletHeight
    readonly property bool sizeKnown: root.tabletWidth > 0 && root.tabletHeight > 0
    readonly property string bus: root.current ? root.current.bus : ""

    // Enabled monitors, logical size (scale and rotation applied).
    property var monitors: []

    function friendly(name) {
        if (name === "") return "All displays"
        for (const m of root.monitors) if (m.name === name) return m.friendly
        return name
    }

    function setOutput(name) { _a.output = name; root._apply() }
    function setKeepRatio(on) { _a.keepRatio = on; root._apply() }
    function setArea(v) { _a.area = Math.max(0.3, Math.min(1, v)); root._apply() }
    function setRotation(deg) { _a.rotation = deg; root._apply() }
    function setRelative(on) { _a.relative = on; root._apply() }
    function setHideCursor(on) { _a.hideCursor = on; root._apply() }
    function setPressureMin(v) { _a.pressureMin = Math.max(0, Math.min(0.3, v)); root._apply() }
    function setPressureMax(v) { _a.pressureMax = Math.max(0.3, Math.min(1, v)); root._apply() }
    function resetPressure() { _a.pressureMin = 0; _a.pressureMax = 1; root._apply() }

    function refresh() {
        _devices.running = true
        _monitorsProc.running = true
    }

    // The active area: the tablet's part that maps to the target's shape
    // (keepRatio), shrunk to `area`, centred. [w, h, x, y] in mm; all zero
    // = Hyprland's default, the whole tablet. Rotated 90/270 the tablet's
    // long side runs along the screen's short one, so the shape flips.
    function _activeArea() {
        const W = root.tabletWidth, H = root.tabletHeight
        if (!root.sizeKnown) return [0, 0, 0, 0]
        let w = W, h = H
        if (root.keepRatio && !root.relative) {
            const t = root._targetSize()
            if (t) {
                let aspect = t[0] / t[1]
                if (root.rotation === 90 || root.rotation === 270) aspect = 1 / aspect
                if (W / H > aspect) w = H * aspect
                else h = W / aspect
            }
        }
        w *= root.area
        h *= root.area
        if (Math.abs(w - W) < 0.05 && Math.abs(h - H) < 0.05) return [0, 0, 0, 0]
        const r = v => Math.round(v * 10) / 10
        return [r(w), r(h), r((W - w) / 2), r((H - h) / 2)]
    }
    function _targetSize() {
        const ms = root.output === "" ? root.monitors : root.monitors.filter(m => m.name === root.output)
        if (ms.length === 0) return null
        const x0 = Math.min(...ms.map(m => m.x)), y0 = Math.min(...ms.map(m => m.y))
        const x1 = Math.max(...ms.map(m => m.x + m.w)), y1 = Math.max(...ms.map(m => m.y + m.h))
        return [x1 - x0, y1 - y0]
    }

    // Hyprland's tablet transform uses the monitor transform numbers
    // (1 = 90°, 2 = 180°, 3 = 270°).
    function _apply() {
        const a = root._activeArea()
        _a.activeArea = a
        if (root.current) {
            _a.tabletName = root.current.name
            _a.tabletWidth = root.current.width
            _a.tabletHeight = root.current.height
        }
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({input={tablet={"
            + 'output="' + root.output + '"'
            + ",transform=" + Math.round(root.rotation / 90) % 4
            + ",relative_input=" + root.relative
            + ",active_area_size={" + a[0] + "," + a[1] + "}"
            + ",active_area_position={" + a[2] + "," + a[3] + "}"
            + "},tablettool={pressure_range_min=" + root.pressureMin.toFixed(2)
            + ",pressure_range_max=" + root.pressureMax.toFixed(2)
            + "}},cursor={hide_on_tablet=" + root.hideCursor + "}})"])
    }
    // After the tablet or the monitors change: only when the area moved, so
    // opening the page doesn't rewrite the file every time.
    function _recheck() {
        if (!_file.loaded) return
        const a = root._activeArea()
        const old = _a.activeArea || []
        if (a.some((v, i) => v !== old[i]) || (root.current && root.current.width !== _a.tabletWidth)) root._apply()
    }

    property Process _devices: Process {
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list
                try { list = JSON.parse(text).tablets || [] } catch (e) { return }
                const key = l => l.map(t => t.name).join(",")
                if (key(list) === key(root.tablets)) return
                root.tablets = list
                if (root.connected) _infoProc.running = true
            }
        }
    }
    property Process _infoProc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/tablet-info.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._info = JSON.parse(text)
                } catch (e) { /* keep the last */ }
                root._recheck()
            }
        }
    }
    property Process _monitorsProc: Process {
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list
                try { list = JSON.parse(text) } catch (e) { return }
                const makes = list.map(m => Displays.friendlyMake(m.make))
                root.monitors = list.map((m, i) => {
                    const turned = m.transform % 2 === 1
                    const lw = Math.round(m.width / m.scale), lh = Math.round(m.height / m.scale)
                    const laptop = Displays.isLaptopPanel(m.name)
                    // Two monitors of one brand: their connector names tell them apart.
                    const brand = makes[i]
                    const dup = !laptop && makes.filter(b => b === brand).length > 1
                    return { name: m.name, friendly: laptop ? "Laptop" : dup ? brand + " " + m.name : brand,
                        x: m.x, y: m.y, w: turned ? lh : lw, h: turned ? lw : lh }
                })
                root._recheck()
            }
        }
    }

    property FileView _file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/tablet.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoaded: root._recheck()

        adapter: JsonAdapter {
            id: _a
            property string output: ""
            property bool keepRatio: true
            property real area: 1
            property int rotation: 0
            property bool relative: false
            property bool hideCursor: false
            property real pressureMin: 0
            property real pressureMax: 1
            property var buttons: ({ lower: "default", upper: "default" })
            // Derived -- for input.lua, which can't compute them.
            property var activeArea: [0, 0, 0, 0]
            property string tabletName: ""
            property real tabletWidth: 0
            property real tabletHeight: 0
        }
    }

    // The remapper waits for the tablet itself (and re-reads tablet.json
    // when it changes), so it runs whenever a binding is set, connected or
    // not -- a Bluetooth tablet waking while the Control Center is closed
    // would go unnoticed here.
    property Process _buttons: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/pen-buttons.py"]
        running: root.remapping && _file.loaded
    }

    // Hyprland's event socket says nothing when a tablet comes or goes (a
    // Bluetooth one does on every sleep), so while the Control Center is
    // open the device list is re-read every few seconds -- one hyprctl call.
    readonly property bool _ccOpen: ShellState.activePopup === "quicksettings" || ShellState.activePopup.startsWith("qs-")
    on_CcOpenChanged: if (root._ccOpen) root.refresh()
    property Timer _poll: Timer {
        interval: 3000
        repeat: true
        running: root._ccOpen
        onTriggered: _devices.running = true
    }

    Component.onCompleted: refresh()
}
