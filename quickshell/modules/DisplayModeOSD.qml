import QtQuick
import Quickshell
import Quickshell.Wayland
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
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

    property string mode: "extend"

    IpcHandler {
        target: "displaymode"
        function pop(mode: string) {
            osd.mode = mode
            osd.visible = true
            hideTimer.restart()
            ShellState.activeOsd = "displaymode"
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
            if (ShellState.activeOsd !== "displaymode") {
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
                glyph: "󰹑"
                color: Theme.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Centered in the space right of the icon, not left-aligned with
                // the rest of the card empty.
                width: content.width - osdIcon.width - content.spacing
                horizontalAlignment: Text.AlignHCenter
                text: osd.mode === "mirror" ? "Mirroring" : "Extended"
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.text
            }
        }
    }
}
