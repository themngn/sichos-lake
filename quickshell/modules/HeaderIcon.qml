import QtQuick

// Accent glyph in the top-left corner of a popup/menu header. Sized and
// centered by the glyph's ink, not its pixelSize: Nerd Font Mono icons don't
// share an ink-to-em ratio (see Theme.barIconInkHeight) and sit on the text
// baseline, so a plain Text at a matching pixelSize read smaller than the
// bold title beside it and visibly low. Here every icon's ink is fitted into
// a Theme.headerIconSize box and centered in this Item, which the header Row
// centers against the title's line box -- for bold Inter that middle is the
// cap-height middle (within 0.25px), so icon and title read as one line.
Item {
    id: root

    required property string glyph
    property color color: Theme.accent
    property real inkHeight: Theme.headerIconSize
    // Nerd Font Mono stretches nearly every icon to the full cell width, so
    // wide-and-short glyphs (cloud, gamepad) would balloon sideways if only
    // height were matched; cap the width a little above the height.
    property real inkWidth: Theme.headerIconSize * 1.1

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    // Real ink bounds at pixelSize 100, [x, top, width, height] relative to
    // the pen origin on the baseline, measured from rendered pixels (grab +
    // trim) of JetBrainsMono Nerd Font Mono. TextMetrics.tightBoundingRect
    // can't be used for this: its top is right but its bottom is clamped to
    // the baseline, so glyphs whose ink ends above the baseline (cloud ends
    // 16px up, gamepad 15px) were measured too tall -- they came out too
    // small and rode high. A glyph not listed falls back to it.
    readonly property var _measured: ({
        0xf0f3: [0, -70, 60, 69],   // bell (NotificationCenter)
        0xf116b: [0, -71, 61, 70],  // bell with dot
        0xf293: [0, -77, 60, 82],   // bluetooth
        0xf0176: [-1, -64, 62, 56], // coffee (Idle)
        0xf02b4: [0, -57, 60, 42],  // gamepad (GameFocus)
        0xf036c: [0, -77, 60, 82],  // microphone
        0xf036d: [0, -68, 60, 64],  // microphone off
        0xf0379: [-1, -64, 62, 56], // monitor (HDR, WorkspaceMenu)
        0xf0590: [0, -55, 60, 39],  // cloud (Weather)
        0xf0594: [0, -69, 59, 66],  // moon (Sunset)
        0xf06a9: [-1, -63, 62, 55], // robot (Claude)
        0xf16a3: [-1, -63, 62, 55], // robot (AGY)
        0xf06b0: [0, -66, 61, 60],  // update (SystemUpdate)
        0xf0e17: [-1, -70, 62, 68], // calendar
        0xf0e51: [-1, -64, 62, 56], // monitor (DisplaySettings)
        0xf042: [0, -66, 60, 60],   // adjust (Transparency)
        0xf009a: [0, -71, 61, 70],  // bell (NotificationMute)
        0xf009b: [0, -66, 60, 61],  // bell-off (NotificationMute)
        // custom/alert-widget (header + history badges)
        0xf0565: [-1, -73, 62, 74], // shield-check
        0xf0026: [0, -62, 60, 52],  // alert
        0xf0434: [0, -66, 60, 60],  // quadcopter
        0xf14de: [0, -66, 60, 60],  // rocket-launch
        0xf0691: [0, -66, 60, 60]   // bomb
    })
    readonly property real _ref: 100
    readonly property var _ink: {
        const m = root._measured[root.glyph.codePointAt(0)]
        if (m) return { x: m[0], y: m[1], width: m[2], height: m[3] }
        const r = metrics.tightBoundingRect
        return { x: r.x, y: r.y, width: r.width, height: r.height }
    }
    // pixelSize is an int, so position with the scale actually rendered.
    readonly property int _pixelSize: (_ink.height > 0 && _ink.width > 0)
        ? Math.round(_ref * Math.min(root.inkHeight / _ink.height, root.inkWidth / _ink.width)) : Theme.fontSize
    readonly property real _scale: _pixelSize / _ref

    implicitWidth: Math.ceil(_ink.width * _scale)
    implicitHeight: root.inkHeight

    TextMetrics {
        id: metrics
        font.family: Theme.fontFamily
        font.pixelSize: root._ref
        text: root.glyph
    }

    Text {
        text: root.glyph
        color: root.color
        font.family: Theme.fontFamily
        font.pixelSize: root._pixelSize
        // Ink bounds are relative to the pen origin on the baseline (y
        // negative above it); shift so the ink box is centered in root.
        x: (root.width - root._ink.width * root._scale) / 2 - root._ink.x * root._scale
        y: (root.height - root._ink.height * root._scale) / 2 - (baselineOffset + root._ink.y * root._scale)
    }
}
