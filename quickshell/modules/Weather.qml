import QtQuick
import Quickshell
import Quickshell.Io

// Current conditions, from weather.py (auto-detected location via IP
// geolocation, no config/API key needed). Polls infrequently.
// Hover-driven with 250ms initial delay, immediate switch between open menus,
// and persistent hover over the popup.
Pill {
    id: root

    property var tempC: null
    property var code: null
    property bool isDay: true
    property string city: ""
    property var hourly: []
    property var daily: []
    property string screenName: ""
    readonly property bool haveData: root.tempC !== null

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "weather"
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool popupHovered: popupMouseArea.containsMouse

    Timer {
        id: openDelayTimer
        interval: 250
        onTriggered: {
            if (root.hovered && root.haveData) {
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
            if (ShellState.activePopup !== "" && !root.popupOpen && root.haveData) {
                openDelayTimer.stop()
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            } else if (ShellState.activePopup === "" && !openDelayTimer.running && root.haveData) {
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

    onClicked: (mouse) => {
        if (root.haveData) {
            if (root.popupOpen) {
                ShellState.activePopup = ""
            } else {
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            }
        }
    }

    // WMO weather codes (Open-Meteo's `weather_code`) mapped to Weather
    // Icons glyphs already confirmed present in this build of JetBrainsMono
    // Nerd Font Mono.
    function iconFor(code, isDay) {
        if (code === 0) return isDay ? "" : ""
        if (code === 1 || code === 2) return isDay ? "" : ""
        if (code === 3) return ""
        if (code === 45 || code === 48) return ""
        if ([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82].indexOf(code) !== -1) {
            return isDay ? "" : ""
        }
        if ([71, 73, 75, 77, 85, 86].indexOf(code) !== -1) return ""
        if ([95, 96, 99].indexOf(code) !== -1) return ""
        return ""
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.haveData
        text: root.haveData ? root.iconFor(root.code, root.isDay) : ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * 2
        color: Theme.text
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.haveData ? Math.round(root.tempC) + "°C" : "—"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }

    Process {
        id: weatherProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.tempC = data.tempC
                    root.code = data.code
                    root.isDay = data.isDay
                    root.city = data.city
                    root.hourly = data.hourly || []
                    root.daily = data.daily || []
                } catch (e) {
                    root.tempC = null
                }
            }
        }
    }

    Timer {
        interval: 900000 // 15 min
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    PopupWindow {
        id: popup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        visible: root.popupOpen && root.haveData

        implicitWidth: 340
        implicitHeight: bg.implicitHeight

        Rectangle {
            id: bg
            width: 340
            implicitWidth: 340
            implicitHeight: content.implicitHeight + 24
            color: "#1c1c1c"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 6

            MouseArea {
                id: popupMouseArea
                anchors.fill: parent
                hoverEnabled: true
                z: -1
            }

            Column {
                id: content
                width: 316
                anchors {
                    top: parent.top
                    topMargin: 12
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 10

                // Menu Title Header
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "󰖐"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            color: Theme.accent
                        }
                        Text {
                            text: "Weather"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.city
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                }

                // Current conditions
                Item {
                    width: parent.width
                    height: headerIcon.implicitHeight

                    Row {
                        id: headerRow
                        spacing: 10
                        Text {
                            id: headerIcon
                            text: root.iconFor(root.code, root.isDay)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize * 3
                            color: Theme.text
                        }
                        Text {
                            anchors.verticalCenter: headerIcon.verticalCenter
                            text: Math.round(root.tempC) + "°C"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 4
                            font.bold: true
                            color: Theme.text
                        }
                    }
                }

                Text {
                    text: "Today"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Row {
                    width: parent.width

                    Repeater {
                        model: root.hourly
                        delegate: Column {
                            id: hourDelegate
                            required property var modelData
                            width: content.width / 8
                            spacing: 3

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: hourDelegate.modelData.hour.substring(0, 2)
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.iconFor(hourDelegate.modelData.code, true)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize * 2
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(hourDelegate.modelData.tempC) + "°"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                    }
                }

                Text {
                    text: "This Week"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Column {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.daily
                        delegate: Item {
                            id: dayDelegate
                            required property var modelData
                            required property int index
                            width: content.width
                            height: dayIcon.implicitHeight

                            Text {
                                id: dayName
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                text: dayDelegate.index === 0 ? "Today"
                                    : Qt.formatDate(new Date(dayDelegate.modelData.date), "ddd")
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                id: dayIcon
                                anchors {
                                    left: dayName.right
                                    leftMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: root.iconFor(dayDelegate.modelData.code, true)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize * 2
                            }
                            Row {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: dayIcon.right
                                    leftMargin: 8
                                }
                                spacing: 3
                                visible: dayDelegate.modelData.precipProb >= 20

                                Text {
                                    text: ""
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    text: dayDelegate.modelData.precipProb + "%"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                            Text {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                text: Math.round(dayDelegate.modelData.tempMin) + "° / "
                                    + Math.round(dayDelegate.modelData.tempMax) + "°"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                    }
                }
            }
        }
    }
}
