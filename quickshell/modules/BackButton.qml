import QtQuick

// Back arrow at the start of a submenu header (the Control Center's Sound,
// Bluetooth and Display pages). A full control-sized "‹ Back" button
// rather than a bare chevron, which was too small a target.
Rectangle {
    id: root
    signal clicked()

    implicitWidth: label.implicitWidth + 20
    implicitHeight: Theme.controlHeight
    radius: Theme.controlRadius
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: area.containsMouse ? Theme.hoverFill : Theme.controlFill

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf053" // nf-fa-chevron_left
            color: area.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Back"
            color: area.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
