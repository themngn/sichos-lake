import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

// Display Settings indicator and popup: a top-down layout diagram of every
// connected monitor (doubles as a picker -- click a box to select it, current
// bar's own screen selected by default) plus a Settings section for whichever
// monitor is selected: name/description, a resolution/refresh-rate combo-box
// pair, a brightness slider (DDC for a desktop monitor, the laptop panel's
// own backlight otherwise), a Variable refresh rate checkbox, and a "Use this
// display for HDR" checkbox. Structured like BluetoothIndicator.qml
// (self-contained pill + popup, no persisted-settings singleton) rather than
// HdrToggle/HdrSettings/HdrPopup's three-file split -- brightness/layout are
// live hardware state, re-read fresh each time the popup opens rather than
// owned by this config.
//
// VRR only has a fire-and-forget write path, unlike brightness: the same
// hl.monitor() mechanism HdrSettings.qml uses for cm/bitdepth
// (hl.monitor({output=name, vrr=N}) via `hyprctl eval`) is the correct call
// per Hyprland's own Lua stub (/usr/share/hypr/stubs/hl.meta.lua lists
// `vrr? integer|boolean` on the monitor spec), but there's no reliable way
// to read the *configured* value back to confirm or initialize a checkbox
// from it -- confirmed live that `hyprctl monitors -j`'s "vrr" field
// actually reports whether VRR is *currently engaged* (gated on a
// fullscreen surface demanding it, per that same monitor's own
// solitaryBlockedBy/tearingBlockedBy fields), not the configured mode, so
// it stayed false in testing regardless of what was requested. `misc:vrr`
// (the global mode) IS readable via `hyprctl getoption`, but there's no
// per-monitor equivalent. So, same as HdrSettings.active, each checkbox
// here reflects only its own last-issued request (session-only, resets on
// every quickshell restart) rather than confirmed hardware state.
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
    readonly property string popupId: "display"
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
            if (root.popupOpen && !closeDelayTimer.running) {
                closeDelayTimer.start()
            }
        }
    }

    onHoveredChanged: _updateHoverState()
    onPopupHoveredChanged: _updateHoverState()

    PopupWindow {
        id: popup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        visible: root.popupOpen

        implicitWidth: bg.implicitWidth
        implicitHeight: bg.implicitHeight

        // `popupHoverHandler` alone only sees the mouse while it's over
        // `bg`'s own surface -- once a ModePicker's dropdown opens (a
        // separate floating PopupWindow, see ModePicker's own comment),
        // moving the mouse into IT hands mouse-over to that other surface
        // instead, and this popup would otherwise think the pointer left
        // entirely and close itself out from under the open dropdown.
        // Each ModePicker bumps this while its own box or dropdown is
        // hovered (a plain counter rather than an OR of named siblings,
        // since there are two of them and neither needs to know about the
        // other).
        property int extraHoverCount: 0
        readonly property bool popupHovered: popupHoverHandler.hovered || popup.extraHoverCount > 0

        // Popup content width -- every fixed-width row below shares this
        // rather than its own literal 240/300 so resizing the popup is a
        // one-line change.
        readonly property real contentWidth: 300

        property var ddcMonitors: []
        property var vrrEnabled: ({}) // monitor name -> bool, see file header

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

        onVisibleChanged: if (visible) {
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

        function saveMonitorConfig(name, modeSpec, scale) {
            const args = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/save-monitor-config.py", name]
            if (modeSpec) args.push("--mode", modeSpec)
            if (scale) args.push("--scale", scale)
            Quickshell.execDetached(args)
        }

        function isVrrEnabled(name) {
            return !!popup.vrrEnabled[name]
        }

        function toggleVrr(name) {
            const next = Object.assign({}, popup.vrrEnabled)
            next[name] = !next[name]
            popup.vrrEnabled = next
            Quickshell.execDetached(["hyprctl", "eval",
                'hl.monitor({output="' + name + '",vrr=' + (next[name] ? 1 : 0) + '})'])
        }

        Rectangle {
            id: bg
            implicitWidth: column.implicitWidth + 24
            implicitHeight: column.implicitHeight + 26
            color: "#1c1c1c"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 0

            HoverHandler {
                id: popupHoverHandler
            }

            Column {
                id: column
                anchors.centerIn: parent
                spacing: 14

                // Header
                Item {
                    width: popup.contentWidth
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "Display"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 2
                            font.bold: true
                            color: Theme.text
                        }
                    }
                }

                Rectangle {
                    width: popup.contentWidth
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Text {
                    text: "Layout"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
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
                            return {
                                name: m.name,
                                isCurrent: m.name === root.screenName,
                                brand: popup.isLaptopPanel(m.name) ? "Built-in Display" : popup.friendlyMake(m.make),
                                model: popup.isLaptopPanel(m.name) ? "" : m.model,
                                vrrCapable: popup.vrrCapable(m),
                                hdrCapable: popup.hdrCapability[m.name] === true,
                                x: m.x,
                                y: m.y,
                                w: (rotated ? m.height : m.width) / scale,
                                h: (rotated ? m.width : m.height) / scale
                            }
                        })

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
                            brand: i.brand,
                            model: i.model,
                            vrrCapable: i.vrrCapable,
                            hdrCapable: i.hdrCapable,
                            rx: (i.x - minX) * fit,
                            ry: (i.y - minY) * fit,
                            rw: Math.max(2, i.w * fit),
                            rh: Math.max(2, i.h * fit)
                        }))
                        return { rects: rects, height: spanY * fit }
                    }

                    Repeater {
                        model: layoutBox.rects

                        delegate: Rectangle {
                            id: monRect
                            required property var modelData
                            x: modelData.rx
                            y: modelData.ry
                            width: modelData.rw
                            height: modelData.rh
                            radius: 0
                            readonly property bool selected: popup.selectedMonitor === modelData.name
                            color: monRect.selected
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: monRect.selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.25)

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popup.selectedMonitor = monRect.modelData.name
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
                                font.family: Theme.fontFamily
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
                                font.family: Theme.fontFamily
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
                                font.family: Theme.fontFamily
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
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }
                                Text {
                                    visible: monRect.modelData.hdrCapable
                                    text: "HDR"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }
                            }

                            // Marks whichever box is this bar's own screen --
                            // distinct from monRect.selected (click-driven,
                            // defaults to this same box but can be pointed at
                            // any monitor) since the two can diverge once
                            // another box is clicked.
                            Text {
                                visible: monRect.modelData.isCurrent
                                anchors.centerIn: parent
                                text: "This"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }

                    Text {
                        visible: layoutBox.rects.length === 0
                        anchors.centerIn: parent
                        text: "No monitors detected"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Rectangle {
                    width: popup.contentWidth
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Text {
                    text: "Settings"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
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
                            // takes any float, so this is the same small set
                            // of stops most desktop scaling UIs offer. 3.2
                            // instead of a plain 3: Hyprland's own tooltip
                            // flags scale=3 on a 2560x1440 panel as invalid
                            // (853.33x480, a non-integer logical resolution)
                            // and recommends 3.2 (a clean 800x450) instead --
                            // filtered below per-monitor along with everything
                            // else in this list, so a resolution where 3.2
                            // itself doesn't divide evenly just won't offer it.
                            readonly property var scaleCandidates: [1, 1.25, 1.6, 2, 3.2, 4]

                            // Actually-offered stops for this monitor: capped
                            // by native resolution (even 2x is already too
                            // much on a 1920x1200 panel -- a ~960x600 logical
                            // desktop is too cramped to be worth it, so that
                            // tier caps at 1.6x instead) and filtered to only
                            // those that divide this panel's real resolution
                            // into a clean integer logical size, the same
                            // property that makes 3 vs. 3.2 matter above,
                            // generalized to whatever's connected.
                            readonly property var scaleOptions: {
                                const w = row.modelData.width
                                const h = row.modelData.height
                                const maxScale = h <= 1200 ? 1.6 : (h <= 1440 ? 3.2 : 4)
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
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }

                                // Side by side, 3:2 -- "2560x1440" needs more
                                // room than "165Hz" does. (300 - 6 spacing) / 5
                                // parts = ~59px/part.
                                Row {
                                    width: parent.width
                                    spacing: 6

                                    ModePicker {
                                        boxWidth: 175
                                        current: row.selectedRes
                                        options: row.resolutions
                                        onPicked: (value) => row.pickResolution(value)
                                    }

                                    ModePicker {
                                        boxWidth: 118
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
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
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
                                            height: 26
                                            radius: 0
                                            color: scaleButton.isActive
                                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                                : Qt.rgba(1, 1, 1, 0.06)
                                            border.width: 1
                                            border.color: scaleButton.isActive ? Theme.accent : Qt.rgba(1, 1, 1, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: scaleButton.modelData + "x"
                                                color: scaleButton.isActive ? Theme.text : Theme.textMuted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 3
                                            }
                                            MouseArea {
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
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }

                                // Brightness slider -- DDC for a desktop monitor,
                                // the laptop panel's own backlight otherwise (see
                                // popup.hasBacklight/backlightPercent above).
                                Row {
                                    visible: row.hasBrightness
                                    width: parent.width
                                    spacing: 6

                                    Rectangle {
                                        id: track
                                        width: parent.width - 40
                                        height: 8
                                        color: Qt.rgba(1, 1, 1, 0.12)

                                        Rectangle {
                                            width: track.width * (row.percent / 100)
                                            height: parent.height
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
                                        width: 34
                                        height: track.height
                                        verticalAlignment: Text.AlignVCenter
                                        text: row.percent + "%"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                }

                                Text {
                                    visible: !row.hasBrightness
                                    text: "No brightness control"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
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
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
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
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
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
                text: (checkbox.checked ? "[x] " : "[ ] ") + checkbox.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: checkbox.checked ? Theme.accent : Theme.textMuted
            }
            MouseArea {
                anchors.fill: parent
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
        // The option list is a second PopupWindow -- a genuine floating
        // overlay, not a child sized into this Item's own layout, so opening
        // it never resizes the Display popup or shoves its other rows
        // around. Two things had to be worked around to get this rendering
        // in the right place, both confirmed live:
        //   1. Anchoring straight to `box` (anchor.item) puts it two
        //      xdg_popup levels deep off the bar's layer-shell surface (box
        //      lives inside the Display popup, itself already one level
        //      deep) -- Quickshell reports it visible with the right size,
        //      but nothing ever renders. Anchoring to `root.QsWindow.window`
        //      (the bar's own PanelWindow) instead keeps this popup a
        //      sibling of the Display popup, one level deep, which renders.
        //   2. `PopupAnchor.mapFromItem` does NOT do real cross-window
        //      coordinate translation despite being built for exactly this
        //      -- it just returns box's position relative to its own
        //      popup's content root. `barRectForBox()` below computes the
        //      real answer by hand (Wayland doesn't hand a client back its
        //      own popup's resolved position, so there's no API to read
        //      this out directly) -- see its own comment for why it has to
        //      be a function called from `anchor.onAnchoring`, not a
        //      declarative property binding.
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
            // (hover-out) -- listPopup is anchored to the bar, not to
            // `popup`, so it wouldn't otherwise notice and the arrow glyph
            // would stay stuck on "▲" for next time this reopens.
            Connections {
                target: popup
                function onVisibleChanged() { if (!popup.visible) picker.expanded = false }
            }

            // True while the pointer is over this picker's own box or its
            // open dropdown (a separate window -- see listHover below).
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

            // `box`'s rect in the BAR window's coordinate space -- has to be
            // a function called from anchor.onAnchoring below, never a
            // `readonly property rect: ...` binding: Qt's coordinate mapping
            // functions (mapToItem/mapFromItem) are not reactive (Quickshell
            // documents this on PopupAnchor's own `anchoring` signal), so a
            // property binding using them evaluates exactly once, during
            // construction -- before `box`/`root` are even parented into
            // their real item trees -- and then never re-evaluates, no
            // matter how wrong that first answer was. Confirmed live: such a
            // property came back a degenerate {x:-2,y:0,w:30,h:24} (root's
            // own local size, i.e. no ancestor transform applied at all) and
            // stayed that way across restarts. `anchoring()` is emitted by
            // Quickshell's own WaylandPopupPositioner right before it reads
            // the rect back to build the xdg_positioner, which is both the
            // one moment the whole hierarchy is guaranteed laid out AND
            // guaranteed to be read by that exact positioning pass.
            //
            // The Display popup's own on-screen position (needed to place
            // box, which lives inside it, into the bar window's coordinate
            // space) is read directly via plain QtQuick `Window.window.x/y`
            // rather than predicted -- first attempt here hand-replicated
            // the xdg_positioner math (centered under `root`, then
            // Hyprland's own slide-to-fit clamp since `root` sits near the
            // bar's right edge), which landed close but ~16px off in
            // testing. `Window.window` gives Qt's own tracked *global*
            // position for any window (confirmed live: the bar's is exactly
            // its monitor's origin, e.g. 2560 for the second monitor;
            // `popup`'s is a real absolute coordinate too, not local/zeroed
            // the way Quickshell's own WindowInterface has no equivalent
            // property for) -- subtracting the two gives popup's exact
            // position relative to the bar, no guessing required.
            function barRectForBox() {
                const popupWin = box.Window.window
                const barWin = root.Window.window
                if (!popupWin || !barWin) return Qt.rect(0, 0, 1, 1)

                // box's own position within popup -- ordinary same-window
                // mapping, exact now that this runs after layout instead of
                // during construction.
                const b = box.mapToItem(popup.contentItem, 0, 0, box.width, box.height)

                // The 2px gap under the box is baked into the returned
                // height instead of an anchor.margins.top on listPopup --
                // that's a no-op for gravity: Bottom (marginsRemoved() moves
                // the top edge down and shrinks the height by the same
                // amount, leaving y+h, the actual anchor point, unchanged).
                return Qt.rect(
                    (popupWin.x - barWin.x) + b.x,
                    (popupWin.y - barWin.y) + b.y,
                    b.width, b.height + 2)
            }

            Rectangle {
                id: box
                width: picker.boxWidth
                height: 26
                radius: 0

                // Same "sunken control" look on the closed box regardless of
                // hover/open state -- only the border lights up, same
                // treatment TimeSpinner's arrows give hover via containsMouse.
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: (boxHover.containsMouse || picker.expanded)
                    ? Theme.accent : Qt.rgba(1, 1, 1, 0.2)

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: sep.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: picker.current
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
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
                    color: Qt.rgba(1, 1, 1, 0.15)
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

            PopupWindow {
                id: listPopup
                // Anchored to the bar (see barRectForBox's own comment), so
                // this does NOT inherit the Display popup's own visibility
                // automatically -- without the `&& popup.visible` an
                // expanded dropdown would keep floating on screen after the
                // Display popup itself closes on hover-out.
                visible: picker.expanded && popup.visible
                anchor.window: root.QsWindow.window
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                color: "transparent"
                implicitWidth: listBg.implicitWidth
                implicitHeight: listBg.implicitHeight

                Connections {
                    target: listPopup.anchor
                    function onAnchoring() {
                        listPopup.anchor.rect = picker.barRectForBox()
                    }
                }

            // Its own bordered panel (not bare rows loose on a transparent
            // window) so it actually reads as a dropdown rather than plain
            // text floating in space.
            Rectangle {
                id: listBg
                implicitWidth: picker.boxWidth
                implicitHeight: optionsColumn.implicitHeight + 4
                radius: 0
                color: "#242424"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.2)

                // Covers the whole card (padding included, not just the
                // option rows' own MouseAreas) so picker.selfHovered stays
                // true while the pointer is anywhere over the dropdown.
                HoverHandler {
                    id: listHover
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
                            radius: 0
                            color: optionHover.containsMouse
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                                : (optionRow.isCurrent
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                    : "transparent")

                            Text {
                                anchors.centerIn: parent
                                width: optionRow.width - 8
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: optionRow.modelData
                                color: optionRow.isCurrent ? Theme.accent : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
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
}
