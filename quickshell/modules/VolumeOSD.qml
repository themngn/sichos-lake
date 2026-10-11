import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Windows-11-style transient volume overlay: pops up on any volume/mute
// change (media keys, Volume.qml's scroll wheel, pavucontrol, anything —
// all of them go through Pipewire, so watching the sink's own signals here
// catches every source uniformly) and fades out again after a couple
// seconds of no further change.
PanelWindow {
    id: osd
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

    property var sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: osd.sink ? [osd.sink] : []
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

    Connections {
        target: osd.sink ? osd.sink.audio : null
        function onVolumeChanged() { osd.pop() }
        function onMutedChanged() { osd.pop() }
    }

    // Only the most recent OSD shows: another one popping hides this one.
    Connections {
        target: ShellState
        function onActiveOsdChanged() {
            if (ShellState.activeOsd !== "volume") {
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

    function pop() {
        // The Control Center's own slider already shows the level while it's open.
        if (ShellState.activePopup === "quicksettings" || ShellState.activePopup === "qs-audio") return
        osd.visible = true
        hideTimer.restart()
        ShellState.activeOsd = "volume"
    }


    function icon() {
        if (!sink || !sink.audio) return ""
        if (sink.audio.muted) return "󰝟"
        const v = sink.audio.volume
        if (v < 0.01) return "󰝟"
        if (v < 0.34) return ""
        if (v < 0.67) return ""
        return ""
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.osdSquircleRadius
        color: Theme.surfaceFor(osd.screen)
        borderColor: Theme.surfaceBorder
        borderWidth: Theme.surfaceBorderWidth

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
                glyph: osd.icon()
                color: osd.sink && osd.sink.audio && osd.sink.audio.muted ? Theme.textDim : Theme.text
                // The volume glyphs grow to the right (more sound waves), so
                // pin their left edge rather than centering them. Ink left
                // edge per glyph at pixelSize 100, measured; the widest
                // glyphs fill the cell (0).
                alignLeft: true
                inkLeft: ({ "\uefcf": 6, "\uf027": 9 })[glyph] || 0
            }

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: content.width - osdIcon.width - percentText.width - 2 * content.spacing
                height: Theme.trackHeight
                radius: Theme.trackRadius
                color: Theme.track

                Rectangle {
                    width: track.width * (osd.sink && osd.sink.audio ? osd.sink.audio.volume : 0)
                    height: track.height
                    radius: Theme.trackRadius
                    color: osd.sink && osd.sink.audio && osd.sink.audio.muted ? Theme.textDim : Theme.accent
                }
            }

            Text {
                // Fixed width (wide enough for "100%") so the digit count
                // changing (0% vs 50% vs 100%) doesn't shift/reflow the
                // rest of the row.
                id: percentText
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2.5
                // Right-aligned so a short value ("7%") doesn't leave a gap at the card's edge.
                horizontalAlignment: Text.AlignRight
                text: (osd.sink && osd.sink.audio ? Math.round(osd.sink.audio.volume * 100) : 0) + "%"
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.text
            }
        }
    }
}
