import QtQuick

// The bar's clock, with the current weather after the time. A click
// opens the hub (Hub.qml -- notifications, calendar, weather, Control
// Center in one card hanging from here) or closes it; it used to open a small calendar on hover, which the hub's
// Today column replaced. Click-only like the Control Center pill: the hub
// gets worked in, so hovering past the clock shouldn't throw one open.
Pill {
    id: root
    property date now: new Date()
    property string screenName: ""
    // Set by Bar.qml.
    property Item hub: null

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    onClicked: if (root.hub) root.hub.toggle()

    // The bar's Weather pill (hidden, kept as the data source -- see
    // Bar.qml): its conditions ride along after the time, so date, time and
    // weather are one pill and one click away from the hub's forecast.
    property var weather: null
    readonly property bool _haveWeather: !!root.weather && root.weather.haveData

    Text {
        // Centred, not top-aligned: the weather glyph's large font makes
        // the Row taller than the bar, and an unanchored Text sits at its top.
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        text: Qt.formatDateTime(root.now, TimeRegion.use24Hour ? "ddd dd  HH:mm" : "ddd dd  h:mm AP")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }
    Item { visible: root._haveWeather; width: 4; height: 1 }
    Text {
        visible: root._haveWeather
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        text: root._haveWeather ? root.weather.iconFor(root.weather.code, root.weather.isDay) : ""
        font.family: Theme.fontFamily
        // Same size the Weather pill gave it (barIconScale like every bar icon).
        font.pixelSize: Theme.fontSize * 2 * Theme.barIconScale
        color: Theme.text
    }
    Text {
        visible: root._haveWeather
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        text: root._haveWeather ? Math.round(root.weather.tempC) + "°C" : ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }

    // Hover outline, and held while the hub is open, so the card reads as
    // hanging from the clock. An explicit parent rather than a child --
    // Pill's default property would lay it out next to the text.
    readonly property Item _highlight: Rectangle {
        parent: root
        z: -1
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        radius: Theme.barItemRadius
        color: Theme.barItemHover
        opacity: root.hovered || (root.hub && root.hub.open) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
    }
}
