import QtQuick

// On/off switch for popup headers (Wi-Fi, Bluetooth power).
Rectangle {
    id: root
    property bool checked: false
    signal toggled()

    implicitWidth: 36
    implicitHeight: 20
    radius: height / 2
    color: root.checked ? Theme.accent : Theme.track
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        width: parent.height - 4
        height: width
        radius: width / 2
        y: 2
        x: root.checked ? parent.width - width - 2 : 2
        color: Theme.text
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
