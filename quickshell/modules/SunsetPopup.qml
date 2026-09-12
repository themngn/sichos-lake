import QtQuick
import Quickshell
import Quickshell.Io

// Warm Light / Night Light popup panel for SunsetToggle.qml.
// Hover-driven with persistent hover: allows smooth interaction with the
// On/Off force switch, the independent "Follow schedule" checkbox, the
// 100K warmth slider, and the schedule time editor without focus grabs.
PopupWindow {
    id: popup

    required property Item anchorItem
    property bool active: false // mirrors ShellState.sunsetWarm
    property bool scheduleFollow: true // mirrors ShellState.sunsetScheduleFollow, fully independent of active
    property int kelvin: 2500 // last manually-set warmth

    signal setWarm(bool warm)
    signal setTemperature(int kelvin)
    signal setScheduleFollow(bool follow)
    signal scheduleSaved()

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    // HoverHandler rather than a background MouseArea: a MouseArea only reports
    // containsMouse while it's the topmost hover-accepting item, so it goes false
    // the moment the cursor is over a descendant control that sets hoverEnabled
    // itself (Save button, TimeSpinner arrows) — closing the popup mid-interaction.
    // HoverHandler tracks its own item's bounds independently of what's on top.
    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    onVisibleChanged: if (visible) loadTimes()

    readonly property int minKelvin: 2000
    readonly property int maxKelvin: 5000

    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/hypr/hyprsunset.conf"
        printErrors: false
    }

    property int dayHour: 7
    property int dayMinute: 0
    property int nightHour: 23
    property int nightMinute: 0

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    // hyprsunset.conf declares exactly two profiles, day (identity) then
    // night (temperature) — pull their "time = H:MM" values in file order.
    function loadTimes() {
        const re = /time\s*=\s*(\d{1,2}):(\d{2})/g
        const matches = []
        let m
        while ((m = re.exec(confFile.text())) !== null) matches.push(m)
        if (matches[0]) { popup.dayHour = +matches[0][1]; popup.dayMinute = +matches[0][2] }
        if (matches[1]) { popup.nightHour = +matches[1][1]; popup.nightMinute = +matches[1][2] }
    }

    function saveTimes() {
        const times = [
            popup.pad2(popup.dayHour) + ":" + popup.pad2(popup.dayMinute),
            popup.pad2(popup.nightHour) + ":" + popup.pad2(popup.nightMinute)
        ]
        let i = 0
        confFile.setText(confFile.text().replace(/time\s*=\s*\d{1,2}:\d{2}/g, () => "time = " + times[i++]))
        popup.scheduleSaved()
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
                width: 220
                height: 20

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "\uf186"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        color: Theme.accent
                    }
                    Text {
                        text: "Warm Light"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            // Force on/off switch -- always reflects/sets popup.active
            // directly. Fully independent of the "Follow schedule" switch
            // below: clicking either of these never touches scheduleFollow.
            Row {
                width: 220
                spacing: 6

                Repeater {
                    model: [
                        { on: true, label: "On" },
                        { on: false, label: "Off" }
                    ]
                    delegate: Rectangle {
                        id: modeButton
                        required property var modelData
                        readonly property bool active: popup.active === modelData.on
                        width: 107
                        height: 26
                        radius: 4
                        color: modeButton.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: modeButton.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modeButton.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: modeButton.active ? Theme.text : Theme.textMuted
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: popup.setWarm(modeButton.modelData.on)
                        }
                    }
                }
            }

            // Independent "Follow schedule" switch -- deliberately not a
            // third option in the On/Off row above, and stored as its own
            // property rather than a shared mode enum. Checking or
            // unchecking it never changes popup.active/the light itself
            // (see ShellState.setScheduleFollow) -- it only changes who
            // gets to decide going forward, so forcing on/off here never
            // knocks this switch off the way an earlier version did.
            Item {
                width: 220
                height: scheduleText.implicitHeight

                Text {
                    id: scheduleText
                    text: (popup.scheduleFollow ? "[x] " : "[ ] ") + "Follow schedule"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: scheduleArea.containsMouse ? Theme.text : Theme.textMuted
                }
                MouseArea {
                    id: scheduleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.setScheduleFollow(!popup.scheduleFollow)
                }
            }

            // Warmth slider in increments of 100K
            Column {
                width: 220
                spacing: 4

                Item {
                    width: parent.width
                    height: 14
                    Text {
                        anchors.left: parent.left
                        text: "Warmth"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        anchors.right: parent.right
                        text: popup.kelvin + "K"
                        color: popup.active && !popup.scheduleFollow ? Theme.accent : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Rectangle {
                    id: track
                    width: parent.width
                    height: 8
                    radius: 0
                    color: Qt.rgba(1, 1, 1, 0.12)
                    opacity: popup.active && !popup.scheduleFollow ? 1 : 0.5

                    readonly property real fraction: (popup.kelvin - popup.minKelvin) / (popup.maxKelvin - popup.minKelvin)

                    Rectangle {
                        width: track.width * track.fraction
                        height: parent.height
                        radius: 0
                        color: Theme.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: (mouse) => {
                            if (pressed) popup.setTemperature(popup._kelvinAt(mouse.x))
                        }
                        onPressed: (mouse) => popup.setTemperature(popup._kelvinAt(mouse.x))
                        onWheel: (wheel) => {
                            const delta = wheel.angleDelta.y > 0 ? 100 : -100
                            const newKelvin = Math.max(popup.minKelvin, Math.min(popup.maxKelvin, Math.round(popup.kelvin / 100) * 100 + delta))
                            popup.setTemperature(newKelvin)
                        }
                    }
                }
            }

            Rectangle {
                width: 220
                height: 1
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            Text {
                text: "Schedule times"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            Row {
                width: 220
                height: 22
                spacing: 6

                Text {
                    width: 40
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "Day"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textMuted
                }
                TimeSpinner {
                    value: popup.dayHour
                    max: 23
                    onChanged: (v) => popup.dayHour = v
                }
                Text {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: ":"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textMuted
                }
                TimeSpinner {
                    value: popup.dayMinute
                    max: 59
                    onChanged: (v) => popup.dayMinute = v
                }
            }

            Row {
                width: 220
                height: 22
                spacing: 6

                Text {
                    width: 40
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "Night"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textMuted
                }
                TimeSpinner {
                    value: popup.nightHour
                    max: 23
                    onChanged: (v) => popup.nightHour = v
                }
                Text {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: ":"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textMuted
                }
                TimeSpinner {
                    value: popup.nightMinute
                    max: 59
                    onChanged: (v) => popup.nightMinute = v
                }
            }

            Item {
                id: saveEntry
                width: 220
                height: saveLabel.implicitHeight + 6

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: saveArea.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : "transparent"
                }
                Text {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: "Save schedule"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.accent
                }
                MouseArea {
                    id: saveArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.saveTimes()
                }
            }
        }
    }

    function _kelvinAt(x) {
        const fraction = Math.max(0, Math.min(1, x / 220))
        const raw = popup.minKelvin + fraction * (popup.maxKelvin - popup.minKelvin)
        return Math.round(raw / 100) * 100
    }
}
