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
        0xf1542: [-1, -63, 61, 54], // tune-variant (QuickSettings)
        0xf0d7d: [-1, -47, 61, 22], // hdr (QuickSettings)
        0xf011c: [0, -83, 60, 94],  // cellphone (QuickSettings, PhonePage)
        // Control Center tiles
        0xf001d: [0, -66, 60, 60],  // airplane
        0xf0003: [0, -58, 60, 44],  // access point (Hotspot)
        0xf1511: [0, -66, 60, 60],  // access point off
        0xf1e6: [0, -76, 60, 80],   // plug (power profile: performance)
        0xf032a: [0, -64, 60, 57],  // leaf (power profile: saver)
        0xf24e: [0, -60, 60, 49],   // balance scale (power profile: balanced)
        0xf075f: [-1, -61, 61, 51], // volume mute
        0xf027: [8, -57, 43, 42],   // volume low
        0xefcf: [5, -57, 49, 42],   // volume medium
        0xf028: [-1, -58, 61, 44],  // volume high
        0xf05a9: [0, -61, 60, 50],  // wifi
        0xf05aa: [0, -61, 60, 50],  // wifi off
        0xf0200: [-1, -65, 61, 58], // ethernet
        0xf00af: [1, -83, 59, 94],  // bluetooth (md)
        0xf00b2: [0, -74, 60, 76],  // bluetooth off
        0xf035b: [-1, -67, 62, 62], // memory (system stats)
        0xf062c: [0, -74, 60, 76],  // source-branch (SichOS version)
        0xf0322: [-1, -57, 62, 42], // laptop (lid close)
        0xf042: [0, -66, 60, 60],   // adjust (Transparency)
        0xf009a: [0, -71, 61, 70],  // bell (NotificationMute)
        0xf009b: [0, -66, 60, 61],  // bell-off (NotificationMute)
        // custom/alert-widget (header + history badges)
        0xf0565: [-1, -73, 62, 74], // shield-check
        0xf0026: [0, -62, 60, 52],  // alert
        0xf0434: [0, -66, 60, 60],  // quadcopter
        0xf14de: [0, -66, 60, 60],  // rocket-launch
        0xf0691: [0, -66, 60, 60],  // bomb
        // EmojiPicker category tabs
        0xf0150: [0, -66, 60, 60],  // clock-outline (Recent)
        0xf01f5: [0, -66, 60, 60],  // emoticon-outline
        0xf03e9: [0, -63, 60, 54],  // paw
        0xf025a: [0, -66, 60, 60],  // food
        0xf010b: [0, -63, 60, 54],  // car
        0xf0806: [0, -66, 60, 60],  // basketball
        0xf0336: [0, -79, 60, 86],  // lightbulb-outline
        0xf02d5: [0, -64, 60, 55],  // heart-outline
        0xf023b: [0, -70, 60, 68],  // flag
        // PowerMenu (header + tiles)
        0xf0425: [0, -68, 60, 64],  // power
        0xf033e: [0, -75, 60, 79],  // lock
        // Phone mirror (connecting spinner, unlock cover)
        0xf0453: [0, -62, 59, 52],  // refresh
        0xf033f: [0, -75, 60, 79],  // lock-open
        0xf04b2: [0, -58, 60, 44],  // sleep (zzz)
        0xf0343: [0, -69, 59, 66],  // logout
        0xf0709: [0, -71, 60, 72]   // restart
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
