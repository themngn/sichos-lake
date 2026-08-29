import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: root
    readonly property int percent: maxFile.text().length > 0 && brightnessFile.text().length > 0
        ? Math.round((Number(brightnessFile.text()) / Number(maxFile.text())) * 100)
        : 0

    visible: maxFile.text().length > 0

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/amdgpu_bl1/brightness"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        id: maxFile
        path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
        printErrors: false
    }

    tooltipText: "Backlight " + percent + "%"

    // See Volume.qml's wheelAccum for why: touchpads emit many small
    // angleDelta events per gesture (plus a trailing reverse-direction one
    // from kinetic deceleration), so stepping on every event turned that
    // artifact into a visible bounce right after hitting 0%.
    property real wheelAccum: 0
    onWheel: (event) => {
        root.wheelAccum += event.angleDelta.y
        while (Math.abs(root.wheelAccum) >= 120) {
            const goingUp = root.wheelAccum < 0
            root.wheelAccum -= (root.wheelAccum > 0 ? 120 : -120)
            Quickshell.execDetached(["brightnessctl", "set", goingUp ? "+2%" : "2%-"])
        }
    }

    function icon() {
        const icons = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
        const idx = Math.max(0, Math.min(icons.length - 1, Math.round(percent / 100 * (icons.length - 1))))
        return icons[idx]
    }

    Row {
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon()
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize * 1.5
            color: Theme.text
        }
    }
}
