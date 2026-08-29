pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Apps toggled on in the launcher's Autostart folder. Only the app *name*
// is persisted (not exec/icon) — hypr/autostart.lua's launch script
// re-resolves those from a fresh .desktop scan at login, same as
// HiddenApps does for its own name list.
QtObject {
    id: root

    function isEnabled(name) {
        return adapter.enabled.indexOf(name) !== -1
    }
    function enable(name) {
        if (!root.isEnabled(name)) adapter.enabled = adapter.enabled.concat([name])
    }
    function disable(name) {
        adapter.enabled = adapter.enabled.filter(n => n !== name)
    }
    function toggle(name) {
        if (root.isEnabled(name)) root.disable(name)
        else root.enable(name)
    }

    property FileView view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/autostart-apps.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property var enabled: []
        }
    }
}
