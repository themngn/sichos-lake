import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Display Settings indicator and popup: per-monitor DDC/CI brightness
// sliders plus a per-monitor VRR checkbox. Structured like
// BluetoothIndicator.qml (self-contained pill + popup, no persisted-settings
// singleton) rather than HdrToggle/HdrSettings/HdrPopup's three-file split —
// brightness is live hardware state, re-read fresh each time the popup
// opens rather than owned by this config.
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
Pill {
    id: root
    property string screenName: ""

    readonly property bool anyVrrOn: Object.keys(popup.vrrEnabled).some(k => popup.vrrEnabled[k])

    BarIcon {
        glyph: "󰍹"
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

        readonly property bool popupHovered: popupHoverHandler.hovered

        property var ddcMonitors: []
        property var vrrEnabled: ({}) // monitor name -> bool, see file header

        onVisibleChanged: if (visible) ddcListProc.running = true

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
            implicitHeight: column.implicitHeight + 20
            color: "#1c1c1c"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 6

            HoverHandler {
                id: popupHoverHandler
            }

            Column {
                id: column
                anchors.centerIn: parent
                spacing: 12

                // Header
                Item {
                    width: 240
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "Display"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }
                }

                Rectangle {
                    width: 240
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Text {
                    text: "Monitors"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Column {
                    width: 240
                    spacing: 10

                    Repeater {
                        model: Hyprland.monitors.values

                        delegate: Column {
                            id: row
                            required property var modelData
                            width: 240
                            spacing: 4

                            readonly property var ddc: popup.ddcFor(row.modelData.name)
                            readonly property bool hasDdc: row.ddc !== null

                            property int percent: row.hasDdc && row.ddc.max > 0
                                ? Math.round(row.ddc.brightness / row.ddc.max * 100) : 0

                            function _percentAt(x) {
                                return Math.max(0, Math.min(100, Math.round(x / (row.width - 40) * 100)))
                            }

                            // Name + VRR checkbox
                            Item {
                                width: parent.width
                                height: 14

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 70
                                    elide: Text.ElideRight
                                    text: row.modelData.name + (row.modelData.description ? " — " + row.modelData.description : "")
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (popup.isVrrEnabled(row.modelData.name) ? "[x] " : "[ ] ") + "VRR"
                                    color: popup.isVrrEnabled(row.modelData.name) ? Theme.accent : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: popup.toggleVrr(row.modelData.name)
                                    }
                                }
                            }

                            // Brightness slider (DDC-controllable monitors only)
                            Row {
                                visible: row.hasDdc
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
                                    text: row.percent + "%"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }

                            Text {
                                visible: !row.hasDdc
                                text: "No DDC brightness control"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }

                            // Debounced same reasoning as ShellState's sunset
                            // kelvin commit -- each ddcutil setvcp call is a
                            // slow I2C round-trip, so this waits for the drag
                            // to settle rather than firing one per pixel.
                            Timer {
                                id: commitTimer
                                interval: 200
                                onTriggered: if (row.hasDdc) popup.setBrightness(row.ddc.bus, Math.round(row.percent / 100 * row.ddc.max))
                            }
                        }
                    }

                    Text {
                        visible: Hyprland.monitors.values.length === 0
                        text: "No monitors detected"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }
        }
    }
}
