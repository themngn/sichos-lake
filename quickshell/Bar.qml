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
    // Each Pill already carries 8px horizontalPadding on both sides, so two
    // adjacent pills stack 16px of padding between their icons before any
    // Row spacing is added. Tray's own icons (inside one Pill) sit exactly
    // 8px apart with no padding doubling — matching that here means
    // cancelling the doubled padding with negative spacing (8 - 8 - 8 = -8).
    Row {
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: -8

        Tray {}
        Language {}
        NetworkIndicator {}
        Volume {}
        Backlight {}
        PowerProfile {}
        Battery {}
    }
}
