import QtQuick
import Quickshell
import Quickshell.Io

// Idle timeout settings popup panel for IdleToggle.qml.
// Hover-driven with persistent hover: allows adjusting lock, dim, and screen-off
// timers and Never toggles smoothly without focus grabs.
PopupWindow {
    id: popup

    required property Item anchorItem
    property bool active: false

    signal settingsSaved()

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    // HoverHandler rather than a background MouseArea: a MouseArea only reports
    // containsMouse while it's the topmost hover-accepting item, so it goes false
    // the moment the cursor is over a descendant control that sets hoverEnabled
    // itself (Save button, Never checkboxes, TimeSpinner arrows) — closing the
    // popup mid-interaction. HoverHandler tracks its own item's bounds
    // independently of what's on top.
    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    onVisibleChanged: if (visible) loadSettings()

    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"
        printErrors: false
    }

    property bool lockNever: false
    property int lockHours: 0
    property int lockMinutes: 5

    property bool dimNever: false
    property int dimSeconds: 15 // lead time before the lock, not an absolute idle time

    property bool offNever: false
    property int offHours: 0
    property int offMinutes: 10

    function loadSettings() {
        const text = confFile.text()
        const dimMatch = /listener\s*\{\s*timeout\s*=\s*(\d+)\s*\n\s*on-timeout\s*=\s*quickshell ipc call idledim/.exec(text)
        const lockMatch = /listener\s*\{\s*timeout\s*=\s*(\d+)\s*\n\s*on-timeout\s*=\s*pidof hyprlock/.exec(text)
        const offMatch = /listener\s*\{\s*timeout\s*=\s*(\d+)\s*\n\s*on-timeout\s*=\s*hyprctl eval[^\n]*dpms/.exec(text)

        popup.lockNever = !lockMatch
        if (lockMatch) {
            const total = +lockMatch[1]
            popup.lockHours = Math.floor(total / 3600)
            popup.lockMinutes = Math.floor((total % 3600) / 60)
        }

        popup.offNever = !offMatch
        if (offMatch) {
            const total = +offMatch[1]
            popup.offHours = Math.floor(total / 3600)
            popup.offMinutes = Math.floor((total % 3600) / 60)
        }

        popup.dimNever = !dimMatch
        if (dimMatch && lockMatch) popup.dimSeconds = Math.max(0, +lockMatch[1] - +dimMatch[1])
    }

    function saveSettings() {
        let listeners = ""
        if (!popup.lockNever) {
            const lockSec = popup.lockHours * 3600 + popup.lockMinutes * 60
            if (!popup.dimNever) {
                const dimSec = Math.max(0, lockSec - popup.dimSeconds)
                // Software dim (IdleDimOverlay.qml), not brightnessctl -- a
                // backlight write only ever dims the laptop panel, leaving
                // external/DDC-less monitors undimmed. See
                // IdleDimOverlay.qml's header for the full rationale.
                listeners += "listener {\n    timeout = " + dimSec
                    + "\n    on-timeout = quickshell ipc call idledim dim\n    on-resume = quickshell ipc call idledim undim\n}\n\n"
            }
            listeners += "listener {\n    timeout = " + lockSec
                + "\n    on-timeout = pidof hyprlock || hyprlock\n}\n\n"
        }
        if (!popup.offNever) {
            const offSec = popup.offHours * 3600 + popup.offMinutes * 60
            listeners += "listener {\n    timeout = " + offSec
                + "\n    on-timeout = hyprctl eval 'hl.dispatch(hl.dsp.dpms(\"off\"))'"
                + "\n    on-resume = hyprctl eval 'hl.dispatch(hl.dsp.dpms(\"on\"))'\n}\n"
        }

        const text = confFile.text()
        confFile.setText(/listener\s*\{/.test(text)
            ? text.replace(/listener\s*\{[\s\S]*/, listeners)
            : text.replace(/\s*$/, "\n") + listeners)
        popup.settingsSaved()
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

            // Menu Title Header
            Item {
                width: 260
                height: 20

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "\udb80\udd76"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        color: popup.active ? Theme.accent : Theme.textDim
                    }
                    Text {
                        text: "Stay Awake"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            // Lock
            Column {
                width: 260
                spacing: 4

                Row {
                    width: 260
                    height: 22
                    spacing: 6
                    opacity: popup.lockNever ? 0.4 : 1

                    Text {
                        width: 66
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: "Lock after"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                    TimeSpinner {
                        value: popup.lockHours
                        max: 23
                        onChanged: (v) => popup.lockHours = v
                    }
                    Text {
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: "h"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                    TimeSpinner {
                        value: popup.lockMinutes
                        max: 59
                        onChanged: (v) => popup.lockMinutes = v
                    }
                    Text {
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: "min"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                }

                NeverCheckbox {
                    checked: popup.lockNever
                    onToggled: popup.lockNever = !popup.lockNever
                }
            }

            // Dim before lock
            Column {
                width: 260
                spacing: 4
                opacity: popup.lockNever ? 0.4 : 1

                Row {
                    width: 260
                    height: 22
                    spacing: 6
                    opacity: popup.dimNever ? 0.4 : 1

                    Text {
                        width: 130
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: "Dim before lock"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                    TimeSpinner {
                        value: popup.dimSeconds
                        max: 59
                        onChanged: (v) => popup.dimSeconds = v
                    }
                    Text {
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: "sec"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                }

                NeverCheckbox {
                    label: "No dim"
                    checked: popup.dimNever
                    onToggled: popup.dimNever = !popup.dimNever
                }
            }

            // Screen off
            Column {
                width: 260
                spacing: 4

                Row {
                    width: 260
                    height: 22
                    spacing: 6
                    opacity: popup.offNever ? 0.4 : 1

                    Text {
                        width: 66
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: "Screen off"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                    TimeSpinner {
                        value: popup.offHours
                        max: 23
                        onChanged: (v) => popup.offHours = v
                    }
                    Text {
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: "h"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                    TimeSpinner {
                        value: popup.offMinutes
                        max: 59
                        onChanged: (v) => popup.offMinutes = v
                    }
                    Text {
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: "min"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                }

                NeverCheckbox {
                    checked: popup.offNever
                    onToggled: popup.offNever = !popup.offNever
                }
            }

            Item {
                id: saveEntry
                width: 260
                height: saveLabel.implicitHeight + 6

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: saveArea.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : "transparent"
                }
                Text {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: "Save"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.accent
                }
                MouseArea {
                    id: saveArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.saveSettings()
                }
            }
        }
    }

    component NeverCheckbox: Item {
        id: checkbox
        property bool checked: false
        property string label: "Never"
        signal toggled()

        width: checkText.implicitWidth
        height: checkText.implicitHeight

        Text {
            id: checkText
            text: (checkbox.checked ? "[x] " : "[ ] ") + checkbox.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            color: checkArea.containsMouse ? Theme.text : Theme.textMuted
        }
        MouseArea {
            id: checkArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: checkbox.toggled()
        }
    }
}
