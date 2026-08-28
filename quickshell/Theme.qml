pragma Singleton
import QtQuick

QtObject {
    // Matches the original waybar style.css palette closely
    readonly property color text: "#ffffff"
    readonly property color textMuted: Qt.rgba(1, 1, 1, 0.65)
    readonly property color textDim: Qt.rgba(1, 1, 1, 0.5)

    readonly property color background: "#000000"
    readonly property color accent: "#c102fa"

    readonly property color submap: "#f1c40f"
    readonly property color success: "#26a65b"
    readonly property color critical: "#f53c3c"
    readonly property color urgent: "#eb4d4b"

    readonly property color perfPerformance: "#f53c3c"
    readonly property color perfBalanced: "#2980b9"
    readonly property color perfPowerSaver: "#2ecc71"

    // font.family takes a single family name (this build has no font.families
    // fallback-list support); Qt's font engine still auto-falls-back to other
    // installed fonts (e.g. Noto Color Emoji) for glyphs missing from this one.
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property int fontSize: 13

    readonly property int barHeight: 30
}
