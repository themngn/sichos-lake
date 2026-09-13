import QtQuick
import Quickshell
import Quickshell.Io

// Same Windows-11-style transient overlay as VolumeOSD.qml/BacklightOSD.qml,
// for the SUPER+P mirror/extend toggle (hypr/keybindings.lua). Unlike those
// two, there's no PipeWire property or sysfs file to watch reactively here —
// monitor mirror state is purely internal Hyprland state — so the keybind's
// Lua function pokes this directly over IPC (`quickshell ipc call
// displaymode pop <mode>`) right after it applies the hl.monitor() calls,
// the same way HdrSettings.qml's "hdr toggle" IPC target is driven from a
// keybind rather than this being watched for.
PanelWindow {
    id: osd

    property string mode: "extend"

    IpcHandler {
        target: "displaymode"
        function pop(mode: string) {
            osd.mode = mode
            osd.visible = true
            hideTimer.restart()
        }
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
                    // Same glyph DisplaySettings.qml's bar pill uses for
                    // "monitor/display" (nf-md-monitor) — mirror vs. extend
                    // is told apart by the label below, not a second glyph.
                    text: "󰹑"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 3
                    color: Theme.text
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: osd.mode === "mirror" ? "Mirroring" : "Extended"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 1.2
                color: Theme.text
            }
        }
    }
}
