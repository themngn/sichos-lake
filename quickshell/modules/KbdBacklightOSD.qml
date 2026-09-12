import QtQuick
import Quickshell
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

    implicitWidth: 260
    implicitHeight: 64

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osd.visible = false
    }

    function pop() {
        osd.visible = true
        hideTimer.restart()
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
                    anchors.centerIn: parent
                    text: "󰌌"
                    font.family: Theme.fontFamily
                    // nf-md-keyboard ink 582/1000em (fontTools glyf bbox).
                    font.pixelSize: Theme.fontSize * 3 * 582 / 1000
                    color: Theme.text
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
                    width: track.width * (osd.percent / 100)
                    height: track.height
                    radius: 0
                    color: Theme.accent
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2.5
                text: osd.percent + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.text
            }
        }
    }
}
