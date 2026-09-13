import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Pill {
    id: root
    property var sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    tooltipText: sink && sink.audio
        ? (sink.audio.muted ? "Muted" : Math.round(sink.audio.volume * 100) + "%")
        : "No sink"

    onClicked: (mouse) => {
        if (!sink || !sink.audio) return
        // pavucontrol-dark (~/.local/share/themes) is scoped to just this
        // process: pavucontrol is plain GTK4 with no libadwaita, so it
        // doesn't pick up dark mode from either the adw-gtk3-dark GTK3 theme
        // (env.lua) or the color-scheme portal (which GTK4 only honors
        // through libadwaita) — it needs its own named theme instead.
        if (mouse.button === Qt.LeftButton) Quickshell.execDetached(["env", "GTK_THEME=pavucontrol-dark", "pavucontrol"])
        else if (mouse.button === Qt.RightButton) sink.audio.muted = !sink.audio.muted
    }
    // Touchpads deliver a smooth-scroll gesture as many small angleDelta
    // events rather than one ±120 "notch", and often end the gesture with a
    // tiny reverse-direction event from kinetic deceleration. Applying a
    // full step per event turned that trailing artifact into a visible
    // bounce right after hitting 0. Accumulating to a full notch (120)
    // before stepping absorbs both issues.
    property real wheelAccum: 0
    onWheel: (event) => {
        if (!sink || !sink.audio) return
        root.wheelAccum += event.angleDelta.y
        const step = 0.02
        while (Math.abs(root.wheelAccum) >= 120) {
            const dir = root.wheelAccum > 0 ? -1 : 1
            root.wheelAccum -= (root.wheelAccum > 0 ? 120 : -120)
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + dir * step))
        }
    }

    // Per-icon correction: these Nerd Font glyphs don't share a consistent
    // bounding box within their advance cell. Measured directly from the
    // font's glyf table (ink height in font units, 1000/em): mute/zero 508
    // (nf-md-volume_mute), low 431 (nf-fa-volume_down), medium 421
    // (nf-fa-volume), high 432 (nf-fa-volume_up) — scaled here so all four
    // render at the same effective visual height instead of Nerd Font's
    // inconsistent one.
    function iconScale() {
        const ic = root.icon()
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

    Row {
        spacing: 4

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 1.5 * Theme.barIconScale
            height: Theme.fontSize * 1.5 * Theme.barIconScale

            Text {
                // Left-aligned, not centered: see VolumeOSD.qml — these
                // icons vary in width, and centering would shift the
                // speaker-cone part of the glyph side to side as it changes.
                anchors {
                    left: parent.left
                    leftMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                text: root.icon()
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 1.5 * Theme.barIconScale * root.iconScale()
                color: root.sink && root.sink.audio && root.sink.audio.muted ? Theme.textDim : Theme.text
            }
        }
    }
}
