import QtQuick
import Quickshell
import Quickshell.Io

// Warm Light / Night Light popup panel for SunsetToggle.qml.
// Hover-driven with persistent hover: allows smooth interaction with the
// On/Off force switch, the independent "Follow schedule" checkbox, the
// 100K warmth slider, and the schedule time editor without focus grabs.
Item {
    id: popup

    required property Item anchorItem
    // Content for ToggleMorphPopup (the bar's one morphing card, shared by
    // every toggle-row popup): the toggle reparents this into the card and
    // drives `shown`; the card sizes itself to this item's implicit size,
    // lines up under anchorItem, and cross-fades between contents.
    property bool shown: false
    anchors.top: parent ? parent.top : undefined
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    opacity: shown ? 1 : 0
    visible: opacity > 0
    // Outgoing content clears out quickly so the two don't read as a
    // jumble mid-morph; the incoming one fades in over the full open time.
    Behavior on opacity {
        NumberAnimation { duration: shown ? Theme.openDuration : 70; easing.type: Easing.OutCubic }
    }
    property bool active: false // mirrors ShellState.sunsetWarm
    property bool scheduleFollow: true // mirrors ShellState.sunsetScheduleFollow, fully independent of active
    property int kelvin: 2500 // last manually-set warmth

    signal setWarm(bool warm)
    signal setTemperature(int kelvin)
    signal setScheduleFollow(bool follow)
    signal scheduleSaved()


    // HoverHandler rather than a background MouseArea: a MouseArea only reports
    // containsMouse while it's the topmost hover-accepting item, so it goes false
    // the moment the cursor is over a descendant control that sets hoverEnabled
    // itself (Save button, TimeSpinner arrows) — closing the popup mid-interaction.
    // HoverHandler tracks its own item's bounds independently of what's on top.
    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    onShownChanged: if (shown) loadTimes()

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

    Item {
        id: bg
        anchors.fill: parent

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            // Menu Title Header
            Item {
                width: 220
                height: 20

                PinButton {
                    toggleId: "sunset"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    HeaderIcon {
                        glyph: "\udb81\udd94"
                        color: Theme.accent
                    }
                    Text {
                        text: "Warm Light"
                        font.family: Theme.uiFontFamily
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
                        height: Theme.controlHeight
                        radius: Theme.controlRadius
                        color: modeButton.active ? Theme.selectedFill : modeArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                        border.color: modeButton.active ? Theme.accent : Theme.surfaceBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modeButton.modelData.label
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: modeButton.active ? Theme.text : Theme.textMuted
                        }

                        MouseArea {
                            id: modeArea
                            hoverEnabled: true
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
                    text: (popup.scheduleFollow ? "󰄲  " : "󰄱  ") + "Follow schedule"
                    font.family: Theme.uiFontFamily
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
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: popup.kelvin + "K"
                        color: popup.active && !popup.scheduleFollow ? Theme.accent : Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }

                Rectangle {
                    id: track
                    width: parent.width
                    height: Theme.trackHeight
                    radius: Theme.trackRadius
                    color: Theme.track
                    opacity: popup.active && !popup.scheduleFollow ? 1 : 0.5

                    readonly property real fraction: (popup.kelvin - popup.minKelvin) / (popup.maxKelvin - popup.minKelvin)

                    Rectangle {
                        width: track.width * track.fraction
                        height: parent.height
                        radius: Theme.trackRadius
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
                color: Theme.separator
            }

            Text {
                text: "Schedule times"
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
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
                    font.family: Theme.uiFontFamily
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
                    font.family: Theme.uiFontFamily
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
                height: Theme.controlHeight

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.controlRadius
                    color: saveArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                }
                Text {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: "Save schedule"
                    font.family: Theme.uiFontFamily
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
