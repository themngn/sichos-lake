import QtQuick
import Quickshell
import Quickshell.Wayland
import "./modules"

PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    color: "transparent"

    IdleInhibitor {
        window: bar
        enabled: ShellState.idleActive
    }

    // Left section
    Row {
        anchors {
            left: parent.left
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: 4

        Workspaces {}
        Submap {}
    }

    // Center section — the clock owns true screen-center; the idle toggle
    // is secondary and sits to its left rather than sharing the center point.
    ClockWidget {
        id: clock
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
    }
    IdleToggle {
        anchors {
            right: clock.left
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        active: ShellState.idleActive
        onToggle: ShellState.idleActive = !ShellState.idleActive
    }

    // Right section
    Row {
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: 4

        Tray {}
        NetworkIndicator {}
        Volume {}
        Backlight {}
        Language {}
        PowerProfile {}
        Battery {}
    }
}
