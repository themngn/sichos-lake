import QtQuick

// Bar + terminal transparency toggle. Unlike SunsetToggle/IdleToggle there's
// no popup — one click flips between the bar's normal dynamic transparency
// (transparent over an empty desktop, 80% once a window's behind it) and a
// fully opaque backdrop for both the bar and every open kitty window.
Pill {
    id: root
    property bool opaque: false
    signal toggle()

    tooltipText: root.opaque ? "Opaque (click for semi-transparent)" : "Semi-transparent (click for opaque)"
    opacity: root.opaque ? 1 : 0.5

    onClicked: root.toggle()

    Text {
        text: ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.opaque ? Theme.text : Theme.textMuted
    }
}
