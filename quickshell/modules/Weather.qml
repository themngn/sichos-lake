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
        // Same barIconScale every other bar icon (BarIcon.qml, Tray.qml,
        // Volume.qml, the toggle glyphs) grows/shrinks with, so this one
        // moves together with the rest instead of drifting independently.
        font.pixelSize: Theme.fontSize * 2 * Theme.barIconScale
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

    // Short description of a WMO code, for the hero line under the
    // temperature (same grouping as iconFor, a bit finer for intensity).
    function textFor(code) {
        if (code === 0) return "Clear"
        if (code === 1) return "Mostly clear"
        if (code === 2) return "Partly cloudy"
        if (code === 3) return "Overcast"
        if (code === 45 || code === 48) return "Fog"
        if ([51, 53, 55].indexOf(code) !== -1) return "Drizzle"
        if ([56, 57, 66, 67].indexOf(code) !== -1) return "Freezing rain"
        if (code === 61 || code === 80) return "Light rain"
        if (code === 63 || code === 81) return "Rain"
        if (code === 65 || code === 82) return "Heavy rain"
        if ([71, 73, 75, 77, 85, 86].indexOf(code) !== -1) return "Snow"
        if ([95, 96, 99].indexOf(code) !== -1) return "Thunderstorm"
        return ""
    }

    // Week-wide temperature span: every day's range bar is laid out on this
    // shared scale, so the bars line up and read against each other.
    readonly property real weekMin: root.daily.length
        ? Math.min.apply(null, root.daily.map(d => d.tempMin)) : 0
    readonly property real weekMax: root.daily.length
        ? Math.max.apply(null, root.daily.map(d => d.tempMax)) : 1
    readonly property var today: root.daily.length ? root.daily[0] : null

    // Set by Bar.qml: the bar's MorphPopup card (see MorphContent.qml).
    property Item popupHost: null
    readonly property Item _popupContent: MorphContent {
        id: popup
        parent: root.popupHost
        anchorItem: root
        shown: root.popupOpen && root.haveData

        implicitWidth: 340
        implicitHeight: bg.implicitHeight

        Item {
            id: bg
            width: 340
            implicitWidth: 340
            implicitHeight: content.implicitHeight + 2 * Theme.surfacePadding

            MouseArea {
                id: popupMouseArea
                anchors.fill: parent
                hoverEnabled: true
                z: -1
            }

            Column {
                id: content
                width: parent.width - 2 * Theme.surfacePadding
                anchors {
                    top: parent.top
                    topMargin: Theme.surfacePadding
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: Theme.sectionSpacing

                // Menu Title Header
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        HeaderIcon {
                            glyph: "󰖐"
                            color: Theme.accent
                        }
                        Text {
                            text: "Weather"
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.city
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }
                }

                // Hero: big icon + temperature + condition on the left,
                // today's high/low on the right.
                Item {
                    width: parent.width
                    height: Math.max(heroLeft.implicitHeight, heroRight.implicitHeight)

                    Row {
                        id: heroLeft
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.iconFor(root.code, root.isDay)
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(Theme.fontSize * 3.6)
                            color: Theme.text
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: Math.round(root.tempC) + "°"
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Math.round(Theme.fontSize * 2.6)
                                font.weight: Font.DemiBold
                                color: Theme.text
                            }
                            Text {
                                text: root.textFor(root.code)
                                visible: text !== ""
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textMuted
                            }
                        }
                    }

                    Column {
                        id: heroRight
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.today !== null
                        spacing: 4

                        Repeater {
                            model: root.today ? [
                                { label: "High", value: root.today.tempMax },
                                { label: "Low", value: root.today.tempMin }
                            ] : []
                            delegate: Row {
                                id: hlRow
                                required property var modelData
                                anchors.right: parent.right
                                spacing: 6
                                Text {
                                    anchors.baseline: hlValue.baseline
                                    text: hlRow.modelData.label
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    color: Theme.textDim
                                }
                                Text {
                                    id: hlValue
                                    text: Math.round(hlRow.modelData.value) + "°"
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.text
                                }
                            }
                        }
                    }
                }

                // Feels like / humidity / wind: three equal cells on one
                // strip, so they share a baseline instead of being placed at
                // hand-picked x-fractions of the width.
                Rectangle {
                    width: parent.width
                    height: statsRow.implicitHeight + 16
                    radius: Theme.controlRadius
                    color: Theme.controlFill
                    visible: root.feelsLikeC !== null

                    Row {
                        id: statsRow
                        anchors.centerIn: parent
                        width: parent.width

                        Repeater {
                            model: [
                                { icon: "", label: "Feels like",
                                  value: Math.round(root.feelsLikeC) + "°" },
                                { icon: "", label: "Humidity",
                                  value: root.humidity + "%" },
                                { icon: "", label: "Wind",
                                  value: Math.round(root.windKph) + " km/h" }
                            ]
                            delegate: Item {
                                id: statCell
                                required property var modelData
                                required property int index
                                width: statsRow.width / 3
                                height: statCol.implicitHeight

                                Rectangle {
                                    visible: statCell.index > 0
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 1
                                    height: parent.height
                                    color: Theme.separator
                                }

                                Column {
                                    id: statCol
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 2
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 5
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: statCell.modelData.icon
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize + 1
                                            color: Theme.accent
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: statCell.modelData.value
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 1
                                            color: Theme.text
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: statCell.modelData.label
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                        color: Theme.textMuted
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "Next hours"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Row {
                    width: parent.width

                    Repeater {
                        model: root.hourly
                        delegate: Column {
                            id: hourDelegate
                            required property var modelData
                            required property int index
                            width: content.width / Math.max(1, root.hourly.length)
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: hourDelegate.index === 0 ? "Now"
                                    : hourDelegate.modelData.hour.substring(0, 2)
                                color: hourDelegate.index === 0 ? Theme.text : Theme.textDim
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 3
                                font.bold: hourDelegate.index === 0
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                // Older caches (before weather.py emitted a
                                // per-hour isDay) fall back to the day icon.
                                text: root.iconFor(hourDelegate.modelData.code,
                                    hourDelegate.modelData.isDay !== undefined ? hourDelegate.modelData.isDay : true)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.round(Theme.fontSize * 2.8)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(hourDelegate.modelData.tempC) + "°"
                                color: Theme.text
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
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
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }
                }

                Text {
                    text: "This week"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                // Day | icon | rain chance | low ━━━━ high. Fixed-width
                // columns so every row's range bar starts and ends at the
                // same x; the bar fills the week-wide span (weekMin..weekMax)
                // from this day's low to its high.
                Column {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.daily
                        delegate: Item {
                            id: dayDelegate
                            required property var modelData
                            required property int index
                            readonly property bool rainy: (modelData.precipProb || 0) >= 20
                            width: content.width
                            height: Math.round(Theme.fontSize * 2.8)

                            Text {
                                id: dayName
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 42
                                text: dayDelegate.index === 0 ? "Today"
                                    : Qt.formatDate(new Date(dayDelegate.modelData.date), "ddd")
                                color: Theme.text
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: dayDelegate.index === 0
                            }
                            Text {
                                id: dayIcon
                                anchors.left: dayName.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                horizontalAlignment: Text.AlignHCenter
                                text: root.iconFor(dayDelegate.modelData.code, true)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.round(Theme.fontSize * 2.8)
                            }
                            // Rain chance only when it's worth noticing --
                            // the slot keeps its width either way.
                            Item {
                                id: rainSlot
                                anchors.left: dayIcon.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                height: parent.height
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dayDelegate.rainy
                                    spacing: 2
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ""
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: dayDelegate.modelData.precipProb + "%"
                                        color: Theme.accent
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                }
                            }
                            Text {
                                id: lowText
                                anchors.left: rainSlot.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(dayDelegate.modelData.tempMin) + "°"
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                id: highText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(dayDelegate.modelData.tempMax) + "°"
                                color: Theme.text
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Rectangle {
                                id: rangeTrack
                                anchors.left: lowText.right
                                anchors.leftMargin: 10
                                anchors.right: highText.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                height: 4
                                radius: Theme.trackRadius
                                color: Theme.track

                                readonly property real span: Math.max(1, root.weekMax - root.weekMin)
                                function xFor(t) {
                                    return (t - root.weekMin) / span * width
                                }

                                Rectangle {
                                    x: rangeTrack.xFor(dayDelegate.modelData.tempMin)
                                    width: Math.max(parent.height,
                                        rangeTrack.xFor(dayDelegate.modelData.tempMax) - x)
                                    height: parent.height
                                    radius: Theme.trackRadius
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Theme.accent }
                                        GradientStop { position: 1; color: Theme.success }
                                    }
                                }
                                // Today only: where the current temperature
                                // sits within the day's range.
                                Rectangle {
                                    visible: dayDelegate.index === 0
                                    width: 8
                                    height: 8
                                    radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(rangeTrack.width,
                                        rangeTrack.xFor(root.tempC))) - width / 2
                                    color: Theme.text
                                    border.color: Theme.surface
                                    border.width: 2
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
