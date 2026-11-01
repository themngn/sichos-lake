import QtQuick

// Round − / + button beside a page row's value (Stay Awake timers, Night
// Light schedule times).
Rectangle {
    id: sb
    property string glyph: ""
    signal clicked()
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: Theme.controlHeight + 2
    height: Theme.controlHeight + 2
    radius: width / 2
    opacity: sb.enabled ? 1 : 0.35
    color: sbArea.containsMouse && sb.enabled ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.08)
    Text {
        anchors.centerIn: parent
        text: sb.glyph
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
    }
    MouseArea {
        id: sbArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: sb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (sb.enabled) sb.clicked()
    }
}
