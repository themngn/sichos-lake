import QtQuick

// Fixed-size icon glyph for the bar's right-section widgets. Every caller
// gets the same box width (Theme.barIconBoxWidth), centered, regardless of
// its own glyph's font-design proportions -- callers pass a `pixelSize`
// pre-scaled (via Theme.barIconInkHeight) to their own glyph's measured ink
// height, so every icon reads as the same visual size despite Nerd Font
// glyphs not sharing a consistent ink-to-em ratio.
//
// The fixed box (not just matching pixelSize) is what makes adjacent Pills'
// implicitWidth-driven MouseAreas tile edge-to-edge with an even gap instead
// of one that depends on each glyph's own advance/ink quirks -- this
// generalizes what BluetoothIndicator.qml and PowerProfile.qml used to do
// individually with a one-off `width: Theme.fontSize * 1.6`.
Item {
    id: root

    required property string glyph
    required property real pixelSize
    property color color: Theme.text
    property int boxWidth: Theme.barIconBoxWidth

    anchors.verticalCenter: parent.verticalCenter
    width: root.boxWidth
    height: Theme.fontSize * 1.5

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Theme.fontFamily
        font.pixelSize: root.pixelSize
        color: root.color
    }
}
