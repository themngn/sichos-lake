pragma Singleton
import QtQuick

QtObject {
    // Theme palette derived from colors.toml (sage/spruce theme)
    readonly property color text: "#f0f9e3"
    readonly property color textMuted: "#b4bbaa"
    readonly property color textDim: "#676f71"

    readonly property color background: "#000000"
    readonly property color cardBackground: "#141c1e"
    readonly property color accent: "#698b85"
    readonly property color accentHover: "#77a29b"

    readonly property color submap: "#e1ffdf"
    readonly property color success: "#b2cfb8"
    readonly property color critical: "#a9b495"
    readonly property color urgent: "#a5ac97"

    readonly property color perfPerformance: "#a9b495"
    readonly property color perfBalanced: "#698b85"
    readonly property color perfPowerSaver: "#b2cfb8"

    // font.family takes a single family name (this build has no font.families
    // fallback-list support); Qt's font engine still auto-falls-back to other
    // installed fonts (e.g. Noto Color Emoji) for glyphs missing from this one.
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property int fontSize: 13

    readonly property int barHeight: 30

    // Requested 33% size bump across every bar-right icon (glyphs, Volume,
    // Tray, Language) -- one shared multiplier so they all grow together
    // and stay mutually consistent rather than drifting apart again.
    readonly property real barIconScale: 1.00

    // Shared visual-height target (px) that every right-section bar icon
    // (BarIcon.qml) scales its own glyph's measured ink to, regardless of
    // that glyph's own font-design proportions -- Nerd Font icons don't
    // share a consistent ink-to-em ratio (confirmed via fontTools glyf
    // bbox: e.g. battery glyphs sit at 334 units/1000em, bluetooth at 802),
    // so matching pixelSize alone left icons looking visibly different
    // sizes. Base value (before barIconScale) == Volume.qml's own
    // pre-existing mute-icon ink height (508 units/1000em @ pixelSize
    // fontSize*1.5) -- kept rather than picking a new number so
    // Volume.qml's already-correct icons don't need to move independently.
    readonly property real barIconInkHeight: fontSize * 1.5 * 0.508 * barIconScale
    // Fixed box width every BarIcon renders into. Must clear the widest
    // glyph's resulting ink width once scaled to barIconInkHeight -- battery
    // glyphs are the extreme case (334-unit-tall ink but 601-unit-wide, so
    // scaling height up to match taller glyphs blows their width out to
    // ~17.8px pre-scale, ~23.7px at barIconScale). Identical width on every
    // icon (not just matching pixelSize) is what makes adjacent Pills'
    // implicitWidth-driven hitboxes tile with an even gap instead of a
    // size-dependent one.
    readonly property int barIconBoxWidth: Math.round(22 * barIconScale)
}
