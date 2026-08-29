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

    function icon() {
        if (!sink || !sink.audio) return ""
        if (sink.audio.muted) return ""
        const v = sink.audio.volume
        if (v < 0.01) return ""
        if (v < 0.5) return ""
        return ""
    }

    Row {
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) : 0) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: root.sink && root.sink.audio && root.sink.audio.muted ? Theme.textDim : Theme.text
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon()
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize * 1.5
            color: root.sink && root.sink.audio && root.sink.audio.muted ? Theme.textDim : Theme.text
        }
    }
}
