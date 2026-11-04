import QtQuick

// A round transport button: plain, with a hover fill and a pressed scale.
Item {
    id: mb
    property string glyph: ""
    property bool big: false
    // A white disc with a dark glyph (the large card's play/pause).
    property bool filled: false
    property bool enabledState: true
    signal clicked()

    property int size: mb.filled ? 28 : 34
    width: mb.size
    height: mb.size
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: mb.filled ? (mbArea.containsMouse ? "white" : Theme.text)
            : mbArea.containsMouse && mb.enabledState ? Theme.hoverFill : "transparent"
        scale: mbArea.pressed ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    Text {
        id: mbGlyph
        // Centered by hand on whole pixels: anchors.centerIn put the
        // small play glyph a pixel left in its disc. Inside the disc the
        // play triangle also gets nudged right -- its ink box is centered
        // in the glyph, but against a circle its visual middle (a third of
        // the way in from the flat side) reads as off to the left. A plain
        // one stays box-centered: nudged, it sat ~3px out of step with
        // prev/next beside it.
        readonly property real nudge: mb.filled && mb.glyph === "\u{f040a}" ? font.pixelSize * 0.2 : 0
        x: Math.round((parent.width - width) / 2 + nudge)
        y: Math.round((parent.height - height) / 2)
        text: mb.glyph
        color: mb.filled ? Theme.textOnLight : mb.enabledState ? Theme.text : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: mb.filled ? Theme.fontSize - 1 : mb.big ? Theme.fontSize + 11 : mb.size < 34 ? Theme.fontSize + 3 : Theme.fontSize + 5
        scale: mbArea.pressed ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        transform: Scale { id: swapScale; origin.x: mbGlyph.width / 2; origin.y: mbGlyph.height / 2 }
    }
    // Play <-> pause: the new glyph fades and grows in instead of
    // swapping in one frame. A separate Scale transform, so it doesn't
    // fight the pressed scale above.
    property string _shown: ""
    onGlyphChanged: {
        if (mb._shown !== "" && mb._shown !== mb.glyph) swapAnim.restart()
        mb._shown = mb.glyph
    }
    ParallelAnimation {
        id: swapAnim
        NumberAnimation { target: mbGlyph; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: swapScale; properties: "xScale,yScale"; from: 0.5; to: 1; duration: 220; easing.type: Easing.OutBack }
    }
    MouseArea {
        id: mbArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: mb.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: mb.clicked()
    }
}
