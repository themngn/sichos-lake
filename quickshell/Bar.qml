import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
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
    // Confirmed live: on a bitdepth=10 (HDR, see HdrSettings.apply) output,
    // any non-opaque bar surface bands/noises constantly — worse the closer
    // its alpha sits to (but short of) fully transparent (tried alpha 1/255
    // as a "still see-through" compromise; that was worse than plain
    // "transparent", not better). Only alpha=1.0 was clean, so on an
    // HDR-active monitor the bar just stays forced opaque, same as
    // ShellState.transparencyOpaque, regardless of workspace state — this
    // gives up the "floats over the wallpaper" look only where HDR is on.
    readonly property bool hdrActiveHere: HdrSettings.active && bar.hyprMonitor && HdrSettings.isSelected(bar.hyprMonitor.name)
    // TransparencyToggle overrides the dynamic behavior above with a
    // constant solid backdrop, matching kitty's background_opacity going to
    // 1.0 at the same time (see ShellState.transparencyOpaque).
    color: (ShellState.transparencyOpaque || bar.hdrActiveHere)
        ? bar.fullyOpaqueBackground
        : (bar.activeWorkspaceHasWindows ? bar.opaqueBackground : "transparent")
    Behavior on color {
        ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    IdleInhibitor {
        window: bar
        enabled: ShellState.idleActive
    }

    // Keeps defaultAudioSource's audio.muted property actually live-bound —
    // same reasoning as Volume.qml's own PwObjectTracker on defaultAudioSink.
    PwObjectTracker {
        objects: Pipewire.defaultAudioSource ? [Pipewire.defaultAudioSource] : []
    }

    // One Component per right-section widget, picked by id at runtime so
    // BarSettings' order/enabled state (edited from the launcher's
    // Settings > Bar Widgets folder) can reshuffle and show/hide them
    // without Bar.qml hardcoding a fixed declaration order. Night Light,
    // Stay Awake, and the transparency toggle below aren't part of this —
    // they're a fixed trio, not covered by BarSettings.
    //
    // horizontalPadding: 4 * Theme.barIconSpacingScale (down from Pill's
    // default 8) on every one of these -- paired with this Row's spacing: 0
    // below, that reproduces the original ~8px visual gap between icons
    // (4 + 0 + 4, before the scale) without the negative-Row-spacing hack
    // that used to cause it (see that comment). Theme.barIconSpacingScale
    // tunes that gap globally without touching each Component's own value.
    // Center-group Pills (SunsetToggle/HdrToggle/IdleToggle/
    // TransparencyToggle, Weather, CustomWidget) aren't touched -- they
    // keep Pill's real default.
    // Extra margin (double every other widget's) on the tray specifically --
    // it reads as a distinct cluster of app icons rather than a single
    // glyph like its neighbors, so it wants more breathing room on both
    // sides than the uniform 4 * barIconSpacingScale everything else gets.
    Component { id: trayComp; Tray { horizontalPadding: 12 * Theme.barIconSpacingScale } }
    Component { id: aiModelUsageComp; AiModelUsage { screenName: bar.screen.name; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: notificationCenterComp; NotificationCenter { screen: bar.screen; screenName: bar.screen.name; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: languageComp; Language { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: bluetoothComp; BluetoothIndicator { screenName: bar.screen.name; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: networkComp; NetworkIndicator { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: volumeComp; Volume { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: backlightComp; Backlight { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: displayComp; DisplaySettings { screenName: bar.screen.name; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: powerProfileComp; PowerProfile { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: batteryComp; Battery { horizontalPadding: 4 * Theme.barIconSpacingScale } }

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
    // transparency/mic-mute toggles are secondary and sit to its left rather
    // than sharing the center point.
    ClockWidget {
        id: clock
        screenName: bar.screen.name
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
    }
    // Whether any of this row's own popups (Sunset/Hdr/Idle) is currently
    // open on THIS screen -- TransparencyToggle has no popup. Keeps the row
    // revealed while a popup is open even after the pointer leaves the row's
    // own bounds for the popup below it (its own window, outside toggleRow's
    // geometry, so toggleRowHover alone would otherwise drop to unhovered
    // and fade the row out from under an still-open popup).
    readonly property bool toggleRowPopupOpen: ["sunset", "hdr", "idle"].includes(ShellState.activePopup)
        && ShellState.activePopupScreen === bar.screen.name

    // Fixed invisible hover target used only to bootstrap the very first
    // reveal from a fully-collapsed row (width 0 everywhere has no area to
    // hover into otherwise). Its exact size doesn't need to precisely match
    // the pills' real footprint -- once growth has begun, `anyToggleHovered`
    // below (each pill's own real, geometry-accurate MouseArea) takes over
    // and keeps the row open, which is what actually matters: a fixed zone
    // sized to the pills' *collapsed* state will always undershoot their
    // *expanded* one, so hovering squarely on a fully-grown icon (outside
    // this zone) used to read as "not hovered" and collapse the row out
    // from under the pointer -- which re-entered the zone and grew again,
    // producing a rapid open/close flicker. Renders nothing.
    Item {
        id: toggleHoverZone
        anchors {
            right: clock.left
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        width: 180
        height: Theme.barHeight

        HoverHandler { id: toggleRowHover }
    }

    // Once any pill has grown enough to be hovered directly, its own
    // MouseArea (real, geometry-accurate, unlike the fixed bootstrap zone
    // above) keeps the whole row revealed -- see toggleHoverZone's comment.
    readonly property bool anyToggleHovered: sunsetToggle.hovered || hdrToggle.hovered
        || idleToggle.hovered || transparencyToggle.hovered || micMuteToggle.hovered
    readonly property bool toggleRowRevealed: toggleRowHover.hovered || bar.toggleRowPopupOpen || bar.anyToggleHovered

    Row {
        id: toggleRow
        anchors {
            right: clock.left
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        spacing: 4
        // Row is anchored by its right edge only (above), so as children
        // collapse and its total width shrinks, the row naturally contracts
        // toward the clock rather than leaving a gap on that side. No
        // separate `move: Transition` here -- each pill's own width
        // Behavior already changes smoothly every frame, and Row recomputes
        // every sibling's x live off of that same continuously-changing
        // value, so motion is already smooth. Layering a positioner `move`
        // transition on top made it chase a constantly-shifting target
        // (retargeted every frame while widths were mid-animation) instead
        // of a single fixed destination -- suspected cause of the hover
        // flicker that kept a pill's popup from ever settling open; removed
        // rather than tuned since it was redundant with the width Behavior.

        SunsetToggle {
            id: sunsetToggle
            screenName: bar.screen.name
            revealed: bar.toggleRowRevealed
            active: ShellState.sunsetWarm
            scheduleFollow: ShellState.sunsetScheduleFollow
            kelvin: ShellState.sunsetKelvin
            // Pill click and the popup's On/Off buttons both land here —
            // ShellState.forceSunsetWarm owns the dedup-guard, the state
            // write, and the matching hyprctl push, and deliberately never
            // touches sunsetScheduleFollow.
            onSetWarm: (warm) => ShellState.forceSunsetWarm(warm)
            // Dragging the warmth slider only presets the kelvin value —
            // it deliberately does NOT force the light on or touch
            // "Follow schedule". ShellState.setSunsetKelvin owns the
            // debounced disk write + hyprctl push (see its own comment for
            // why that's debounced rather than firing per pixel).
            onSetTemperature: (k) => ShellState.setSunsetKelvin(k)
            // The popup's "Follow schedule" checkbox — ShellState.
            // setScheduleFollow owns the dedup-guard and, when re-enabling,
            // the immediate resync to whatever the schedule currently says.
            onSetScheduleFollow: (follow) => ShellState.setScheduleFollow(follow)
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
                ShellState.setScheduleFollow(true)
                Quickshell.execDetached(["systemctl", "--user", "restart", "hyprsunset.service"])
            }
        }
        HdrToggle {
            id: hdrToggle
            screenName: bar.screen.name
            revealed: bar.toggleRowRevealed
        }
        IdleToggle {
            id: idleToggle
            screenName: bar.screen.name
            revealed: bar.toggleRowRevealed
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
            id: transparencyToggle
            revealed: bar.toggleRowRevealed
            opaque: ShellState.transparencyOpaque
            onToggle: {
                ShellState.transparencyOpaque = !ShellState.transparencyOpaque
                Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/toggle-transparency.py",
                    ShellState.transparencyOpaque ? "opaque" : "semi"])
            }
        }
        MicMuteToggle {
            id: micMuteToggle
            revealed: bar.toggleRowRevealed
            source: Pipewire.defaultAudioSource
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
        // User-local, not part of this repo — see CustomWidget.qml's own
        // comment and CustomWidgets.qml. One entry per
        // ~/.config/quickshell/custom/<id>/main.qml found on this machine,
        // installed/removed (and reordered/toggled) from the launcher's
        // Settings > Custom Plugins folder (or by hand, same as the
        // original alert-widget precedent) — orderedIds() rather than
        // `widgets` directly so a drag-reorder there is reflected here too.
        Repeater {
            model: CustomWidgets.orderedIds()

            delegate: CustomWidget {
                required property string modelData
                name: modelData
            }
        }
    }

    // Right section
    // Zero, not negative, spacing: negative spacing here used to make
    // adjacent Pills' Items physically overlap by the same amount, and
    // since each Pill's MouseArea is anchors.fill: parent, the overlapping
    // strip was claimed by both — the right-hand Pill always won (later Row
    // sibling), so every pill had 8px of dead click-through on its left
    // edge that silently fired its right neighbor's handler instead (this
    // is exactly what BluetoothIndicator.qml's old fixed-width comment was
    // papering over). Zero spacing tiles pills edge-to-edge with zero
    // overlap; each BarIcon (see modules/BarIcon.qml) now also reports an
    // accurate, identical-width implicitWidth. The visual gap this used to
    // fake via negative spacing (8px, matching Tray's own inter-icon
    // spacing) comes instead from each widget's horizontalPadding: 4 below
    // (4 + 0 + 4 = 8) — a real non-overlapping gap rather than a
    // padding-cancellation hack.
    Row {
        anchors {
            right: parent.right
            rightMargin: 2
            verticalCenter: parent.verticalCenter
        }
        spacing: 0

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
