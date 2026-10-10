import QtQuick

// "Bar on this screen only" toggle (ShellState.barSoloScreen). No popup,
// same shape as TransparencyToggle. Clicking it pins the bar to the screen
// this pill lives on (screenName) and hides it everywhere else; since the
// only bar left visible is the pinned one, clicking again always unpins.
Pill {
    id: root
    property string screenName: ""
    property bool active: false
    // Set externally by Bar.qml, same as TransparencyToggle's.
    property bool revealed: true
    signal toggle()

    tooltipText: root.active ? "Bar on this screen only (click to show on all)" : "Bar on all screens (click for this screen only)"
    readonly property bool shown: root.active || root.revealed
    opacity: root.shown ? (root.active ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    // Width collapse rather than just a fade -- see TransparencyToggle.
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    onClicked: root.toggle()

    Text {
        text: "󰍹"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.active ? Theme.text : Theme.textMuted
    }
}
