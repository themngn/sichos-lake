import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Same transient overlay as DisplayModeOSD.qml (icon + label, no level bar),
// for the microphone's mute state. Like VolumeOSD.qml it watches the PipeWire
// node itself rather than being poked from each place that can mute, so the
// bar pill, MicPopup.qml, the XF86AudioMicMute key and `wpctl` all trigger it
// alike. Mute changes only -- input volume isn't something you need a
// confirmation flash for the way you do for "am I live or not".
PanelWindow {
    id: osd
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

    property var source: Pipewire.defaultAudioSource
    readonly property bool muted: osd.source && osd.source.audio ? osd.source.audio.muted : false

    PwObjectTracker {
        objects: osd.source ? [osd.source] : []
    }

    Connections {
        target: osd.source ? osd.source.audio : null
        function onMutedChanged() {
            osd.visible = true
            hideTimer.restart()
            ShellState.activeOsd = "mic"
        }
    }

    screen: Quickshell.screens[0]
    color: "transparent"
    visible: false
    exclusiveZone: 0

    anchors {
        bottom: true
    }
    margins.bottom: 90

    // Same width on every OSD; the content stretches to fill it (see the Row
    // below). Same visible padding on both sides: the icon's box is wider than
    // its ink, so the left margin is reduced by that slack.
    readonly property real leftPadding: Theme.surfacePadding - (Theme.osdIconBox - Theme.osdIconSize) / 2
    implicitWidth: Theme.osdWidth
    implicitHeight: 64

    // Only the most recent OSD shows: another one popping hides this one.
    Connections {
        target: ShellState
        function onActiveOsdChanged() {
            if (ShellState.activeOsd !== "mic") {
                hideTimer.stop()
                osd.visible = false
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osd.visible = false
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.surfaceRadius
        color: Theme.surfaceFor(osd.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth

        // Left-anchored, not centered: centering the whole row put the
        // icon at a different x on every OSD (it depends on what follows it).
        // Spans the card; the slider (or the label) takes whatever width the
        // icon doesn't, so nothing leaves dead space at the right edge.
        Row {
            id: content
            anchors.left: parent.left
            anchors.leftMargin: osd.leftPadding
            anchors.right: parent.right
            anchors.rightMargin: Theme.surfacePadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            OsdIcon {
                id: osdIcon
                anchors.verticalCenter: parent.verticalCenter
                glyph: osd.muted ? "󰍭" : "󰍬"
                color: osd.muted ? Theme.danger : Theme.text
                // Both mic glyphs are taller than they're wide, and not the
                // same height: ink 82 (mic) vs 64 (mic-off, the slash crops
                // it) tall at pixelSize 100, measured. Each uses its own, so
                // both render the same visual size.
                extent: osd.muted ? 64 : 82
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Centered in the space right of the icon, not left-aligned with
                // the rest of the card empty.
                width: content.width - osdIcon.width - content.spacing
                horizontalAlignment: Text.AlignHCenter
                text: osd.muted ? "Microphone muted" : "Microphone on"
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.text
            }
        }
    }
}
