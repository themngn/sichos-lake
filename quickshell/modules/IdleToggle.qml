import QtQuick

Pill {
    id: root
    property bool active: false
    signal toggle()

    tooltipText: active ? "Idle inhibitor: on" : "Idle inhibitor: off"
    onClicked: root.toggle()
    opacity: root.active ? 1 : 0.5

    Text {
        text: ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: root.active ? Theme.text : Theme.textMuted
    }
}
