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

    // Shared surface style for every popup, OSD, launcher and notification.
    // Each module reads these rather than its own literals, so the whole
    // shell's look can be retuned from here in one place. (Previously
    // there were two clashing styles: OSDs/launcher/notification center used
    // square black boxes with a 4px accent frame, while the bar popups used
    // rounded neutral-gray cards. Everything is now the card style.)
    // Tuned toward a macOS popover look, solid for now (no compositor blur):
    // a dark panel a step above the bar's pure black, faintly tinted toward
    // the sage palette, with generous corners and a hairline highlight edge.
    readonly property color surface: "#222726"
    // One step lighter than surface, for something floating on top of a
    // surface (e.g. an open dropdown list), so it doesn't blend in.
    readonly property color surfaceRaised: "#2d3332"
    readonly property color surfaceBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property int surfaceBorderWidth: 1
    readonly property int surfaceRadius: 12
    // Drop shadow under surfaces that have room for one (launcher,
    // notification center -- popups are sized exactly to their card).
    readonly property color surfaceShadow: Qt.rgba(0, 0, 0, 0.55)
    readonly property int surfaceShadowBlur: 36  // px (RectangularShadow.blur)
    readonly property int surfaceShadowOffset: 10  // px, straight down
    // Inset from a surface's edge to its content, and the gap between a
    // surface's top-level sections (header, controls, footer).
    readonly property int surfacePadding: 14
    readonly property int sectionSpacing: 12
    // Compact cards: notification toasts and notification-center entries
    // (tighter than a popup's surfacePadding/sectionSpacing -- several of
    // these stack, and header/body/time read as one unit, not sections).
    readonly property int cardPadding: 12
    readonly property int cardSpacing: 6
    readonly property int notificationIconSize: 20
    // Buttons, rows, chips and fields inside a surface.
    readonly property int controlRadius: 7
    // Height of buttons, segmented-mode buttons, tabs and dropdown fields.
    readonly property int controlHeight: 26
    readonly property color controlFill: Qt.rgba(1, 1, 1, 0.07)
    readonly property color hoverFill: Qt.rgba(accent.r, accent.g, accent.b, 0.22)
    readonly property color selectedFill: Qt.rgba(accent.r, accent.g, accent.b, 0.35)
    readonly property color separator: Qt.rgba(1, 1, 1, 0.08)
    // Unfilled part of progress/level bars, and the bar's own corners.
    readonly property color track: Qt.rgba(1, 1, 1, 0.14)
    // Rectangle clamps radius to half its shorter side, so a large value
    // here means "fully rounded pill ends" at any bar thickness.
    readonly property int trackRadius: 100
    readonly property int trackHeight: 8
    // Dims the desktop behind fullscreen overlays (launcher, notification center).
    readonly property color backdrop: Qt.rgba(0, 0, 0, 0.35)
    // Dark text drawn on a light fill (e.g. the calendar's "today" dot).
    readonly property color textOnLight: "#1c1c1c"
    // "Muted" state of the mic/notification mute toggles.
    readonly property color danger: "#ee3e3e"

    // font.family takes a single family name (this build has no font.families
    // fallback-list support); Qt's font engine still auto-falls-back to other
    // installed fonts (e.g. Noto Color Emoji) for glyphs missing from this one.
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    // Proportional text inside popups/OSDs/launcher/notifications (macOS
    // look; Inter as the usual SF Pro stand-in). Icon glyphs in those same
    // surfaces still use fontFamily -- Inter has no Nerd Font glyphs.
    readonly property string uiFontFamily: "Inter"
    readonly property int fontSize: 13

    readonly property int barHeight: 24

    // Requested 33% size bump across every bar-right icon (glyphs, Volume,
    // Tray, Language) -- one shared multiplier so they all grow together
    // and stay mutually consistent rather than drifting apart again.
    readonly property real barIconScale: 1.1

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

    // Multiplies the right-section Pills' horizontalPadding (Bar.qml) to
    // tune the gap between adjacent bar-right icons without touching each
    // Component's own padding value -- see Bar.qml's comment above those
    // Components for why the gap comes from padding rather than Row spacing.
    readonly property real barIconSpacingScale: 0.75
}
