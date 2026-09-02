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
    property var feelsLikeC: null
    property var humidity: null
    property var windKph: null
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

    function _applyData(data) {
        if (data.tempC === undefined || data.tempC === null) return false
        root.tempC = data.tempC
        root.code = data.code
        root.isDay = data.isDay
        root.city = data.city
        root.feelsLikeC = data.feelsLikeC !== undefined ? data.feelsLikeC : null
        root.humidity = data.humidity !== undefined ? data.humidity : null
        root.windKph = data.windKph !== undefined ? data.windKph : null
        root.hourly = data.hourly || []
        root.daily = data.daily || []
        return true
    }

    // weather.py re-runs from scratch on every quickshell (re)start with no
    // memory of its own, so without this the pill goes blank for however
    // long the two network calls take. weather.py maintains this same file
    // as its own on-disk cache (mirroring exactly what it last emitted), so
    // reading it here shows the last known reading on the very first frame;
    // the Process below then overwrites it with a fresh poll shortly after.
    FileView {
        id: cacheFile
        path: Quickshell.env("HOME") + "/.config/quickshell/weather-cache.json"
        printErrors: false
        onLoaded: {
            try {
                root._applyData(JSON.parse(text()))
            } catch (e) { /* no cache yet -- stays blank until the process finishes */ }
        }
    }

    Process {
        id: weatherProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (!root._applyData(JSON.parse(text)))
                        root.tempC = null
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

                // Current conditions: icon+temp, feels-like, humidity,
                // and wind spread across four equal-width slots spanning
                // the full popup width, same "divide the width evenly"
                // approach as the hourly forecast row further down.
                Item {
                    width: parent.width
                    height: headerIcon.implicitHeight

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 0
                        spacing: 8
                        Text {
                            id: headerIcon
                            text: root.iconFor(root.code, root.isDay)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize * 3
                            color: Theme.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(root.tempC) + "°C"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * 0.30
                        visible: root.feelsLikeC !== null
                        spacing: 8

                        Column {
                            id: feelsLabel
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: "Feels"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Text {
                                text: "like:"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        Text {
                            anchors.verticalCenter: feelsLabel.verticalCenter
                            text: Math.round(root.feelsLikeC) + "°"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * 0.58
                        visible: root.feelsLikeC !== null
                        spacing: 6
                        Text {
                            id: humidityIcon
                            text: ""
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                        }
                        Text {
                            anchors.verticalCenter: humidityIcon.verticalCenter
                            text: root.humidity + "%"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * 0.80
                        visible: root.feelsLikeC !== null
                        spacing: 6
                        Text {
                            id: windIcon
                            text: ""
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                        }
                        Text {
                            anchors.verticalCenter: windIcon.verticalCenter
                            text: Math.round(root.windKph) + " km/h"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
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
                            // Empty (not visible:false) so every column keeps
                            // the same height whether or not it has a
                            // reading to show -- otherwise the row above
                            // (temp) ends up at different y-positions across
                            // columns depending on which hours are rainy.
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (hourDelegate.modelData.precipProb || 0) >= 20
                                    ? hourDelegate.modelData.precipProb + "%" : ""
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
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
                                Text {
                                    text: ""
                                    color: dayDelegate.modelData.precipProb >= 20 ? Theme.accent : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    text: dayDelegate.modelData.precipProb + "%"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    text: dayDelegate.modelData.precipMm > 0
                                        ? " · " + dayDelegate.modelData.precipMm.toFixed(1) + "mm" : ""
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
