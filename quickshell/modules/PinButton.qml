import QtQuick

// Pin icon for the top-right of a toggle popup's header (SunsetPopup,
// IdlePopup, HdrPopup, GameFocusPopup, MicPopup). Pinned (the default): the
// toggle stays visible in the collapsed toggle row while it's on. Unpinned:
// it collapses with the rest of the row even while on, showing only on hover
// -- see BarSettings.isPinned() and each *Toggle.qml's `shown`.
Text {
    id: pin

    required property string toggleId
    readonly property bool pinned: BarSettings.isPinned(pin.toggleId)

    text: pin.pinned ? "󰐃" : "󰐄"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    color: pin.pinned ? Theme.accent : pinArea.containsMouse ? Theme.text : Theme.textDim

    MouseArea {
        id: pinArea
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: BarSettings.togglePin(pin.toggleId)
    }
}
