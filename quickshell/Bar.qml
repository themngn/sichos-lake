import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
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

    // Transparent over an empty desktop, 80% opaque once this monitor's
    // active workspace actually has a window on it — otherwise the bar
    // reads as "floating over the wallpaper" when there's nothing behind
    // it to separate from, and gets a real backdrop the moment there is.
    readonly property var hyprMonitor: {
        const list = Hyprland.monitors.values
        for (const m of list) if (m.name === bar.screen.name) return m
        return null
    }

    // Bumped on every window lifecycle event so activeWorkspaceHasWindows
    // (which loops Hyprland.toplevels.values by hand rather than reading a
    // single notifying property) reliably recomputes — same reasoning as
    // Workspaces.qml's own windowEpoch.
    property int windowEpoch: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow"
                || event.name === "movewindow" || event.name === "movewindowv2")
                bar.windowEpoch++
        }
    }

    readonly property bool activeWorkspaceHasWindows: {
        const epoch = bar.windowEpoch // forces recompute on every window event
        if (!bar.hyprMonitor || !bar.hyprMonitor.activeWorkspace) return false
        const wsId = bar.hyprMonitor.activeWorkspace.id
        return Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === wsId)
    }

    readonly property color opaqueBackground: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
    readonly property color fullyOpaqueBackground: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 1.0)
    // TransparencyToggle overrides the dynamic behavior above with a
    // constant solid backdrop, matching kitty's background_opacity going to
    // 1.0 at the same time (see ShellState.transparencyOpaque).
    color: ShellState.transparencyOpaque
        ? bar.fullyOpaqueBackground
        : (bar.activeWorkspaceHasWindows ? bar.opaqueBackground : "transparent")
    Behavior on color {
        ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    IdleInhibitor {
        window: bar
        enabled: ShellState.idleActive
    }

    // One Component per right-section widget, picked by id at runtime so
    // BarSettings' order/enabled state (edited from the launcher's
    // Settings > Bar Widgets folder) can reshuffle and show/hide them
    // without Bar.qml hardcoding a fixed declaration order. Night Light,
    // Stay Awake, and the transparency toggle below aren't part of this —
    // they're a fixed trio, not covered by BarSettings.
    Component { id: trayComp; Tray {} }
    Component { id: aiModelUsageComp; AiModelUsage { screenName: bar.screen.name } }
    Component { id: notificationCenterComp; NotificationCenter { screen: bar.screen; screenName: bar.screen.name } }
    Component { id: languageComp; Language {} }
    Component { id: bluetoothComp; BluetoothIndicator { screenName: bar.screen.name } }
    Component { id: networkComp; NetworkIndicator {} }
    Component { id: volumeComp; Volume {} }
    Component { id: backlightComp; Backlight {} }
    Component { id: displayComp; DisplaySettings { screenName: bar.screen.name } }
    Component { id: powerProfileComp; PowerProfile {} }
    Component { id: batteryComp; Battery {} }

    function componentFor(id) {
        switch (id) {
        case "tray": return trayComp
        case "ai-model-usage":
        case "claude-usage": return aiModelUsageComp
        case "notifications": return notificationCenterComp
        case "language": return languageComp
        case "bluetooth": return bluetoothComp
        case "network": return networkComp
        case "volume": return volumeComp
        case "backlight": return backlightComp
        case "display": return displayComp
        case "powerprofile": return powerProfileComp
        case "battery": return batteryComp
        }
        return null
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

    // Center section — the clock owns true screen-center; the sunset/idle/
    // transparency toggles are secondary and sit to its left rather than
    // sharing the center point.
    ClockWidget {
        id: clock
        screenName: bar.screen.name
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
    }
    Row {
        anchors {
            right: clock.left
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        spacing: 4

        SunsetToggle {
            screenName: bar.screen.name
            active: ShellState.sunsetWarm
            mode: ShellState.sunsetMode
            kelvin: ShellState.sunsetKelvin
            scheduleWarm: ShellState.sunsetWarm
            onModeSelected: (mode) => {
                // Re-clicking the already-active mode would still fire a
                // real gamma push (stutters the cursor for a frame) for
                // zero actual change — skip it.
                if (mode === ShellState.sunsetMode) return
                ShellState.sunsetMode = mode
                if (mode === "schedule") Quickshell.execDetached(["hyprctl", "hyprsunset", "reset"])
                else if (mode === "off") Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"])
            }
            // Dragging the warmth slider always implies manual "on" mode —
            // ShellState.setSunsetKelvin owns the mode switch plus the
            // debounced disk write + hyprctl push (see its own comment for
            // why that's debounced rather than firing per pixel).
            onSetTemperature: (k) => ShellState.setSunsetKelvin(k)
            onScheduleSaved: {
                // hyprsunset only reads its config at startup — no live-reload
                // IPC exists — so the edited profile times only take effect
                // after a restart. hyprsunset now runs as its packaged
                // systemd --user service (see autostart.lua's comment on the
                // uwsm/graphical-session.target migration) rather than a
                // plain background process — systemctl handles the
                // stop-then-start sequencing itself (clean SIGTERM wait
                // before restart), so no manual sleep/stale-socket cleanup
                // is needed anymore the way the old `pkill; hyprsunset &`
                // dance required. Only actually restarts anything under the
                // uwsm-managed session — see that same autostart.lua comment
                // for why a non-uwsm session leaves this a silent no-op.
                ShellState.sunsetMode = "schedule"
                Quickshell.execDetached(["systemctl", "--user", "restart", "hyprsunset.service"])
            }
        }
        HdrToggle {
            screenName: bar.screen.name
        }
        IdleToggle {
            screenName: bar.screen.name
            active: ShellState.idleActive
            onToggle: ShellState.idleActive = !ShellState.idleActive
            onSettingsSaved: {
                // hypridle only reads its config at startup, same as
                // hyprsunset — now via its systemd --user service too, same
                // reasoning as hyprsunset's onScheduleSaved above.
                Quickshell.execDetached(["systemctl", "--user", "restart", "hypridle.service"])
            }
        }
        TransparencyToggle {
            opaque: ShellState.transparencyOpaque
            onToggle: {
                ShellState.transparencyOpaque = !ShellState.transparencyOpaque
                Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/toggle-transparency.py",
                    ShellState.transparencyOpaque ? "opaque" : "semi"])
            }
        }
    }
    Row {
        anchors {
            left: clock.right
            leftMargin: 4
            verticalCenter: parent.verticalCenter
        }
        spacing: 4

        Weather { screenName: bar.screen.name }
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
            rightMargin: 2
            verticalCenter: parent.verticalCenter
        }
        spacing: -8

        Repeater {
            model: BarSettings.orderedIds()
            delegate: Loader {
                required property string modelData
                // active skips instantiating a disabled widget at all (no
                // point running e.g. AiModelUsage's poll loop for
                // something nobody sees). visible mirrors the loaded item's
                // own visible (falling back to true while it's still
                // loading) — that's what makes Row actually skip it and
                // close the gap, and it doubles as the hook a widget can use
                // to self-hide (AiModelUsage does, when no AI agent process
                // is running) without Bar.qml needing to know why.
                active: BarSettings.isEnabled(modelData)
                visible: active
                sourceComponent: bar.componentFor(modelData)
            }
        }
    }
}
