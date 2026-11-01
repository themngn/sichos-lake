import QtQuick

// Header of a Control Center page: Back, the bold title, and on the right
// whatever the page puts in it (its main switch, a pin, a text action).
// Every page used to hand-roll this row, some with a HeaderIcon and some
// without -- now one look: no icon (the main page's tile already showed it
// right before the page opened) and no separator under it, like the hub's
// own columns.
Item {
    id: header
    property string title: ""
    property bool showBack: true
    signal back()
    default property alias trailing: trailingRow.data

    width: parent ? parent.width : 0
    height: 20

    Row {
        id: leadRow
        spacing: 8
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        BackButton {
            id: backButton
            visible: header.showBack
            onClicked: header.back()
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Elides before running into the trailing controls (a long
            // network or device name as the title).
            width: Math.min(implicitWidth, header.width - (header.showBack ? backButton.width + leadRow.spacing : 0)
                - (trailingRow.width > 0 ? trailingRow.width + 12 : 0))
            elide: Text.ElideRight
            text: header.title
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            color: Theme.text
        }
    }
    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
