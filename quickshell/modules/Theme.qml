pragma Singleton
import QtQuick

QtObject {
    // Theme palette derived from colors.toml (sage/spruce theme)
    readonly property color text: "#f0f9e3"
    // Brightened from #b4bbaa / #676f71: on the translucent glass cards
    // (glassAlpha) the old values washed out over light backgrounds.
    readonly property color textMuted: "#cbd2c1"
    readonly property color textDim: "#8f9796"

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
    // Glass: the same two surface colors at glassAlpha, with Hyprland
    // blurring whatever is behind them (layer rules in hypr/window_rules.lua
    // -- only quickshell's menu-type surfaces are blurred, never the bar or
    // application windows). Cards pick per screen via surfaceFor()/
    // surfaceRaisedFor(): on a monitor with HDR active they stay solid,
    // since translucent surfaces band there (TODO.md, same reason Bar.qml
    // forces itself opaque under HDR). glassAlpha must stay above the
    // layer rules' ignore_alpha, or Hyprland stops blurring behind cards.
    // Legibility over light pages comes from hypr's blur brightness (0.45,
    // darkens the blurred backdrop) and the brighter textMuted/textDim
    // above, not from a more opaque card -- 0.72 was tried and lost the
    // glass look.
    readonly property real glassAlpha: 0.55
    function glassOn(screen) {
        return !(screen && HdrSettings.active && HdrSettings.isSelected(screen.name))
    }
    function surfaceFor(screen) {
        return glassOn(screen) ? Qt.rgba(surface.r, surface.g, surface.b, glassAlpha) : surface
    }
    function surfaceRaisedFor(screen) {
        return glassOn(screen) ? Qt.rgba(surfaceRaised.r, surfaceRaised.g, surfaceRaised.b, glassAlpha) : surfaceRaised
    }
    readonly property color surfaceBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property int surfaceBorderWidth: 1
    readonly property int surfaceRadius: 12
    // Drop shadow under surfaces that have room for one (launcher,
    // notification center -- popups are sized exactly to their card).
    // Only drawn while the card is solid (HDR screens) -- see Launcher.qml.
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
    // macOS-menu-bar-style hover highlight behind a clickable bar item: a
    // soft neutral rounded fill, no border.
    readonly property color barItemHover: Qt.rgba(1, 1, 1, 0.12)
    readonly property int barItemRadius: 6
    readonly property color separator: Qt.rgba(1, 1, 1, 0.08)
    // Unfilled part of progress/level bars, and the bar's own corners.
    readonly property color track: Qt.rgba(1, 1, 1, 0.14)
    // Rectangle clamps radius to half its shorter side, so a large value
    // here means "fully rounded pill ends" at any bar thickness.
    readonly property int trackRadius: 100
    readonly property int trackHeight: 8
    // Open animation for popups/menus (SurfaceAppear.qml): fade + scale-up.
    readonly property int openDuration: 160
    readonly property real openScaleFrom: 0.94
    // MorphPopup: how long the bar's shared popup card takes to slide and
    // reshape from one popup into the next.
    readonly property int morphDuration: 220
    // Content width shared by every toggle-row popup, so the morphing card
    // keeps one width and only slides/changes height between them. 260 is
    // what IdlePopup's timer rows need; the others used 220/240 before.
    readonly property int togglePopupWidth: 260
    // The big glyph on every OSD (OsdIcon.qml): the box it sits in, and the
    // size of the square its ink is scaled to fit, whatever the glyph's own
    // proportions.
    readonly property int osdIconBox: fontSize * 3
    readonly property int osdIconSize: 30
    // Every OSD's width, whatever it shows.
    readonly property int osdWidth: 260
    // Squircle.qml corners (continuous, iOS-style): every surface card --
    // OSDs, popups, menus, launcher, pickers, notifications. Controls
    // inside them still use plain controlRadius Rectangles.
    // Smoothing 0.6 is Apple's (0 = plain arcs). At the same radius a
    // squircle corner reads tighter than a circular one -- the curve starts
    // further out but bends later -- so it takes a slightly larger radius to
    // look as round as surfaceRadius.
    readonly property real cornerSmoothing: 0.5
    readonly property int surfaceSquircleRadius: 14
    // OSDs are short (64px) single-row cards; the surface radius made them
    // read as pills.
    readonly property int osdSquircleRadius: 10
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
    // Visible (ink) height of the accent glyph in the top-left corner of
    // every popup/menu header -- HeaderIcon.qml scales each glyph to this,
    // so it's an ink height, not a font pixelSize. A bit taller than the
    // bold title's cap height so the icon leads the line.
    readonly property int headerIconSize: fontSize + 3

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
