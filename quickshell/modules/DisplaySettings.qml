import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Display Settings indicator and popup: a top-down layout diagram of every
// connected monitor (doubles as a picker -- click a box to select it, current
// bar's own screen selected by default; drag one to rearrange the monitors,
// see layoutBox.drop) plus a Settings section for whichever
// monitor is selected: name/description, a resolution/refresh-rate combo-box
// pair, a brightness slider (DDC for a desktop monitor, the laptop panel's
// own backlight otherwise), a Variable refresh rate checkbox, and a "Use this
// display for HDR" checkbox. Structured like BluetoothIndicator.qml
// (self-contained pill + popup, no persisted-settings singleton) rather than
// HdrToggle/HdrSettings/HdrPopup's three-file split -- brightness/layout are
// live hardware state, re-read fresh each time the popup opens rather than
// owned by this config.
//
// VRR is applied live with the same hl.monitor() mechanism HdrSettings.qml
// uses for cm/bitdepth (hl.monitor({output=name, vrr=N}) via `hyprctl
// eval`; /usr/share/hypr/stubs/hl.meta.lua lists `vrr? integer|boolean` on
// the monitor spec), and -- like mode/scale -- also written into the
// deployed monitors.lua via save-monitor-config.py so it survives a
// Hyprland restart. The live state can't be read back: `hyprctl monitors
// -j`'s "vrr" field reports whether VRR is *currently engaged* (gated on a
// fullscreen surface demanding it when vrr=2), not the configured mode, and
// there's no per-monitor getoption. So the checkbox initializes from
// monitors.lua itself (`save-monitor-config.py --list-vrr`) on every open --
// that file is what the next Hyprland start will apply, and every toggle
// here keeps it in step with what was just applied live.
//
// "Use this display for HDR" is a thin wrapper around
// HdrSettings.toggleMonitor -- it only edits which monitors HDR would apply
// to next, it does NOT turn HDR on for this popup's monitor (see
// HdrSettings.qml's own header for why that's opt-in and global-switched
// rather than direct). The VRR/HDR checkboxes always occupy the same space
// regardless of state (greyed-out MonitorCheckbox.capable, never
// visible:false) so picking a different monitor above never resizes the
// popup depending on what that monitor happens to support.
Pill {
    id: root
    property string screenName: ""

    readonly property bool anyVrrOn: Object.keys(popup.vrrEnabled).some(k => popup.vrrEnabled[k])

    BarIcon {
        glyph: "󰹑"
        // Ink 544/1000em (fontTools glyf bbox) -- scaled to the shared bar
        // icon target.
        pixelSize: Theme.barIconInkHeight * 1000 / 544
        color: root.anyVrrOn ? Theme.accent : Theme.text
    }

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    // QuickSettings.qml embeds a hidden instance of this as a submenu of its
    // own card: it sets a distinct popupId (so it never opens together with
    // a standalone instance on the same screen), anchors the popup to its
    // own pill, and names the popup the header's back arrow returns to.
    property string popupId: "display"
    property Item popupAnchor: root
    property string backPopupId: ""
    // false inside the Control Center, which closes only on a click outside.
    property bool closeOnLeave: true
    property real popupContentWidth: 300
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool popupHovered: popup.popupHovered

    Timer {
        id: openDelayTimer
        interval: 250
        onTriggered: {
            if (root.hovered) {
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            }
        }
    }

    Timer {
        id: closeDelayTimer
        interval: 300
        onTriggered: {
            if (!root.hovered && !root.popupHovered) {
                if (ShellState.activePopup === root.popupId) {
                    ShellState.activePopup = ""
                }
            }
        }
    }

    function _updateHoverState() {
        if (root.hovered) {
            closeDelayTimer.stop()
            if (ShellState.activePopup !== "" && !root.popupOpen) {
                openDelayTimer.stop()
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            } else if (ShellState.activePopup === "" && !openDelayTimer.running) {
                openDelayTimer.start()
            }
        } else if (root.popupHovered) {
            closeDelayTimer.stop()
            openDelayTimer.stop()
        } else {
            openDelayTimer.stop()
            if (root.popupOpen && root.closeOnLeave && !closeDelayTimer.running) {
                closeDelayTimer.start()
            }
        }
    }

    onHoveredChanged: _updateHoverState()
    // An embedded (QuickSettings) instance opens by a click inside the card
    // with no pill of its own to hover, so arm the close check on open too.
    onPopupOpenChanged: _updateHoverState()
    onPopupHoveredChanged: _updateHoverState()

    // Set by Bar.qml: the bar's MorphPopup card (see MorphContent.qml).
    property Item popupHost: null
    readonly property Item _popupContent: MorphContent {
        id: popup
        parent: root.popupHost
        anchorItem: root.popupAnchor
        shown: root.popupOpen

        implicitWidth: bg.implicitWidth
        implicitHeight: bg.implicitHeight

        // `popupHoverHandler` alone only sees the mouse while it's over
        // `bg` -- a ModePicker's open dropdown is drawn over the card but
        // isn't inside `bg` (see ModePicker's own comment), so this popup
        // could otherwise think the pointer left and close itself out from
        // under the open dropdown.
        // Each ModePicker bumps this while its own box or dropdown is
        // hovered (a plain counter rather than an OR of named siblings,
        // since there are two of them and neither needs to know about the
        // other).
        property int extraHoverCount: 0
        readonly property bool popupHovered: popupHoverHandler.hovered || popup.extraHoverCount > 0

        // Popup content width -- every fixed-width row below shares this
        // rather than its own literal 240/300 so resizing the popup is a
        // one-line change.
        readonly property real contentWidth: root.popupContentWidth

        property var ddcMonitors: []
        property var vrrEnabled: ({}) // monitor name -> bool, from monitors.lua (see file header)

        // Ground truth for every monitor field this popup reads (layout
        // diagram, brand/model, resolution list, refresh rate) -- queried
        // fresh via `hyprctl monitors all -j` on every open rather than
        // trusting Quickshell's own Hyprland.monitors.values cache, which
        // gets stale/duplicated after repeated hl.monitor({mirror=...})
        // toggling (confirmed live: the layout diagram broke after enough
        // mirror/extend cycles from the SUPER+P bind in keybindings.lua,
        // even though `hyprctl monitors` itself reported the real state
        // correctly the whole time -- restarting quickshell fixed it
        // temporarily by rebuilding that cache from scratch, but it broke
        // again after more toggling, confirming the cache itself is what
        // drifts, not a one-off glitch). "all" (not just the default
        // listing) so a currently-mirrored monitor still shows up here
        // instead of vanishing from the diagram entirely.
        property var freshMonitors: []

        Process {
            id: monitorsProc
            command: ["hyprctl", "monitors", "all", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        popup.freshMonitors = JSON.parse(text)
                    } catch (e) { /* leave the previous (or empty) list in place */ }
                }
            }
        }

        // Which monitor the Settings section below the layout diagram is
        // showing -- defaults to (and resets to, on every reopen, same as
        // the DDC re-read below) this bar's own screen, since that's the
        // monitor the user is actually looking at when they open this
        // popup. Clicking a different box in the layout re-targets it.
        property string selectedMonitor: root.screenName

        function monitorFor(name) {
            for (const m of popup.freshMonitors) if (m.name === name) return m
            return null
        }

        readonly property var selectedMonitors: {
            const m = popup.monitorFor(popup.selectedMonitor)
            return m ? [m] : []
        }

        // A monitor's own name (eDP-1, LVDS-1, DSI-1) is how keybindings.lua
        // already tells the laptop's built-in panel apart from a desktop
        // output (see its own comment there) -- reused here since the panel
        // has no DDC/CI bus of its own to list in ddc-brightness.py's output.
        function isLaptopPanel(name) {
            return /^(eDP|LVDS|DSI)/.test(name)
        }

        // EDID "make" strings are the legal entity name, not the brand --
        // confirmed live: DP-2 reports "Lenovo Group Limited", DP-3 reports
        // "Iiyama North America", neither of which is what you'd call the
        // monitor. Table covers what's actually connected to this machine;
        // the regex fallback strips the same kind of corporate-suffix noise
        // from anything not listed so a monitor swap doesn't need this table
        // updated to still look reasonable.
        readonly property var makeAliases: ({
            "Lenovo Group Limited": "Lenovo",
            "Iiyama North America": "Iiyama"
        })

        function friendlyMake(make) {
            if (!make) return ""
            if (popup.makeAliases[make]) return popup.makeAliases[make]
            const stripped = make.replace(
                /\s*\b(Group Limited|North America|Corporation|Co\.,? Ltd\.?|Inc\.?|Technology|Electronics|Company)\b\s*/gi, " ").trim()
            return stripped || make
        }

        // The panel's backlight is a single global sysfs interface, not
        // addressed by output name -- same path Backlight.qml/BacklightOSD.qml
        // already read/write, so this mirrors their FileView + brightnessctl
        // pattern rather than inventing a second way to touch it.
        readonly property bool hasBacklight: _blMax.text().length > 0
        readonly property int backlightPercent: popup.hasBacklight && _blBrightness.text().length > 0
            ? Math.round((Number(_blBrightness.text()) / Number(_blMax.text())) * 100) : 0

        FileView {
            id: _blBrightness
            path: "/sys/class/backlight/amdgpu_bl1/brightness"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
        }
        FileView {
            id: _blMax
            path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
            printErrors: false
        }

        // Whether a monitor is worth offering a VRR checkbox for at all.
        // Neither hyprctl nor wlr-randr expose real VRR *capability* on this
        // Hyprland/wlroots (checked live) -- both only ever report whether
        // adaptive sync is currently *engaged*, same limitation the file
        // header notes for hyprctl's "vrr" field. EDID has no standardized
        // VRR range block the way CTA-861 has one for HDR (AMD FreeSync's is
        // vendor-specific and not worth reverse-engineering here), so this
        // uses a cheaper real-world proxy instead: a monitor that actually
        // does adaptive sync almost always exposes more than one discrete
        // refresh rate at its native resolution (confirmed live on this
        // machine -- the 165Hz Iiyama lists 4 rates at 2560x1440, the plain
        // 60Hz Lenovo lists only 1). A `false` here greys the checkbox out
        // and blocks toggling it (MonitorCheckbox.capable) -- unlike
        // HdrSettings/HdrPopup's own capability check, which only hints via
        // opacity and still lets an already-selected monitor be unchecked.
        function vrrCapable(m) {
            const modes = (m && m.availableModes) || []
            const prefix = m.width + "x" + m.height + "@"
            return modes.filter(s => s.startsWith(prefix)).length > 1
        }

        // name -> true|false|null, see hdr-capable.py's own header for what
        // each value means. Re-run fresh on every open, same reasoning as
        // ddcListProc -- and the same script HdrPopup.qml uses, just queried
        // independently here rather than sharing its popup-local state.
        property var hdrCapability: ({})

        Process {
            id: hdrCapableProc
            command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/hdr-capable.py"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        popup.hdrCapability = JSON.parse(text)
                    } catch (e) { /* leave the previous (or empty) map in place */ }
                }
            }
        }

        onShownChanged: if (shown) {
            vrrListProc.running = true
            ddcListProc.running = true
            hdrCapableProc.running = true
            monitorsProc.running = true
            popup.selectedMonitor = root.screenName
        }

        Process {
            id: ddcListProc
            command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/ddc-brightness.py", "list"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        popup.ddcMonitors = JSON.parse(text)
                    } catch (e) { /* leave the previous (or empty) list in place */ }
                }
            }
        }

        function ddcFor(name) {
            for (const d of popup.ddcMonitors) {
                if (d.output === name) return d
            }
            return null
        }

        function setBrightness(bus, value) {
            Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/ddc-brightness.py",
                "set", String(bus), String(value)])
        }

        // modeSpec is "WxH@RR" (no "Hz" suffix -- that's what monitors.lua's
        // own mode= values look like, and what hl.monitor() expects).
        //
        // hl.monitor() only ever applies live -- resolution/refresh-rate/
        // scale changes made here would otherwise be lost the next time
        // Hyprland starts (back to whatever monitors.lua says), the same
        // fire-and-forget behavior already documented for VRR above. This
        // also writes the change into the deployed monitors.lua itself via
        // save-monitor-config.py, so it actually persists.
        function applyMode(name, modeSpec) {
            Quickshell.execDetached(["hyprctl", "eval",
                'hl.monitor({output="' + name + '",mode="' + modeSpec + '"})'])
            popup.saveMonitorConfig(name, modeSpec, null)
        }

        function applyScale(name, scale) {
            Quickshell.execDetached(["hyprctl", "eval",
                'hl.monitor({output="' + name + '",scale=' + scale + '})'])
            popup.saveMonitorConfig(name, null, String(scale))
        }

        function saveMonitorConfig(name, modeSpec, scale, position) {
            const args = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/save-monitor-config.py", name]
            if (modeSpec) args.push("--mode", modeSpec)
            if (scale) args.push("--scale", scale)
            if (position) args.push("--position", position)
            Quickshell.execDetached(args)
        }

        // A dragged monitor's new spot (layout px). Shown right away by
        // patching freshMonitors, then re-read from Hyprland once it has
        // applied it. Sichlink's headless SICHLINK-1 only moves live -- the
        // save script gives any other output without a block of its own one,
        // but not virtual ones (see its header).
        function applyPosition(name, x, y) {
            popup.freshMonitors = popup.freshMonitors.map(m => m.name === name ? Object.assign({}, m, { x: x, y: y }) : m)
            Quickshell.execDetached(["hyprctl", "eval",
                'hl.monitor({output="' + name + '",position="' + x + "x" + y + '"})'])
            popup.saveMonitorConfig(name, null, null, x + "x" + y)
            refreshTimer.restart()
        }
        Timer {
            id: refreshTimer
            interval: 400
            onTriggered: monitorsProc.running = true
        }
        // Live while open: a monitor plugged in or out, the lid turning the
        // built-in panel off or on, a mode/position change, a reload.
        Connections {
            target: Hyprland
            enabled: popup.shown
            function onRawEvent(event) {
                if (/^(monitoradded|monitorremoved|configreloaded)/.test(event.name))
                    refreshTimer.restart()
            }
        }

        // Any non-zero vrr counts as on (1 = always, 2 = fullscreen-only,
        // 3 = fullscreen games/video) -- a hand-edited monitors.lua may use
        // any of them, and the checkbox only distinguishes on/off.
        Process {
            id: vrrListProc
            command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/save-monitor-config.py", "--list-vrr"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const configured = JSON.parse(text)
                        const next = {}
                        for (const name in configured) next[name] = configured[name] > 0
                        popup.vrrEnabled = next
                    } catch (e) { /* leave the previous (or empty) map in place */ }
                }
            }
        }

        function isVrrEnabled(name) {
            return !!popup.vrrEnabled[name]
        }

        function toggleVrr(name) {
            const next = Object.assign({}, popup.vrrEnabled)
            next[name] = !next[name]
            popup.vrrEnabled = next
            // vrr=2 (fullscreen-only), not 1 (always): with always-on VRR an
            // idle desktop only redraws on damage, so the iiyama GB2770QSU
            // (DP-3) sat at its 40Hz FreeSync floor and visibly flickered.
            Quickshell.execDetached(["hyprctl", "eval",
                'hl.monitor({output="' + name + '",vrr=' + (next[name] ? 2 : 0) + '})'])
            Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/save-monitor-config.py",
                name, "--vrr", next[name] ? "2" : "0"])
        }

        Item {
            id: bg
            implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
            implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

            HoverHandler {
                id: popupHoverHandler
            }

            Column {
                id: column
                anchors.centerIn: parent
                spacing: Theme.sectionSpacing

                // Header
                Item {
                    width: popup.contentWidth
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        BackButton {
                            visible: root.backPopupId !== ""
                            onClicked: ShellState.activePopup = root.backPopupId
                        }
                        HeaderIcon {
                            glyph: "󰹑"
                            color: Theme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Display"
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }
                }

                Rectangle {
                    width: popup.contentWidth
                    height: 1
                    color: Theme.separator
                }

                Item {
                    width: popup.contentWidth
                    height: layoutLabel.implicitHeight
                    Text {
                        id: layoutLabel
                        text: "Layout"
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        visible: layoutBox.rects.filter(r => r.movable).length > 1
                        anchors.right: parent.right
                        anchors.baseline: layoutLabel.baseline
                        text: "Drag to rearrange"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                // Miniature top-down map of the real monitor arrangement --
                // positions/sizes come straight from Hyprland's layout space
                // (modelData.x/y/width/height, same fields hyprctl monitors -j
                // reports), scaled down to fit the popup rather than hardcoded,
                // so it stays correct across whatever monitors.lua currently
                // has configured (count, order, resolution) without this file
                // needing to know about any of that. Doubles as the picker for
                // the Settings section below -- clicking a box selects it.
                Item {
                    id: layoutBox
                    width: popup.contentWidth
                    // Scaled to fill the full width (fit is a width-only
                    // ratio in layout below, not min(width,height) the way
                    // it used to be) -- height then just follows whatever
                    // that produces for this layout's real aspect ratio,
                    // rather than being fixed and letterboxed top/bottom.
                    height: layoutBox.layout.height

                    readonly property var rects: layoutBox.layout.rects

                    readonly property var layout: {
                        const mons = popup.freshMonitors
                        if (mons.length === 0) return { rects: [], height: 90 }

                        // width/height come back in transform-0 (unrotated)
                        // pixels regardless of the monitor's actual transform,
                        // so a 90/270 rotation needs them swapped to get the
                        // real logical footprint -- scale then converts pixels
                        // to the layout-space units x/y are already in.
                        const items = mons.map(m => {
                            const scale = m.scale > 0 ? m.scale : 1
                            const rotated = (m.transform === 1 || m.transform === 3
                                || m.transform === 5 || m.transform === 7)
                            // A disabled output may report no size; its
                            // preferred mode stands in.
                            const mode = /^(\d+)x(\d+)/.exec((m.availableModes || [])[0] || "")
                            const pw = m.width > 0 ? m.width : mode ? +mode[1] : 1920
                            const ph = m.height > 0 ? m.height : mode ? +mode[2] : 1080
                            return {
                                name: m.name,
                                isCurrent: m.name === root.screenName,
                                disabled: !!m.disabled,
                                // The lid turns the built-in panel off
                                // (hypr/keybindings.lua); anything else
                                // disabled was done by hand.
                                offText: popup.isLaptopPanel(m.name) ? "Off · lid closed" : "Off",
                                brand: popup.isLaptopPanel(m.name) ? "Built-in Display" : popup.friendlyMake(m.make),
                                model: popup.isLaptopPanel(m.name) ? "" : m.model,
                                vrrCapable: popup.vrrCapable(m),
                                hdrCapable: popup.hdrCapability[m.name] === true,
                                // A disabled or mirrored output has no place
                                // of its own in the layout to move.
                                movable: !m.disabled && (!m.mirrorOf || m.mirrorOf === "none"),
                                x: m.x,
                                y: m.y,
                                w: (rotated ? ph : pw) / scale,
                                h: (rotated ? pw : ph) / scale
                            }
                        })
                        // A disabled output keeps its last spot unless that
                        // now overlaps a live one (or there's none); then it
                        // sits beside them, top-aligned.
                        const live = items.filter(i => !i.disabled)
                        for (const i of items) {
                            if (!i.disabled || live.length === 0) continue
                            if (live.some(o => i.x < o.x + o.w && i.x + i.w > o.x && i.y < o.y + o.h && i.y + i.h > o.y)) {
                                i.x = Math.max(...live.map(o => o.x + o.w))
                                i.y = Math.min(...live.map(o => o.y))
                            }
                        }

                        const minX = Math.min(...items.map(i => i.x))
                        const minY = Math.min(...items.map(i => i.y))
                        const maxX = Math.max(...items.map(i => i.x + i.w))
                        const maxY = Math.max(...items.map(i => i.y + i.h))
                        const spanX = Math.max(1, maxX - minX)
                        const spanY = Math.max(1, maxY - minY)
                        // Width-only fit -- always fills layoutBox's full
                        // width edge-to-edge, height (bound above) then
                        // just follows to keep the real layout's aspect
                        // ratio, rather than height-constraining and
                        // leaving empty space on the sides.
                        const fit = layoutBox.width / spanX

                        const rects = items.map(i => ({
                            name: i.name,
                            isCurrent: i.isCurrent,
                            disabled: i.disabled,
                            offText: i.offText,
                            brand: i.brand,
                            model: i.model,
                            vrrCapable: i.vrrCapable,
                            hdrCapable: i.hdrCapable,
                            movable: i.movable,
                            rx: (i.x - minX) * fit,
                            ry: (i.y - minY) * fit,
                            rw: Math.max(2, i.w * fit),
                            rh: Math.max(2, i.h * fit)
                        }))
                        // items/fit/minX/minY: for turning a drag in box px
                        // back into layout px (snap/drop below).
                        return { rects: rects, height: spanY * fit, items: items, fit: fit, minX: minX, minY: minY }
                    }

                    // Where a monitor dragged to (lx, ly) (layout px, its
                    // top-left) ends up: flush against a side of another
                    // monitor -- Hyprland would take a gap or an overlap, but
                    // the cursor can't cross a gap and an overlap shows the
                    // same pixels twice -- sliding along that side, with its
                    // edges caught by the other monitor's edges within a few
                    // box px. The nearest such spot that overlaps no third
                    // monitor wins, a caught edge counting as that much
                    // nearer (else a slot along the neighbouring monitor,
                    // a few px closer, beat lining up with this one); null
                    // if there's none.
                    function snap(name, lx, ly) {
                        const L = layoutBox.layout
                        const me = L.items.find(i => i.name === name)
                        const others = L.items.filter(i => i.name !== name && i.movable)
                        if (!me || others.length === 0) return null
                        const w = me.w, h = me.h
                        const catchDist = 8 / L.fit
                        // Slide along a side from lo to hi, catching on the
                        // other monitor's start/end edges.
                        const along = (v, start, len, size) => {
                            const lo = start - size + 1, hi = start + len - 1
                            for (const e of [start, start + len - size]) if (Math.abs(v - e) < catchDist) return [e, true]
                            return [Math.max(lo, Math.min(hi, v)), false]
                        }
                        const cands = []
                        for (const o of others) {
                            const ay = along(ly, o.y, o.h, h), ax = along(lx, o.x, o.w, w)
                            cands.push([o.x + o.w, ...ay], [o.x - w, ...ay], [ax[0], o.y + o.h, ax[1]], [ax[0], o.y - h, ax[1]])
                        }
                        const overlaps = (x, y) => others.some(o =>
                            x < o.x + o.w && x + w > o.x && y < o.y + o.h && y + h > o.y)
                        let best = null, bestD = Infinity
                        for (const [x, y, caught] of cands) {
                            if (overlaps(x, y)) continue
                            const d = Math.hypot(x - lx, y - ly) - (caught ? catchDist : 0)
                            if (d < bestD) { bestD = d; best = { x: Math.round(x), y: Math.round(y) } }
                        }
                        return best
                    }
                    // Box px (the dragged rect's top-left) -> layout px.
                    function toLayout(rx, ry) {
                        const L = layoutBox.layout
                        return { x: rx / L.fit + L.minX, y: ry / L.fit + L.minY }
                    }
                    function drop(name, rx, ry) {
                        const p = layoutBox.toLayout(rx, ry)
                        const s = layoutBox.snap(name, p.x, p.y)
                        const me = layoutBox.layout.items.find(i => i.name === name)
                        if (!s || !me || (s.x === me.x && s.y === me.y)) return
                        popup.applyPosition(name, s.x, s.y)
                    }

                    // The snapped spot while dragging (set by the dragged
                    // box), drawn as an outline.
                    property var ghost: null
                    Rectangle {
                        visible: layoutBox.ghost !== null
                        x: layoutBox.ghost ? (layoutBox.ghost.x - layoutBox.layout.minX) * layoutBox.layout.fit : 0
                        y: layoutBox.ghost ? (layoutBox.ghost.y - layoutBox.layout.minY) * layoutBox.layout.fit : 0
                        width: layoutBox.ghost ? layoutBox.ghost.w * layoutBox.layout.fit : 0
                        height: layoutBox.ghost ? layoutBox.ghost.h * layoutBox.layout.fit : 0
                        radius: Theme.controlRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.accent
                        opacity: 0.8
                    }

                    Repeater {
                        model: layoutBox.rects

                        delegate: Rectangle {
                            id: monRect
                            required property var modelData
                            // Offset while being dragged (box px).
                            property real dragDX: 0
                            property real dragDY: 0
                            readonly property bool draggable: monRect.modelData.movable
                                && layoutBox.rects.filter(r => r.movable).length > 1
                            x: modelData.rx + dragDX
                            y: modelData.ry + dragDY
                            z: dragArea.dragging ? 1 : 0
                            opacity: dragArea.dragging ? 0.85 : monRect.modelData.disabled ? 0.55 : 1
                            width: modelData.rw
                            height: modelData.rh
                            radius: Theme.controlRadius
                            readonly property bool selected: popup.selectedMonitor === modelData.name
                            color: monRect.selected
                                ? Theme.selectedFill
                                : monRect.modelData.disabled ? "transparent" : Theme.controlFill
                            border.width: 1
                            border.color: monRect.selected ? Theme.accent : Theme.surfaceBorder

                            // Click selects; past a few px it's a drag instead
                            // (and selects too). Positions are taken in
                            // layoutBox's coordinates, since this box moves
                            // under the pointer while dragged.
                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                // Nothing to set on an output that's off.
                                enabled: !monRect.modelData.disabled
                                cursorShape: dragArea.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                property bool dragging: false
                                property point start
                                onPressed: (mouse) => {
                                    dragArea.start = mapToItem(layoutBox, mouse.x, mouse.y)
                                    dragArea.dragging = false
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed || !monRect.draggable) return
                                    const p = mapToItem(layoutBox, mouse.x, mouse.y)
                                    const dx = p.x - dragArea.start.x, dy = p.y - dragArea.start.y
                                    if (!dragArea.dragging && Math.hypot(dx, dy) < 4) return
                                    dragArea.dragging = true
                                    popup.selectedMonitor = monRect.modelData.name
                                    monRect.dragDX = dx
                                    monRect.dragDY = dy
                                    const l = layoutBox.toLayout(monRect.modelData.rx + dx, monRect.modelData.ry + dy)
                                    const s = layoutBox.snap(monRect.modelData.name, l.x, l.y)
                                    const me = layoutBox.layout.items.find(i => i.name === monRect.modelData.name)
                                    layoutBox.ghost = s && me ? { x: s.x, y: s.y, w: me.w, h: me.h } : null
                                }
                                onReleased: {
                                    if (dragArea.dragging) {
                                        layoutBox.drop(monRect.modelData.name,
                                            monRect.modelData.rx + monRect.dragDX, monRect.modelData.ry + monRect.dragDY)
                                    } else {
                                        popup.selectedMonitor = monRect.modelData.name
                                    }
                                    dragArea.dragging = false
                                    monRect.dragDX = 0
                                    monRect.dragDY = 0
                                    layoutBox.ghost = null
                                }
                                onCanceled: {
                                    dragArea.dragging = false
                                    monRect.dragDX = 0
                                    monRect.dragDY = 0
                                    layoutBox.ghost = null
                                }
                            }

                            // Four corners rather than a centered label so a
                            // single small box can carry brand, model,
                            // output name, and capability badges all at
                            // once without any of them competing for the
                            // same line -- there's no room in a box this
                            // size (as little as ~100x80px with 3+ monitors)
                            // for a normal multi-line layout.
                            Text {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 4
                                // Full width rather than sharing with the
                                // model corner when there's no model text
                                // to share with (the "Built-in Display"
                                // label set in place of brand for the
                                // laptop panel, which leaves model blank).
                                width: (monRect.modelData.model ? parent.width / 2 - 2 : parent.width - 8)
                                text: monRect.modelData.brand
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 4
                                elide: Text.ElideRight
                            }
                            Text {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                width: parent.width / 2 - 2
                                horizontalAlignment: Text.AlignRight
                                text: monRect.modelData.model
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 4
                                elide: Text.ElideRight
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.margins: 4
                                width: parent.width / 2 - 2
                                text: monRect.modelData.name
                                color: monRect.selected ? Theme.accent : Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 4
                                elide: Text.ElideRight
                            }
                            Row {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.margins: 4
                                spacing: 2

                                Text {
                                    visible: monRect.modelData.vrrCapable
                                    text: "VRR"
                                    color: Theme.accent
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }
                                Text {
                                    visible: monRect.modelData.hdrCapable
                                    text: "HDR"
                                    color: Theme.accent
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }
                            }

                            // Marks whichever box is this bar's own screen --
                            // distinct from monRect.selected (click-driven,
                            // defaults to this same box but can be pointed at
                            // any monitor) since the two can diverge once
                            // another box is clicked.
                            Text {
                                visible: monRect.modelData.isCurrent || monRect.modelData.disabled
                                anchors.centerIn: parent
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: monRect.modelData.disabled ? monRect.modelData.offText : "This"
                                color: Theme.textDim
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }

                    Text {
                        visible: layoutBox.rects.length === 0
                        anchors.centerIn: parent
                        text: "No monitors detected"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }

                Rectangle {
                    width: popup.contentWidth
                    height: 1
                    color: Theme.separator
                }

                Text {
                    text: "Settings"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Column {
                    width: popup.contentWidth
                    spacing: 10

                    Repeater {
                        model: popup.selectedMonitors

                        delegate: Column {
                            id: row
                            required property var modelData
                            width: popup.contentWidth
                            spacing: 12

                            readonly property bool isLaptopPanel: popup.isLaptopPanel(row.modelData.name)
                            readonly property var ddc: popup.ddcFor(row.modelData.name)
                            readonly property bool hasDdc: row.ddc !== null
                            readonly property bool hasBrightness: row.hasDdc || (row.isLaptopPanel && popup.hasBacklight)
                            readonly property bool vrrCapable: popup.vrrCapable(row.modelData)
                            readonly property var hdrCapable: popup.hdrCapability[row.modelData.name]

                            // DDC brightness wins if both somehow applied (never
                            // does in practice -- a laptop panel has no DDC bus)
                            // -- otherwise seeded from sysfs for the panel, or 0
                            // when there's no brightness control at all.
                            property int percent: row.hasDdc && row.ddc.max > 0
                                ? Math.round(row.ddc.brightness / row.ddc.max * 100)
                                : (row.isLaptopPanel ? popup.backlightPercent : 0)

                            function _percentAt(x) {
                                return Math.max(0, Math.min(100, Math.round(x / (row.width - 40) * 100)))
                            }

                            // "WxH@RRRHz" strings straight from hyprctl monitors
                            // -j's own availableModes.
                            readonly property var modes: row.modelData.availableModes || []

                            // Common-name label for a WxH ratio (e.g. 16:9,
                            // 16:10, 4:3) rather than a raw GCD-reduced
                            // fraction -- exact reduction turns near-standard
                            // oddities like 1366x768 into ugly fractions
                            // (683:384) that would never group with the
                            // 1920x1080s and 2560x1440s that are visually the
                            // same ratio. Float-tolerant match against the
                            // common ratios so those still group together;
                            // anything genuinely nonstandard falls back to
                            // its own reduced fraction rather than being
                            // mislabeled as one of the known ones.
                            function aspectLabel(w, h) {
                                const ratio = w / h
                                const known = [
                                    [16 / 9, "16:9"], [16 / 10, "16:10"], [4 / 3, "4:3"],
                                    [5 / 4, "5:4"], [21 / 9, "21:9"], [3 / 2, "3:2"], [1, "1:1"]
                                ]
                                for (const [r, label] of known) {
                                    if (Math.abs(ratio - r) < 0.02) return label
                                }
                                function gcd(a, b) { return b === 0 ? a : gcd(b, a % b) }
                                const g = gcd(w, h) || 1
                                return (w / g) + ":" + (h / g)
                            }

                            // Only resolutions matching the panel's native
                            // aspect ratio -- availableModes lists every mode
                            // the panel supports at every ratio (16:9, 5:4,
                            // 4:3, ...), which is a lot of noise for a bar
                            // popup, and there's no Hyprland/DRM control (or
                            // any other actually available here) that
                            // changes how a monitor's own hardware handles an
                            // off-ratio mode (stretch, letterbox, or refuse
                            // it) -- confirmed live picking one always just
                            // stretches regardless of anything toggleable
                            // from software, so there's no real use in
                            // offering them at all, only in filtering them
                            // out.
                            readonly property var resolutions: {
                                const seen = new Set()
                                const list = []
                                for (const m of row.modes) {
                                    const wh = m.split("@")[0]
                                    if (!seen.has(wh)) { seen.add(wh); list.push(wh) }
                                }
                                const nativeLabel = row.aspectLabel(row.modelData.width, row.modelData.height)
                                return list.filter(wh => {
                                    const [w, h] = wh.split("x").map(Number)
                                    return row.aspectLabel(w, h) === nativeLabel
                                })
                            }

                            // Highest rate first -- availableModes' own order
                            // puts the EDID-preferred mode first regardless of
                            // rate (confirmed live: the 165Hz Iiyama lists its
                            // 59.95Hz mode before 165.15Hz), which reads as
                            // random in a dropdown meant to be sorted by rate.
                            function ratesFor(res) {
                                return row.modes
                                    .filter(m => m.startsWith(res + "@"))
                                    .map(m => m.slice(res.length + 1).replace(/Hz$/, ""))
                                    .sort((a, b) => parseFloat(b) - parseFloat(a))
                            }

                            property string selectedRes: row.modelData.width + "x" + row.modelData.height
                            // Seeded to whichever listed rate is closest to the
                            // monitor's actual current refresh rate (exact
                            // float formatting can differ by a thousandth
                            // between what Hyprland reports live and what's in
                            // availableModes) -- pickResolution/pickRate below
                            // take over from here once the user touches either.
                            property string selectedRate: {
                                const cur = row.modelData.refreshRate || 0
                                const opts = row.ratesFor(row.selectedRes)
                                let best = opts[0] || ""
                                let bestDiff = Infinity
                                for (const r of opts) {
                                    const diff = Math.abs(parseFloat(r) - cur)
                                    if (diff < bestDiff) { bestDiff = diff; best = r }
                                }
                                return best
                            }

                            // Live one-off mode change via hl.monitor(), same
                            // mechanism/rationale as popup.toggleVrr and
                            // HdrSettings.apply -- this Lua-config build has no
                            // legacy `hyprctl keyword monitor`.
                            function pickResolution(res) {
                                const rate = row.ratesFor(res)[0] || ""
                                row.selectedRes = res
                                row.selectedRate = rate
                                popup.applyMode(row.modelData.name, res + "@" + rate)
                            }

                            function pickRate(rate) {
                                row.selectedRate = rate
                                popup.applyMode(row.modelData.name, row.selectedRes + "@" + rate)
                            }

                            // Displayed/picked as whole Hz (nobody cares that
                            // it's really 165.153) but hl.monitor() needs the
                            // precise value to actually match one of the
                            // panel's real modes -- this resolves a rounded
                            // label from the dropdown back to it.
                            function preciseRateFor(roundedLabel) {
                                const target = parseInt(roundedLabel)
                                const opts = row.ratesFor(row.selectedRes)
                                for (const r of opts) if (Math.round(parseFloat(r)) === target) return r
                                return opts[0] || ""
                            }

                            // Candidate stops -- there's no equivalent of
                            // availableModes for scale, monitors.lua just
                            // takes any float, so this would otherwise be the
                            // same small set of stops most desktop scaling
                            // UIs offer ([1, 1.25, 1.6, 2, 2.5, 4]). Cut down
                            // to just 1x for now: the bar's Language pill
                            // (flag glyph, a color/bitmap emoji rather than a
                            // Nerd Font icon) doesn't scale correctly at
                            // anything else -- confirmed live it renders the
                            // wrong size and, worse, drifts increasingly out
                            // of vertical alignment with every other bar icon
                            // as scale grows (0px off at 1x, ~8px+ low at
                            // 2x). Every fix attempted (compensating pixelSize
                            // by the real per-output Hyprland scale, a
                            // calibrated vertical offset, a plain `scale`
                            // transform instead of a bigger pixelSize) still
                            // came out wrong at some stop -- Qt's color-emoji
                            // rendering path just doesn't behave predictably
                            // enough here to compensate for from outside.
                            // Revert to the full list above once that's
                            // actually fixed (or the flag glyph is replaced
                            // with something that isn't a bitmap font).
                            readonly property var scaleCandidates: [1]

                            // Actually-offered stops for this monitor: capped
                            // by native resolution (even 2x is already too
                            // much on a 1920x1200 panel -- a ~960x600 logical
                            // desktop is too cramped to be worth it, so that
                            // tier caps at 1.6x instead) and filtered to only
                            // those that divide this panel's real resolution
                            // into a clean integer logical size, the same
                            // property that makes 2.5 vs. 3 matter above,
                            // generalized to whatever's connected.
                            readonly property var scaleOptions: {
                                const w = row.modelData.width
                                const h = row.modelData.height
                                const maxScale = h <= 1200 ? 1.6 : (h <= 1440 ? 2.5 : 4)
                                return row.scaleCandidates.filter(s => {
                                    if (s > maxScale) return false
                                    const lw = w / s, lh = h / s
                                    return Math.abs(lw - Math.round(lw)) < 0.01
                                        && Math.abs(lh - Math.round(lh)) < 0.01
                                })
                            }

                            property real selectedScale: {
                                const cur = row.modelData.scale || 1
                                let best = row.scaleOptions[0]
                                let bestDiff = Infinity
                                for (const s of row.scaleOptions) {
                                    const diff = Math.abs(s - cur)
                                    if (diff < bestDiff) { bestDiff = diff; best = s }
                                }
                                return best
                            }

                            // popup.applyScale is its own hl.monitor() call
                            // (plus persisting to monitors.lua, see its own
                            // comment), same as VRR and HDR's cm/bitdepth --
                            // scale isn't part of the mode string
                            // pickResolution/pickRate apply, and confirmed by
                            // HdrSettings.apply's own comment that
                            // hl.monitor() only touches the fields given,
                            // leaving everything else (including the current
                            // mode) exactly as it was.
                            function pickScale(scale) {
                                row.selectedScale = scale
                                popup.applyScale(row.modelData.name, scale)
                            }

                            Column {
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: "Resolution ("
                                        + row.aspectLabel(row.modelData.width, row.modelData.height) + ")"
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }

                                // Side by side, 3:2 -- "2560x1440" needs more
                                // room than "165Hz" does. Split from contentWidth
                                // (wider when embedded in QuickSettings).
                                Row {
                                    width: parent.width
                                    spacing: 6

                                    ModePicker {
                                        boxWidth: Math.floor((popup.contentWidth - 6) * 3 / 5)
                                        current: row.selectedRes
                                        options: row.resolutions
                                        onPicked: (value) => row.pickResolution(value)
                                    }

                                    ModePicker {
                                        boxWidth: Math.floor((popup.contentWidth - 6) * 2 / 5)
                                        current: Math.round(parseFloat(row.selectedRate)) + "Hz"
                                        options: row.ratesFor(row.selectedRes)
                                            .map(r => Math.round(parseFloat(r)) + "Hz")
                                        onPicked: (value) => row.pickRate(row.preciseRateFor(value))
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: "Scale"
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }

                                // Same button shape as HdrPopup.qml's own On/Off
                                // mode switch -- one per scaleOptions entry
                                // rather than a slider, since these are fixed,
                                // individually-meaningful stops (not a
                                // continuous range) that are few enough to all
                                // show at once.
                                Row {
                                    id: scaleButtons
                                    width: parent.width
                                    spacing: 4

                                    Repeater {
                                        model: row.scaleOptions

                                        delegate: Rectangle {
                                            id: scaleButton
                                            required property real modelData
                                            readonly property bool isActive: row.selectedScale === scaleButton.modelData
                                            width: (scaleButtons.width - 4 * (row.scaleOptions.length - 1))
                                                / row.scaleOptions.length
                                            height: Theme.controlHeight
                                            radius: Theme.controlRadius
                                            color: scaleButton.isActive
                                                ? Theme.selectedFill
                                                : scaleArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                                            border.width: 1
                                            border.color: scaleButton.isActive ? Theme.accent : Theme.surfaceBorder

                                            Text {
                                                anchors.centerIn: parent
                                                text: scaleButton.modelData + "x"
                                                color: scaleButton.isActive ? Theme.text : Theme.textMuted
                                                font.family: Theme.uiFontFamily
                                                font.pixelSize: Theme.fontSize - 1
                                            }
                                            MouseArea {
                                                id: scaleArea
                                                hoverEnabled: true
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: row.pickScale(scaleButton.modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: "Brightness"
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }

                                // Brightness slider -- DDC for a desktop monitor,
                                // the laptop panel's own backlight otherwise (see
                                // popup.hasBacklight/backlightPercent above).
                                // A full text line tall (the % label's height), with
                                // the track centered in it, rather than only as
                                // tall as the track -- so it's the same height as
                                // the "No brightness control" line below and the
                                // popup doesn't change size between monitors.
                                Row {
                                    visible: row.hasBrightness
                                    width: parent.width
                                    height: percentText.implicitHeight
                                    spacing: 6

                                    Rectangle {
                                        id: track
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 40
                                        height: Theme.trackHeight
                                        radius: Theme.trackRadius
                                        color: Theme.track

                                        Rectangle {
                                            width: track.width * (row.percent / 100)
                                            height: parent.height
                                            radius: Theme.trackRadius
                                            color: Theme.accent
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    row.percent = row._percentAt(mouse.x)
                                                    commitTimer.restart()
                                                }
                                            }
                                            onPressed: (mouse) => {
                                                row.percent = row._percentAt(mouse.x)
                                                commitTimer.restart()
                                            }
                                            onWheel: (wheel) => {
                                                row.percent = Math.max(0, Math.min(100, row.percent + (wheel.angleDelta.y > 0 ? 2 : -2)))
                                                commitTimer.restart()
                                            }
                                        }
                                    }
                                    Text {
                                        id: percentText
                                        width: 34
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.percent + "%"
                                        color: Theme.textDim
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                    }
                                }

                                Text {
                                    visible: !row.hasBrightness
                                    height: percentText.implicitHeight
                                    verticalAlignment: Text.AlignVCenter
                                    text: "No brightness control"
                                    color: Theme.textDim
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                            }

                            // Debounced same reasoning as ShellState's sunset
                            // kelvin commit -- each ddcutil setvcp/brightnessctl
                            // call is a slow-ish round-trip, so this waits for
                            // the drag to settle rather than firing one per pixel.
                            Timer {
                                id: commitTimer
                                interval: 200
                                onTriggered: {
                                    if (row.hasDdc) popup.setBrightness(row.ddc.bus, Math.round(row.percent / 100 * row.ddc.max))
                                    else if (row.isLaptopPanel) Quickshell.execDetached(["brightnessctl", "set", row.percent + "%"])
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: "Options"
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }

                                MonitorCheckbox {
                                    label: "Variable refresh rate"
                                    capable: row.vrrCapable
                                    checked: popup.isVrrEnabled(row.modelData.name)
                                    onToggled: popup.toggleVrr(row.modelData.name)
                                }

                                // Undefined (capability check hasn't returned yet)
                                // or null (EDID unreadable/no CTA-861 block) both
                                // mean "can't tell", not "unsupported" -- treated
                                // as capable, same reasoning as HdrPopup.qml's own
                                // use of this script. Only a confirmed `false`
                                // greys it out.
                                MonitorCheckbox {
                                    label: "Use this display for HDR"
                                    capable: row.hdrCapable !== false
                                    checked: HdrSettings.isSelected(row.modelData.name)
                                    onToggled: HdrSettings.toggleMonitor(row.modelData.name)
                                }
                            }
                        }
                    }

                    Text {
                        visible: popup.selectedMonitors.length === 0
                        text: "No monitors detected"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }
        }

        // Similar shape to HdrPopup.qml's own MonitorCheckbox, but blocks
        // the click when `capable` is false (that popup only greys out as a
        // hint and still allows toggling). Greyed out rather than hidden so
        // switching the selected monitor above never changes how many rows
        // this Column has.
        component MonitorCheckbox: Item {
            id: checkbox
            property string label: ""
            property bool checked: false
            property bool capable: true
            signal toggled()

            width: parent.width
            height: checkText.implicitHeight
            opacity: checkbox.capable ? 1 : 0.5

            Text {
                id: checkText
                width: parent.width
                elide: Text.ElideRight
                text: (checkbox.checked ? "󰄲  " : "󰄱  ") + checkbox.label
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
                color: checkArea.containsMouse ? Theme.text : Theme.textMuted
            }
            MouseArea {
                id: checkArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: checkbox.capable
                cursorShape: checkbox.capable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: checkbox.toggled()
            }
        }

        // Click-to-expand combo box, hand-rolled since there's no such widget
        // available here (same reasoning as every other custom control in
        // this popup). `current` is shown in the closed box; `options` is a
        // flat array of display strings, one of which should equal `current`
        // so it gets highlighted in the open list.
        //
        // The option list is drawn over the card itself (parented to `popup`,
        // high z), not inside this Item's own layout, so opening it never
        // resizes the popup or shoves its other rows around. It used to be a
        // second PopupWindow anchored to the bar (a popup nested under the
        // card's own never rendered), but that made it a sibling of the bar's
        // MorphPopup, whose surface stacked above it with an input region
        // covering the card -- so the pointer never reached the list
        // (confirmed live: its HoverHandler never reported hovered) and the
        // picker closed it ~200ms after leaving the box. The card clips, so a
        // list must fit inside it -- the pickers sit near the top of a tall
        // card, which leaves room for every resolution/rate list seen here.
        component ModePicker: Item {
            id: picker
            property string current: ""
            property var options: []
            property bool expanded: false
            property int boxWidth: 100
            signal picked(string value)

            width: picker.boxWidth
            height: box.height

            // Collapses the dropdown when the Display popup itself closes
            // (hover-out), so the arrow glyph doesn't stay stuck on "▲" for
            // next time this reopens.
            Connections {
                target: popup
                function onShownChanged() { if (!popup.shown) picker.expanded = false }
            }

            // True while the pointer is over this picker's own box or its
            // open dropdown (see listHover below).
            // Bumps popup.extraHoverCount so the Display popup doesn't close
            // out from under an open dropdown (point 1), and closes the
            // dropdown itself, debounced, once neither is hovered any more
            // (point 2) -- same debounce reasoning as root's own
            // open/closeDelayTimer: box and the dropdown are two separate
            // hit areas with a small gap between them, so closing
            // immediately on every hover flicker while crossing that gap
            // would make the dropdown impossible to actually use.
            readonly property bool selfHovered: boxHover.containsMouse || listHover.hovered
            onSelfHoveredChanged: {
                popup.extraHoverCount += picker.selfHovered ? 1 : -1
                if (picker.selfHovered) closeTimer.stop()
                else closeTimer.restart()
            }

            Timer {
                id: closeTimer
                interval: 200
                onTriggered: picker.expanded = false
            }

            // mapToItem isn't reactive, so the list is placed on each open.
            onExpandedChanged: if (picker.expanded) {
                const p = box.mapToItem(popup, 0, box.height + 2)
                listBg.x = p.x
                listBg.y = p.y
            }

            Rectangle {
                id: box
                width: picker.boxWidth
                height: Theme.controlHeight
                radius: Theme.controlRadius

                // Same "sunken control" look on the closed box regardless of
                // hover/open state -- only the border lights up, same
                // treatment TimeSpinner's arrows give hover via containsMouse.
                color: Theme.controlFill
                border.width: 1
                border.color: (boxHover.containsMouse || picker.expanded)
                    ? Theme.accent : Theme.surfaceBorder

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: sep.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: picker.current
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                // Vertical divider ahead of the arrow -- the detail that
                // reads as "this is a button glued onto a field" rather than
                // just an arrow floating at the end of a text label.
                Rectangle {
                    id: sep
                    anchors.right: arrowBox.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height - 10
                    color: Theme.surfaceBorder
                }

                Item {
                    id: arrowBox
                    anchors.right: parent.right
                    width: 22
                    height: parent.height

                    Text {
                        anchors.centerIn: parent
                        text: picker.expanded ? "▲" : "▼"
                        color: boxHover.containsMouse ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                    }
                }

                MouseArea {
                    id: boxHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.expanded = !picker.expanded
                }
            }

            // Its own bordered panel (not bare rows loose on a transparent
            // window) so it actually reads as a dropdown rather than plain
            // text floating in space.
            Rectangle {
                id: listBg
                parent: popup
                z: 100
                visible: picker.expanded && popup.shown
                SurfaceAppear { target: listBg; shown: listBg.visible }
                implicitWidth: picker.boxWidth
                implicitHeight: optionsColumn.implicitHeight + 4
                radius: Theme.controlRadius
                // Solid even under glass: it covers the card's own rows.
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.surfaceBorder

                // Covers the whole card (padding included, not just the
                // option rows' own MouseAreas) so picker.selfHovered stays
                // true while the pointer is anywhere over the dropdown.
                HoverHandler {
                    id: listHover
                }
                // Keeps the rows underneath from reacting through the gaps
                // between options.
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                }

                Column {
                    id: optionsColumn
                    y: 2
                    width: parent.width

                    Repeater {
                        model: picker.options

                        delegate: Rectangle {
                            id: optionRow
                            required property string modelData
                            readonly property bool isCurrent: optionRow.modelData === picker.current
                            width: picker.boxWidth
                            height: 22
                            radius: Theme.controlRadius
                            color: optionHover.containsMouse
                                ? Theme.selectedFill
                                : (optionRow.isCurrent
                                    ? Theme.hoverFill
                                    : "transparent")

                            Text {
                                anchors.centerIn: parent
                                width: optionRow.width - 8
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: optionRow.modelData
                                color: optionRow.isCurrent ? Theme.accent : Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            MouseArea {
                                id: optionHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    picker.expanded = false
                                    picker.picked(optionRow.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
