import QtQuick

// Previous / play / next on a cover, shown only while the cover is hovered --
// so moving a card's fader never brings them up, and a paused source stays a
// clean card (the record, half tucked and still, says it's paused). Fills the cover; has
// nothing for a source without a player (a game, a call).
Item {
    id: cc
    required property var source
    // Width of the wash's fade into the card, matching the cover's own.
    property int fade: 0
    // Pushes the buttons right, for a card that keeps its icon beside them.
    property real offset: 0
    property int buttonSize: 34
    // No cover to protect the buttons from: no dark wash.
    property bool wash: true

    readonly property bool show: !!cc.source.player && hover.hovered

    HoverHandler { id: hover }

    Rectangle {
        anchors.fill: parent
        visible: cc.wash
        opacity: cc.show ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.42) }
            GradientStop { position: cc.width > 0 ? (cc.width - cc.fade) / cc.width : 1; color: Qt.rgba(0, 0, 0, 0.42) }
            GradientStop { position: 1; color: cc.fade > 0 ? "transparent" : Qt.rgba(0, 0, 0, 0.42) }
        }
    }

    Row {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: cc.offset
        opacity: cc.show ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // A button that can't do anything isn't shown, but keeps its place so
        // play stays centered.
        MediaButton {
            size: cc.buttonSize
            glyph: "\u{f04ae}" // nf-md-skip_previous
            enabledState: !!cc.source.player && cc.source.player.canGoPrevious
            opacity: enabledState ? 1 : 0
            onClicked: cc.source.player.previous()
        }
        MediaButton {
            size: cc.buttonSize
            glyph: cc.source.player && cc.source.player.isPlaying ? "\u{f03e4}" : "\u{f040a}" // pause / play
            enabledState: !!cc.source.player && cc.source.player.canTogglePlaying
            onClicked: cc.source.player.togglePlaying()
        }
        MediaButton {
            size: cc.buttonSize
            glyph: "\u{f04ad}" // nf-md-skip_next
            enabledState: !!cc.source.player && cc.source.player.canGoNext
            opacity: enabledState ? 1 : 0
            onClicked: cc.source.player.next()
        }
    }
}
