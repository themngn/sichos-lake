import QtQuick
import Quickshell
import Quickshell.Io

// Same Windows-11-style transient overlay as VolumeOSD.qml, for brightness --
// pops up on any backlight change (media keys, Backlight.qml's own scroll
// wheel, brightnessctl run from anywhere) since it watches the same sysfs
// file Backlight.qml itself reads, and fades out after a couple seconds of
// no further change.
PanelWindow {
    id: osd

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
                    text: osd.icon()
                    font.family: Theme.fontFamily
                    // Material Design brightness glyphs ink ~600/1000em
                    // (fontTools glyf bbox) -- same scale Backlight.qml uses.
                    font.pixelSize: Theme.fontSize * 3 * 600 / 1000
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
