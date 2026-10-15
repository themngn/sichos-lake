pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What closing the laptop lid does while another monitor is connected
// (undocked, logind always suspends): "keep" turns the built-in panel off and
// keeps working on the others, "sleep" suspends. The Control Center's "Lid"
// tile flips it; hypr/keybindings.lua reads the file on every lid close.
QtObject {
    id: root

    readonly property bool sleep: _adapter.mode === "sleep"

    function setSleep(on) {
        _adapter.mode = on ? "sleep" : "keep"
    }

    property FileView _file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/lid-close.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: _adapter
            property string mode: "keep"
        }
    }
}
