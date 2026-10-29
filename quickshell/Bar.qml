import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "./modules"

PanelWindow {
    id: bar
    // Own namespace so hypr/window_rules.lua can blur this bar's popups
    // (menus/tooltips) without blurring the bar itself.
    WlrLayershell.namespace: "sichos-bar"

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight

    // Keyboard only while a popup field wants text (ShellState.keySink);
    // otherwise the bar never takes focus from windows.
    readonly property bool takesKeys: ShellState.keySink !== null && ShellState.keySinkScreen === bar.screen.name
    WlrLayershell.keyboardFocus: bar.takesKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Item {
        focus: true
        Keys.onPressed: (event) => {
            if (!bar.takesKeys) return
            ShellState.keySink.handleKey(event)
            event.accepted = true
        }
    }

    // "Bar on this screen only" (ShellState.barSoloScreen). Hiding unmaps
    // the layer surface, so the exclusive zone goes with it and windows
    // reclaim the space. Falls back to showing everywhere if the pinned
    // screen isn't connected anymore -- otherwise unplugging that monitor
    // would leave no bar at all to toggle it back from.
    visible: ShellState.barSoloScreen === ""
        || ShellState.barSoloScreen === bar.screen.name
        || !Quickshell.screens.some(s => s.name === ShellState.barSoloScreen)

    // Transparent over an empty desktop, semi-opaque (BarSettings.terminalOpacity,
    // the transparency popup's slider -- the same level kitty uses) once this monitor's
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
    readonly property real backdropTarget: (ShellState.transparencyOpaque || bar.hdrActiveHere) ? 1.0
        : (bar.activeWorkspaceHasWindows ? BarSettings.terminalOpacity : 0.0)
    // One animated value drives both the backdrop and BarScrim's shade.
    // They used to fade separately (200ms OutQuad each), and halfway through
    // the shade was half gone while the backdrop was still half clear -- a
    // bright wallpaper flashed lighter for a moment before the bar went
    // dark. Tied together, the darkness only moves one way. Timed like
    // Hyprland's window fades (hypr/look_and_feel.lua: fadeIn speed 1.73 =
    // 173ms, fadeOut 1.46 = 146ms, both the "almostLinear" curve), so the
    // bar darkens in step with a window fading in -- the terminal only
    // fades (window_rules.lua) -- and clears with the last one fading out.
    // Keep these in step with those animations.
    property real backdropAlpha: backdropTarget
    Behavior on backdropAlpha {
        NumberAnimation {
            duration: bar.backdropTarget > bar.backdropAlpha ? 173 : 146
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.5, 0.5, 0.75, 1, 1, 1]
        }
    }
    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, bar.backdropAlpha)

    // Shade behind the transparent bar where the wallpaper is bright.
    BarScrim {
        screen: bar.screen
        // Hands over to the backdrop as it fades in. Fading the shade out
        // linearly (1 - f) cancelled the backdrop's first half -- filmed: a
        // bright spot stayed flat (even lightened) while a window faded in,
        // then darkened ~100ms late. With f the backdrop's progress and T
        // its alpha, opacity (1-f)/(1-T*f) makes shade s + backdrop add up
        // to exactly s + (T - s)*f at every pixel, whatever its s: the
        // darkness follows the window's own fade curve.
        level: {
            if (!bar.visible) return 0
            const t = Math.max(0.05, BarSettings.terminalOpacity)
            const f = Math.min(1, bar.backdropAlpha / t)
            const rest = 1 - Math.min(1, bar.backdropAlpha)
            return rest < 0.001 ? 0 : (1 - f) / rest
        }
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
    Component { id: systemUpdateComp; SystemUpdate { screenName: bar.screen.name; popupHost: barMorph.slot; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: aiModelUsageComp; AiModelUsage { screenName: bar.screen.name; popupHost: barMorph.slot; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: notificationCenterComp; NotificationCenter { screen: bar.screen; screenName: bar.screen.name; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: languageComp; Language { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: bluetoothComp; BluetoothIndicator { screenName: bar.screen.name; popupHost: barMorph.slot; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: networkComp; NetworkIndicator { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: volumeComp; Volume { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: backlightComp; Backlight { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: displayComp; DisplaySettings { screenName: bar.screen.name; popupHost: barMorph.slot; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: powerProfileComp; PowerProfile { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: batteryComp; Battery { horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: quickSettingsComp; QuickSettings { screenName: bar.screen.name; popupHost: barMorph.slot; horizontalPadding: 4 * Theme.barIconSpacingScale } }
    Component { id: phoneMirrorComp; PhoneMirror { screenName: bar.screen.name; horizontalPadding: 4 * Theme.barIconSpacingScale } }

    function componentFor(id) {
        switch (id) {
        case "tray": return trayComp
        case "system-update": return systemUpdateComp
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
        case "phone": return phoneMirrorComp
        case "quicksettings": return quickSettingsComp
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
    // transparency/mic-mute/notification-mute toggles are secondary and sit
    // to its left rather than sharing the center point.
    ClockWidget {
        id: clock
        screenName: bar.screen.name
        popupHost: barMorph.slot
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
    }
    // Whether any of this row's own popups (every toggle has one) is currently
    // open on THIS screen. Keeps the row
    // revealed while a popup is open even after the pointer leaves the row's
    // own bounds for the popup below it (its own window, outside toggleRow's
    // geometry, so toggleRowHover alone would otherwise drop to unhovered
    // and fade the row out from under an still-open popup).
    readonly property bool toggleRowPopupOpen: ["idle", "mic", "notifmute"]
        .includes(ShellState.activePopup)
        && ShellState.activePopupScreen === bar.screen.name

    // Invisible hover target that bootstraps the reveal from a collapsed
    // row (width 0 everywhere has no area to hover into otherwise). Sized to
    // the row's fully *expanded* footprint -- every pill's implicitWidth
    // (unaffected by its collapse animation) plus the Row's spacing -- so the
    // whole area the row will occupy opens it, not just a strip next to the
    // clock. `anyToggleHovered` below still keeps it open from each pill's
    // own MouseArea. (A zone that undershot the expanded row used to make
    // hovering a fully-grown icon outside it collapse the row and re-grow
    // it -- a rapid open/close flicker; matching the expanded size avoids
    // that too.) Renders nothing.
    Item {
        id: toggleHoverZone
        anchors {
            right: clock.left
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        width: {
            const pills = toggleRow.children
            let w = 0
            for (let i = 0; i < pills.length; i++) w += pills[i].implicitWidth
            return w + toggleRow.spacing * Math.max(0, pills.length - 1)
        }
        height: Theme.barHeight

        HoverHandler { id: toggleRowHover }
    }

    // Once any pill has grown enough to be hovered directly, its own
    // MouseArea (real, geometry-accurate, unlike the fixed bootstrap zone
    // above) keeps the whole row revealed -- see toggleHoverZone's comment.
    readonly property bool anyToggleHovered: idleToggle.hovered
        || micMuteToggle.hovered || notificationMuteToggle.hovered
    readonly property bool toggleRowRevealed: toggleRowHover.hovered || bar.toggleRowPopupOpen || bar.anyToggleHovered

    // The one morphing card every hover popup on this bar renders into --
    // see MorphPopup.qml.
    MorphPopup {
        id: barMorph
        bar: bar
    }

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

        IdleToggle {
            id: idleToggle
            popupHost: barMorph.slot
            screenName: bar.screen.name
            revealed: bar.toggleRowRevealed
            active: ShellState.idleActive
            onToggle: ShellState.idleActive = !ShellState.idleActive
            onSettingsSaved: {
                // hypridle only reads its config at startup — restart its
                // systemd --user service to pick up the new listeners.
                Quickshell.execDetached(["systemctl", "--user", "restart", "hypridle.service"])
            }
        }
        MicMuteToggle {
            id: micMuteToggle
            popupHost: barMorph.slot
            screenName: bar.screen.name
            revealed: bar.toggleRowRevealed
            source: Pipewire.defaultAudioSource
        }
        NotificationMuteToggle {
            id: notificationMuteToggle
            popupHost: barMorph.slot
            screenName: bar.screen.name
            revealed: bar.toggleRowRevealed
            muted: ShellState.notificationsMuted
            onToggle: ShellState.setNotificationsMuted(!ShellState.notificationsMuted, 0)
        }
    }
    Row {
        anchors {
            left: clock.right
            leftMargin: 4
            verticalCenter: parent.verticalCenter
        }
        spacing: 4

        Weather { screenName: bar.screen.name; popupHost: barMorph.slot }
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
                screenName: bar.screen.name
                popupHost: barMorph.slot
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
