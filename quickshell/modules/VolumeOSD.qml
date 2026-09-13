import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Windows-11-style transient volume overlay: pops up on any volume/mute
// change (media keys, Volume.qml's scroll wheel, pavucontrol, anything —
// all of them go through Pipewire, so watching the sink's own signals here
// catches every source uniformly) and fades out again after a couple
// seconds of no further change.
PanelWindow {
    id: osd

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

    implicitWidth: 260
    implicitHeight: 64

    Connections {
        target: osd.sink ? osd.sink.audio : null
        function onVolumeChanged() { osd.pop() }
        function onMutedChanged() { osd.pop() }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osd.visible = false
    }

    function pop() {
        osd.visible = true
        hideTimer.restart()
    }

    // Per-icon correction: these Nerd Font glyphs don't share a consistent
    // bounding box within their advance cell. Measured directly from the
    // font's glyf table (ink height in font units, 1000/em): mute/zero 508
    // (nf-md-volume_mute), low 431 (nf-fa-volume_down), medium 421
    // (nf-fa-volume), high 432 (nf-fa-volume_up) — scaled here so all four
    // render at the same effective visual height instead of Nerd Font's
    // inconsistent one.
    function iconScale() {
        const ic = osd.icon()
        if (ic === "") return 1.179
        if (ic === "") return 1.207
        if (ic === "") return 1.176
        return 1.0
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

    Rectangle {
        anchors.fill: parent
        radius: 0
        color: Theme.background
        border.color: Theme.accent
        border.width: 4

        Row {
            anchors.centerIn: parent
            spacing: 14

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 3
                height: Theme.fontSize * 3

                Text {
                    // Left-aligned, not centered: these icons vary in width
                    // (more sound waves = wider), and centering would shift
                    // the speaker-cone part of the glyph side to side as it
                    // changes. Left-aligning pins the cone to one spot.
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: osd.icon()
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 3 * osd.iconScale()
                    color: osd.sink && osd.sink.audio && osd.sink.audio.muted ? Theme.textDim : Theme.text
                }
            }

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: 130
                height: 8
                radius: 0
                color: Qt.rgba(1, 1, 1, 0.15)

                Rectangle {
                    width: track.width * (osd.sink && osd.sink.audio ? osd.sink.audio.volume : 0)
                    height: track.height
                    radius: 0
                    color: osd.sink && osd.sink.audio && osd.sink.audio.muted ? Theme.textDim : Theme.accent
                }
            }

            Text {
                // Fixed width (wide enough for "100%") so the digit count
                // changing (0% vs 50% vs 100%) doesn't shift/reflow the
                // rest of the row.
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2.5
                text: (osd.sink && osd.sink.audio ? Math.round(osd.sink.audio.volume * 100) : 0) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.text
            }
        }
    }
}
