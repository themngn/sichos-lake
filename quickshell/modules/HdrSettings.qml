pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Which monitors get HDR applied when HDR mode is on, editable from the HDR
// pill's popup (HdrToggle.qml/HdrPopup.qml, next to Warm Light in Bar.qml).
// Some displays tone-map HDR badly (crushed blacks, washed colors) so this is
// opt-in per monitor rather than the pill being a single switch that hits
// every screen — toggling it on only drives whichever monitors are checked
// here. Both `monitors` and `active` persist (JsonAdapter, same pattern as
// BarSettings) -- HDR only ever lands on monitors explicitly checked here, so
// keeping it on across a restart can't surprise an unchecked one.
QtObject {
    id: root

    property alias active: adapter.active

    function isSelected(name) {
        return adapter.monitors.indexOf(name) !== -1
    }

    function toggleMonitor(name) {
        adapter.monitors = root.isSelected(name)
            ? adapter.monitors.filter(n => n !== name)
            : adapter.monitors.concat([name])
        root.apply()
    }

    function toggleActive() {
        root.setActive(!root.active)
    }

    function setActive(v) {
        if (root.active === v) return
        root.active = v
        root.apply()
    }

    // Pushes the current active/monitors selection to every currently
    // connected output. This Lua-config build of Hyprland has no plain
    // `hyprctl keyword monitor` (legacy-parser only — confirmed live,
    // "keyword can't work with non-legacy parsers. Use eval."), so a live
    // one-off monitor rule change has to go through hl.monitor() the same
    // way autostart-launch.py uses hl.exec_cmd(). Confirmed live that
    // hl.monitor({output=...}) only patches the fields given (cm/bitdepth
    // here) and leaves mode/position/scale/etc. exactly as they were — no
    // need to read back and round-trip a monitor's full geometry first.
    // bitdepth=10 has to be set alongside cm="hdr": cm="hdr" alone left
    // colorManagementPreset at "srgb" in `hyprctl monitors -j`, and only
    // adding bitdepth=10 actually flipped currentFormat to XRGB2101010.
    function apply() {
        for (const m of Hyprland.monitors.values) {
            const on = root.active && root.isSelected(m.name)
            const spec = on
                ? '{output="' + m.name + '",cm="hdr",bitdepth=10}'
                : '{output="' + m.name + '",cm="auto",bitdepth=false}'
            Quickshell.execDetached(["hyprctl", "eval", "hl.monitor(" + spec + ")"])
        }
    }

    // Lets `quickshell ipc call hdr toggle` drive this from outside — used
    // by the Win+Shift+H keybind (hypr/keybindings.lua) so the key, the bar
    // pill, and the popup's On/Off buttons all funnel through the same
    // state instead of the keybind needing its own copy of the monitor list.
    // QtObject has no default property (unlike Item's `data`), so this has
    // to be assigned to a property rather than left as a bare child — same
    // reason _view below is a property instead of a bare FileView.
    property IpcHandler _ipc: IpcHandler {
        target: "hdr"
        function toggle() { root.toggleActive() }
    }

    // Any Hyprland config reload (a save of any hypr/*.lua, including
    // save-monitor-config.py's monitors.lua writes from the Display page)
    // re-applies monitors.lua's rules, which have no cm/bitdepth -- HDR went
    // off while the toggle still said on. hl.monitor() via eval doesn't
    // itself emit configreloaded (checked on socket2), so this can't loop.
    property Connections _reloads: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.active) root.apply()
        }
    }

    property FileView _view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/hdr-monitors.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()
        // Re-applies the saved state on load: after a login monitors.lua
        // starts every output in SDR, and after a quickshell restart this
        // pins every monitor to a known state rather than trusting whatever
        // hl.monitor() calls happened to be live from before it.
        onLoaded: root.apply()

        adapter: JsonAdapter {
            id: adapter
            property var monitors: []
            property bool active: false
        }
    }
}
