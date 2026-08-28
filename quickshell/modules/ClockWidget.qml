import QtQuick

Pill {
    id: root
    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    tooltipText: Qt.formatDateTime(root.now, "yyyy MMMM")
    onClicked: calendarPopup.visible = !calendarPopup.visible

    Text {
        text: Qt.formatDateTime(root.now, "ddd dd  HH:mm")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }

    CalendarPopup {
        id: calendarPopup
        anchorItem: root
    }
}
