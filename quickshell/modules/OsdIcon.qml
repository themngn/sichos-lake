import QtQuick

// The big glyph on every OSD (VolumeOSD, BacklightOSD, KbdBacklightOSD,
// DisplayModeOSD, MicOSD), in one fixed box so it sits at the same spot and
// reads at the same size on all of them.
//
// Sized and placed from measured ink, not font metrics. Rendered by Qt and
// measured off a screenshot (FontMetrics.tightBoundingRect gave wrong boxes
// for some of these -- per-glyph font fallback): in "JetBrainsMono Nerd Font
// Mono" every icon's ink is centered at (0.30, 0.66) * pixelSize from the Text
// item's origin -- the Mono variant centers each icon in its 0.6em cell --
// and most icons' larger ink side is that full 0.6em width. So the only
// per-glyph input is `extent`: the larger ink side at pixelSize 100 (60 for
// the usual cell-wide icons; the tall mic glyphs pass their own).
Item {
    id: icon

    property string glyph: ""
    property color color: Theme.text
    // Larger ink dimension at pixelSize 100 -- see above.
    property real extent: 60
    // For a glyph set that grows to the right as its state changes (the
    // volume icons add sound waves): pin the ink's left edge instead of
    // centering, so the shared part doesn't slide sideways between states.
    // inkLeft is the glyph's ink left edge at pixelSize 100 (0 = flush with
    // the cell, i.e. the widest state).
    property bool alignLeft: false
    property real inkLeft: 0

    implicitWidth: Theme.osdIconBox
    implicitHeight: Theme.osdIconBox

    readonly property real pixelSize: Theme.osdIconSize * 100 / icon.extent

    Text {
        text: icon.glyph
        color: icon.color
        font.family: Theme.fontFamily
        font.pixelSize: icon.pixelSize
        x: icon.alignLeft
            ? (icon.width - 0.60 * icon.pixelSize) / 2 - icon.inkLeft * icon.pixelSize / 100
            : icon.width / 2 - 0.30 * icon.pixelSize
        y: icon.height / 2 - 0.66 * icon.pixelSize
    }
}
