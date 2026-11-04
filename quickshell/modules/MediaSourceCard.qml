import QtQuick
import Quickshell.Widgets

// A source below the lead: a 124px cover slot, title, subtitle and fader, with
// a quiet playbar along the top edge. Every card has the same size and the
// fader in the same place (the banner's lines up with it too), whatever fills
// the slot: wide art fades into the card, a 1:1 cover is a sleeve with a
// record, and no cover is the app's icon, which slides aside for the buttons.
ClippingRectangle {
    id: card
    required property var source
    readonly property int coverWidth: 124
    height: 72
    radius: Theme.controlRadius
    color: Theme.controlFill

    Rectangle {
        anchors.fill: parent
        visible: card.source.hasTint
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: card.source.tint }
            GradientStop { position: card.width > 0 ? card.coverWidth / card.width : 0; color: card.source.tint }
            GradientStop { position: 1; color: card.source.tintDeep }
        }
    }

    // Clicking the card (not its controls, declared after so they stay on
    // top) makes it the lead -- the same swap as a source starting to play.
    MouseArea {
        anchors.fill: parent
        enabled: card.source.isPlayer
        cursorShape: Qt.PointingHandCursor
        onClicked: card.source.makeLead()
    }
    Item {
        id: cover
        width: card.coverWidth
        height: parent.height

        // Wide art.
        Image {
            anchors.fill: parent
            visible: card.source.hasArt && !card.source.square
            source: visible ? card.source.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            sourceSize.height: 144
        }
        // 1:1 art: the record behind its sleeve.
        MediaRecord {
            visible: card.source.square
            x: 52
            y: 4
            art: visible ? card.source.art : ""
            playing: card.source.isPlaying
        }
        Image {
            visible: card.source.square
            width: parent.height
            height: parent.height
            source: visible ? card.source.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            sourceSize.height: 144
        }
        // The slot's right edge dissolving into the card: the art's own for
        // wide art, only past the record for a 1:1 cover.
        Rectangle {
            visible: card.source.hasArt
            anchors.right: parent.right
            width: card.source.square ? 24 : 48
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(card.source.tint.r, card.source.tint.g, card.source.tint.b, 0) }
                GradientStop { position: 1; color: card.source.tint }
            }
        }
        // No cover: the same icon, the same size in both states; only its
        // place changes, to make room for the buttons.
        Item {
            id: iconBox
            visible: !card.source.hasArt
            anchors.centerIn: parent
            width: 32
            height: 32
            readonly property real aside: card.source.canSkip ? -43 : -18
            transform: Translate {
                x: controls.show ? iconBox.aside : 0
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
            }
            IconImage {
                anchors.fill: parent
                visible: card.source.icon !== ""
                source: card.source.icon
                implicitSize: 32
            }
            Text {
                anchors.centerIn: parent
                visible: card.source.icon === ""
                text: "\u{f075a}" // nf-md-music_note
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 10
            }
        }
        MediaCoverControls {
            id: controls
            anchors.fill: parent
            source: card.source
            fade: 48
            wash: card.source.hasArt
            offset: card.source.hasArt ? 0 : (card.source.canSkip ? 15 : 18)
            buttonSize: !card.source.hasArt && card.source.canSkip ? 28 : 34
        }
    }

    Column {
        x: card.coverWidth + 10
        width: card.width - x - 9
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            height: 16
            verticalAlignment: Text.AlignVCenter
            text: card.source.title
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Text {
            width: parent.width
            height: 14
            verticalAlignment: Text.AlignVCenter
            text: card.source.subtitle
            elide: Text.ElideRight
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        SliderRow {
            width: parent.width
            compact: true
            hasMore: false
            maxValue: 1.5
            // A player with no stream yet has nothing to set the volume of.
            enabled: !!card.source.app
            opacity: enabled ? 1 : 0.5
            glyph: card.source.muted ? "\u{f0581}" : "\u{f057e}" // nf-md-volume_off / volume_high
            dim: card.source.muted
            value: card.source.volume
            onGlyphClicked: card.source.toggleMute()
            onMoved: (v) => card.source.setVolume(v)
        }
    }

    // The playbar: 2px and dim, so it's a detail on a card rather than a line
    // competing with the fader. Grabbed by a taller area than it draws.
    Rectangle {
        visible: card.source.hasLength
        width: parent.width
        height: 2
        color: Qt.rgba(1, 1, 1, 0.1)
        Rectangle {
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.6)
            width: parent.width * card.source.progress
            Behavior on width {
                enabled: card.source.isPlaying && !seekArea.pressed
                NumberAnimation { duration: 1000; easing.type: Easing.Linear }
            }
        }
        MouseArea {
            id: seekArea
            width: parent.width
            height: 8
            enabled: card.source.canSeek
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            preventStealing: true
            function seek(mx) { card.source.player.position = card.source.player.length * Math.max(0, Math.min(1, mx / width)) }
            onPressed: (mouse) => seek(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) seek(mouse.x) }
        }
    }

    // Hover: a neutral lift over the whole card, cover included. Theme.hoverFill
    // under the cover tinted only the text side green and clashed with the
    // card's colour at the cover's fade. A handler, not the MouseArea's hover,
    // which goes off whenever the pointer is on the fader or a button.
    HoverHandler {
        id: cardHover
        enabled: card.source.isPlayer
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.07)
        opacity: cardHover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // The border on top, so the cover doesn't paint over it.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.color: Theme.surfaceBorder
        border.width: 1
    }
}
