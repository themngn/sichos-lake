import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Shade under the transparent bar, only where the wallpaper behind it is
// too bright for its light text -- see "Bar scrim" in scripts/wallpaper.py,
// which renders the mask per monitor. On the bottom layer, under every
// window, click-through; Bar.qml sets level, 1 while the bar itself is
// transparent (an empty workspace), fading with the bar's own backdrop.
PanelWindow {
    id: scrim
    property real level: 0
    WlrLayershell.namespace: "sichos-bar-scrim"
    WlrLayershell.layer: WlrLayer.Bottom
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight * 4

    readonly property string maskPath: Theme.barScrim[scrim.screen.name] ?? ""

    Image {
        anchors.fill: parent
        source: scrim.maskPath ? "file://" + scrim.maskPath : ""
        smooth: true
        opacity: scrim.level
    }

    // A monitor plugged in after the wallpaper was set has no mask yet:
    // ask for the set once, after the colors file has been read at all.
    property bool asked: false
    readonly property bool missing: Theme.wallpaperColors.barScrim !== undefined && scrim.maskPath === ""
    onMissingChanged: if (missing && !asked) { asked = true; scrimProc.running = true }
    Process {
        id: scrimProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper.py", "scrim"]
    }
}
