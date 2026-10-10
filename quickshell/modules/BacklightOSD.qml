import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Same Windows-11-style transient overlay as VolumeOSD.qml, for brightness --
// pops up on any backlight change (media keys, Backlight.qml's own scroll
// wheel, brightnessctl run from anywhere) since it watches the same sysfs
// file Backlight.qml itself reads, and fades out after a couple seconds of
// no further change.
PanelWindow {
    id: osd
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

    readonly property int percent: maxFile.text().length > 0 && brightnessFile.text().length > 0
        ? Math.round((Number(brightnessFile.text()) / Number(maxFile.text())) * 100)
        : 0

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/amdgpu_bl1/brightness"
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload()
            osd.pop()
        }
    }
    FileView {
        id: maxFile
        path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
        printErrors: false
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
            if (ShellState.activeOsd !== "backlight") {
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
        osd.visible = true
        hideTimer.restart()
        ShellState.activeOsd = "backlight"
    }

    // Same moon-phase glyph set as Backlight.qml's icon() -- kept identical
    // (not re-derived) so the bar pill and this OSD always agree on which
    // "phase" a given percentage maps to.
    function icon() {
        const icons = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
        const idx = Math.max(0, Math.min(icons.length - 1, Math.round(osd.percent / 100 * (icons.length - 1))))
        return icons[idx]
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
                glyph: osd.icon()
                color: Theme.text
            }

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: content.width - osdIcon.width - percentText.width - 2 * content.spacing
                height: Theme.trackHeight
                radius: Theme.trackRadius
                color: Theme.track

                Rectangle {
                    width: track.width * (osd.percent / 100)
                    height: track.height
                    radius: Theme.trackRadius
                    color: Theme.accent
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2.5
                // Right-aligned so a short value ("7%") doesn't leave a gap at the card's edge.
                horizontalAlignment: Text.AlignRight
                id: percentText
                text: osd.percent + "%"
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.text
            }
        }
    }
}
