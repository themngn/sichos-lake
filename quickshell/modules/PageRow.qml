import QtQuick

// One row on a Control Center page, in the main page's tile style: a filled
// rounded row with a round icon badge (accent while `active`), a bold title
// and a muted status line, and on the right the row's own controls
// (children: a Switch, buttons) and/or a chevron strip that opens more.
// `compact` is for long lists (networks, devices, servers): shorter, smaller
// badge. `badge` takes custom content in place of the glyph (a flag, a
// device picture).
Rectangle {
    id: row
    property string glyph: ""
    property string title: ""
    property string titleTail: ""   // short muted note after the title
    property string subtitle: ""
    property color subtitleColor: Theme.textMuted
    property bool active: false     // accent badge
    property bool selected: false   // accent fill (the current device etc.)
    property bool compact: false
    property bool clickable: true
    property bool chevron: false
    property bool busy: false
    // Greyed and inert -- for a setting this device can't do, kept in
    // place so picking another device never reshuffles the page.
    property bool available: true
    property real glyphInkWidth: 24 * 0.8
    default property alias trailing: trailingRow.data
    property alias badge: badgeSlot.data
    signal clicked()
    signal more()

    readonly property bool hovered: area.containsMouse || moreArea.containsMouse
    readonly property real badgeSize: row.compact ? 28 : 32

    width: parent ? parent.width : 0
    height: row.compact ? 44 : 52
    radius: Theme.controlRadius
    opacity: row.available ? 1 : 0.45
    color: row.selected ? Theme.selectedFill
        : area.containsMouse && row.clickable && row.available ? Theme.hoverFill : Theme.controlFill
    scale: area.pressed && row.clickable ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: row.available
        hoverEnabled: true
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (row.clickable) row.clicked()
    }

    Rectangle {
        id: badgeBg
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: row.badgeSize
        height: row.badgeSize
        radius: width / 2
        color: row.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
        HeaderIcon {
            visible: row.glyph !== "" && badgeSlot.children.length === 0
            anchors.centerIn: parent
            glyph: row.glyph
            inkHeight: row.compact ? 13 : 15
            inkWidth: row.glyphInkWidth * (row.compact ? 0.85 : 1)
            color: row.active ? Theme.text : Theme.textMuted
            opacity: row.busy ? 0.5 : 1
            SequentialAnimation on opacity {
                running: row.busy
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.35; duration: 500 }
                NumberAnimation { from: 0.35; to: 1; duration: 500 }
            }
        }
        Item {
            id: badgeSlot
            anchors.fill: parent
        }
    }

    Column {
        anchors.left: badgeBg.right
        anchors.leftMargin: 10
        anchors.right: trailingRow.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Row {
            width: parent.width
            spacing: 6
            Text {
                id: titleText
                width: Math.min(implicitWidth, parent.width - (tailText.visible ? tailText.implicitWidth + parent.spacing : 0))
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: row.compact ? Theme.fontSize - 1 : Theme.fontSize
                font.bold: true
            }
            Text {
                id: tailText
                visible: text !== ""
                anchors.verticalCenter: titleText.verticalCenter
                text: row.titleTail
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
        Text {
            visible: text !== ""
            width: parent.width
            text: row.subtitle
            elide: Text.ElideRight
            color: row.subtitleColor
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Row {
        id: trailingRow
        anchors.right: moreStrip.visible ? moreStrip.left : parent.right
        anchors.rightMargin: moreStrip.visible ? 2 : 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }

    // The tiles' chevron strip: full height, its own hover.
    Rectangle {
        id: moreStrip
        visible: row.chevron
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 30
        radius: Theme.controlRadius
        color: moreArea.containsMouse ? Theme.hoverFill : "transparent"
        Text {
            anchors.centerIn: parent
            text: "\u{f054}" // nf-fa-chevron_right
            color: moreArea.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        MouseArea {
            id: moreArea
            anchors.fill: parent
            enabled: row.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.more()
        }
    }
}
