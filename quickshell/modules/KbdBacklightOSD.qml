import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Same Windows-11-style transient overlay as VolumeOSD.qml/BacklightOSD.qml,
// for the keyboard backlight. Unlike screen backlight, this can't rely on
// watchChanges/inotify: confirmed live with inotifywait that the physical
// Fn key changes /sys/class/leds/asus::kbd_backlight/brightness (and
// brightness_hw_changed) without ever firing a filesystem change
// notification, even though the value genuinely does update and the actual
// LED visibly dims/brightens -- a known quirk of this sysfs LED classdev
// attribute being updated kernel-side rather than via a normal write().
// Polling is the only thing that reliably sees it. Only 4 raw steps (0-3)
// on this hardware, not a smooth 0-100 range like screen backlight/volume,
// so the percent readout only ever lands on 0/33/67/100 -- expected, not a
// bug.
PanelWindow {
    id: osd
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

    readonly property int percent: maxFile.text().length > 0 && brightnessFile.text().length > 0
        ? Math.round((Number(brightnessFile.text()) / Number(maxFile.text())) * 100)
        : 0

    // Guards the very first poll tick (going from "nothing loaded yet" to
    // the real value) from popping the OSD on every quickshell startup.
    property bool ready: false
    onPercentChanged: {
        if (ready) osd.pop()
        ready = true
    }

    FileView {
        id: brightnessFile
        path: "/sys/class/leds/asus::kbd_backlight/brightness"
        printErrors: false
    }
    FileView {
        id: maxFile
        path: "/sys/class/leds/asus::kbd_backlight/max_brightness"
        printErrors: false
    }

    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: brightnessFile.reload()
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
            if (ShellState.activeOsd !== "kbdbacklight") {
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
        ShellState.activeOsd = "kbdbacklight"
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
                glyph: "󰌌"
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
