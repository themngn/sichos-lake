import QtQuick
import Quickshell

// Phone mirror bar widget: opens the scrcpy window, then shows/hides it
// (expand/collapse) -- closing is the controls card's close button only.
// See PhoneMirrorState.qml and PhoneMirrorPanel.qml.
Pill {
    id: root
    property string screenName: ""

    tooltipText: PhoneMirrorState.loading ? "Connecting…"
        : PhoneMirrorState.collapsed ? "Show phone mirror"
        : PhoneMirrorState.open ? "Hide phone mirror" : "Mirror phone"

    onClicked: PhoneMirrorState.toggle(root.screenName)

    BarIcon {
        glyph: "󰄜"
        // nf-md-cellphone inks ~928/1000em (measured with magick at 1000px,
        // same method that gives Backlight.qml's 600).
        pixelSize: Theme.barIconInkHeight * 1000 / 928
        color: PhoneMirrorState.open || PhoneMirrorState.loading ? Theme.text : Theme.textMuted
    }
}
