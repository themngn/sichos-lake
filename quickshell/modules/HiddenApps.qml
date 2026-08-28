pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    function isHidden(name) {
        return adapter.hidden.indexOf(name) !== -1
    }
    function hide(name) {
        if (!root.isHidden(name)) adapter.hidden = adapter.hidden.concat([name])
    }
    function unhide(name) {
        adapter.hidden = adapter.hidden.filter(n => n !== name)
    }

    property FileView view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/hidden-apps.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property var hidden: []
        }
    }
}
