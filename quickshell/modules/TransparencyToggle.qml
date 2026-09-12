import QtQuick

// Bar + terminal transparency toggle. Unlike SunsetToggle/IdleToggle there's
// no popup — one click flips between the bar's normal dynamic transparency
// (transparent over an empty desktop, 80% once a window's behind it) and a
// fully opaque backdrop for both the bar and every open kitty window.
Pill {
    id: root
    property bool opaque: false
    // Whether the bar has revealed the toggle row (hover/popup-open) --
    // set externally by Bar.qml. Only matters while inactive: an active
    // toggle always stays shown regardless, so its on/off state is never
    // hidden from a glance at the bar.
    property bool revealed: true
    signal toggle()

    tooltipText: root.opaque ? "Opaque (click for semi-transparent)" : "Semi-transparent (click for opaque)"
    readonly property bool shown: root.opaque || root.revealed
    opacity: root.shown ? (root.opaque ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    // Collapses the pill's own width to 0 when hidden (rather than just
    // fading it out) so Bar.qml's toggleRow -- sized by its children's real
    // widths -- closes the gap and the remaining visible pills slide flush
    // together instead of leaving dead space where this one used to sit.
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    onClicked: root.toggle()

    Text {
        text: ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.opaque ? Theme.text : Theme.textMuted
    }
}
