import QtQuick
import Quickshell.Widgets

// The lead source, when it has a cover: a big banner with the title over the
// art, the playbar under it, then the time and a fader at the same x and width
// as the cards' below. Wide art fills it; a 1:1 cover gets a large sleeve and
// record.
ClippingRectangle {
    id: banner
    required property var source
    readonly property int artHeight: 166
    // The cards' cover column, so the fader lines up down the whole list.
    readonly property int coverWidth: 124
    height: 203
    radius: Theme.controlRadius
    color: Theme.controlFill

    Rectangle {
        anchors.fill: parent
        visible: banner.source.hasTint
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: banner.source.tint }
            // Beside a sleeve, its fade below ends in exactly this colour, so
            // the tint's right edge doesn't show as a cut.
            GradientStop { position: banner.source.square && banner.width > 0 ? banner.artHeight / banner.width : 0; color: banner.source.tint }
            GradientStop { position: 1; color: banner.source.tintDeep }
        }
    }

    Item {
        id: art
        width: parent.width
        height: banner.artHeight

        Image {
            anchors.fill: parent
            visible: banner.source.hasArt && !banner.source.square
            source: visible ? banner.source.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            sourceSize.height: 332
        }
        MediaRecord {
            visible: banner.source.square
            // While playing, centered in the space right of the sleeve (as
            // wide as the art is tall); fully behind it on pause.
            x: Math.round((parent.width + parent.height - width) / 2)
            y: 8
            width: 150
            height: 150
            labelSize: 54
            tuck: parent.height - x - width
            art: visible ? banner.source.art : ""
            playing: banner.source.isPlaying
        }
        Image {
            visible: banner.source.square
            width: parent.height
            height: parent.height
            source: visible ? banner.source.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            sourceSize.height: 332
        }
        // The tint behind the text, only as tall as the text plus a short fade
        // and only as wide as it needs: on a 1:1 cover the text stays on the
        // sleeve, so the record beside it keeps its full colour.
        Rectangle {
            id: scrim
            readonly property int fadeHeight: 26
            readonly property color edge: banner.source.square ? banner.source.tint : banner.source.tintDeep
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: banner.source.square ? parent.height : parent.width
            height: textBlock.height + textBlock.anchors.bottomMargin + fadeHeight
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(banner.source.tint.r, banner.source.tint.g, banner.source.tint.b, 0) }
                GradientStop { position: scrim.height > 0 ? scrim.fadeHeight / scrim.height : 0; color: Qt.rgba(banner.source.tint.r, banner.source.tint.g, banner.source.tint.b, 0.85) }
                GradientStop { position: 1; color: Qt.rgba(scrim.edge.r, scrim.edge.g, scrim.edge.b, banner.source.square ? 1 : 0.92) }
            }
        }
        Column {
            id: textBlock
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.bottomMargin: 6
            width: (banner.source.square ? parent.height : parent.width) - 20
            Text {
                width: parent.width
                // Two lines on a sleeve, which is too narrow for one to say much.
                wrapMode: banner.source.square ? Text.Wrap : Text.NoWrap
                maximumLineCount: banner.source.square ? 2 : 1
                text: banner.source.title
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
                text: banner.source.subtitle
                elide: Text.ElideRight
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
        MediaCoverControls {
            anchors.fill: parent
            source: banner.source
        }
    }

    // The playbar.
    Rectangle {
        y: banner.artHeight
        width: parent.width
        height: 3
        color: Qt.rgba(1, 1, 1, banner.source.hasLength ? 0.14 : 0.06)
        Rectangle {
            height: parent.height
            color: Theme.text
            width: parent.width * banner.source.progress
            // Glides between the once-a-second position reads while playing.
            Behavior on width {
                enabled: banner.source.isPlaying && !bannerSeek.pressed
                NumberAnimation { duration: 1000; easing.type: Easing.Linear }
            }
        }
        MouseArea {
            id: bannerSeek
            width: parent.width
            y: -5
            height: 13
            enabled: banner.source.canSeek
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            preventStealing: true
            function seek(mx) { banner.source.player.position = banner.source.player.length * Math.max(0, Math.min(1, mx / width)) }
            onPressed: (mouse) => seek(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) seek(mouse.x) }
        }
    }

    Item {
        y: banner.artHeight + 3
        width: parent.width
        height: parent.height - y
        Text {
            x: 10
            width: banner.coverWidth - 10
            anchors.verticalCenter: parent.verticalCenter
            visible: banner.source.hasLength
            text: banner.visible && banner.source.hasLength
                ? banner.fmt(banner.source.player.position) + " / " + banner.fmt(banner.source.player.length) : ""
            elide: Text.ElideRight
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
            font.features: { "tnum": 1 }
        }
        SliderRow {
            x: banner.coverWidth + 10
            width: parent.width - x - 9
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            hasMore: false
            maxValue: 1.5
            enabled: !!banner.source.app
            opacity: enabled ? 1 : 0.5
            glyph: banner.source.muted ? "\u{f0581}" : "\u{f057e}" // nf-md-volume_off / volume_high
            dim: banner.source.muted
            value: banner.source.volume
            onGlyphClicked: banner.source.toggleMute()
            onMoved: (v) => banner.source.setVolume(v)
        }
    }

    function fmt(secs) {
        const t = Math.max(0, Math.floor(secs))
        const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60
        const ss = (sec < 10 ? "0" : "") + sec
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
    }

    // The border on top, so the cover doesn't paint over it.
    Rectangle {
        anchors.fill: parent
        radius: banner.radius
        color: "transparent"
        border.color: Theme.surfaceBorder
        border.width: 1
    }
}
