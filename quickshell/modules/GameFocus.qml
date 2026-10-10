pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Gaming Focus: while enabled and a game window has focus, every screen
// *except* the game's own is dimmed (IdleDimOverlay.qml renders it). Toggled
// from the bar's GameFocusToggle. A singleton rather than state on the
// overlay since one overlay exists per screen and they all need the same
// answer, same reasoning as ShellState.idleDimActive. Doesn't persist across
// a quickshell restart, same as the other center-row toggles.
QtObject {
    id: root

    property bool enabled: false

    // Name of the monitor the focused game is on, or "" when no game has
    // focus (or the mode is off). Screens whose name differs get dimmed.
    property string gameMonitor: ""

    readonly property bool dimming: root.enabled && root.gameMonitor !== ""

    // Overlay opacity for the dimmed screens (0..1), set from the pill's
    // popup slider. Unlike `enabled` this does persist (game-focus.json) --
    // it's a preference you tune once, not a per-session switch.
    readonly property real dimAmount: _adapter.dimAmount
    readonly property real minDim: 0.2
    readonly property real maxDim: 1.0

    function setDimAmount(v) {
        _adapter.dimAmount = Math.max(root.minDim, Math.min(root.maxDim, Math.round(v * 20) / 20))
    }

    property FileView _file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/game-focus.json"
        printErrors: false
        // A slider drag changes dimAmount on every mouse move -- debounce the
        // disk write rather than rewriting the file per pixel.
        onAdapterUpdated: root._saveTimer.restart()

        adapter: JsonAdapter {
            id: _adapter
            property real dimAmount: 0.85
        }
    }

    property Timer _saveTimer: Timer {
        interval: 300
        onTriggered: root._file.writeAdapter()
    }

    onEnabledChanged: {
        if (root.enabled) root._recheck.restart()
        else root.gameMonitor = ""
    }

    // Deciding "is this a game" needs /proc/<pid>/environ (see
    // game-focus.py's header), which QML can't read cleanly -- hence a
    // one-shot helper per relevant event instead of lastIpcObject alone.
    property Process _proc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/game-focus.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.enabled) return
                try {
                    root.gameMonitor = JSON.parse(text).monitor || ""
                } catch (e) {
                    root.gameMonitor = ""
                }
            }
        }
    }

    // Coalesces the burst of events a single focus change produces
    // (activewindow + activewindowv2 + focusedmon, etc.) into one helper run.
    property Timer _recheck: Timer {
        interval: 80
        onTriggered: {
            if (root._proc.running) root._recheck.restart()
            else root._proc.running = true
        }
    }

    property Connections _events: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.enabled) return
            switch (event.name) {
            case "activewindowv2":
            case "movewindowv2":
            case "closewindow":
            case "focusedmon":
            case "monitoradded":
            case "monitorremoved":
                root._recheck.restart()
            }
        }
    }
}
