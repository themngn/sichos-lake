pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Enumerates ~/.config/quickshell/custom/*/main.qml (list-custom-widgets.py)
// and drives installing/removing entries there (custom-widget.py) — the
// launcher's Settings > Custom Plugins folder and Bar.qml's Repeater over
// `widgets` both read from this. The directory is the source of truth (see
// CustomWidget.qml's own comment); this holds no separate registry, so a
// widget dropped/symlinked in by hand shows up here too after a refresh().
QtObject {
    id: root
    property var widgets: []
    // Set while install()/remove() has a script running — the launcher UI
    // uses this to show a spinner/disable input rather than let a second
    // request race the first.
    property bool busy: false
    // Set by install()/remove() right before their Process exits, since
    // Process.exec doesn't carry a script's own stdout back synchronously —
    // the launcher reads this once busy flips back to false.
    property string lastError: ""

    property Process indexer: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/list-custom-widgets.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.widgets = JSON.parse(text)
                } catch (e) {
                    root.widgets = []
                }
            }
        }
    }
    function refresh() {
        indexer.running = false
        indexer.running = true
    }

    property Process installer: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                let result
                try {
                    result = JSON.parse(text)
                } catch (e) {
                    result = { ok: false, error: "no response from custom-widget.py" }
                }
                root.lastError = result.ok ? "" : (result.error || "failed")
                if (result.ok) root.refresh()
            }
        }
        // Fallback for install()/remove() staying stuck on "Installing…"
        // forever if python3 fails to spawn at all or dies before ever
        // writing stdout (custom-widget.py itself always prints a JSON
        // result on every path, so this is the belt to that script's own
        // suspenders) — onStreamFinished above already clears `busy` on the
        // normal path, so this is a no-op then.
        onExited: root.busy = false
    }
    // CustomWidget.qml's own comment says its Loader only resolves `source`
    // once and won't pick up an *existing* widget's files changing — but
    // that's about a single already-instantiated Loader, not this list.
    // Bar.qml's Repeater instantiates a brand new CustomWidget (and Loader)
    // per id here, so a widget appearing in/disappearing from `widgets`
    // does reach the bar immediately, no quickshell restart needed —
    // confirmed live, including for removal.
    function install(source, id) {
        if (root.busy) return
        root.busy = true
        root.lastError = ""
        const args = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/custom-widget.py", "install", source]
        if (id) args.push(id)
        installer.command = args
        installer.running = true
    }
    function remove(id) {
        if (root.busy) return
        root.busy = true
        root.lastError = ""
        installer.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/custom-widget.py", "remove", id]
        installer.running = true
    }

    // Enabled/disabled + display-order state, same pattern as BarSettings —
    // a plugin left installed but toggled off just stops CustomWidget.qml's
    // Loader from activating (see that file), no uninstall/reinstall needed
    // to temporarily silence one; order is separate from `widgets` (which
    // reflects list-custom-widgets.py's own, install-time ordering) so
    // dragging one in the launcher survives a refresh()/quickshell restart.
    function isEnabled(id) {
        return settingsAdapter.disabled.indexOf(id) === -1
    }
    function enable(id) {
        settingsAdapter.disabled = settingsAdapter.disabled.filter(n => n !== id)
    }
    function disable(id) {
        if (root.isEnabled(id)) settingsAdapter.disabled = settingsAdapter.disabled.concat([id])
    }
    function toggle(id) {
        if (root.isEnabled(id)) root.disable(id)
        else root.enable(id)
    }

    // All installed widget ids in the user's chosen order — any id missing
    // from the saved order (a widget installed since the user's last
    // reorder) is appended at the end in `widgets`' own order; any saved id
    // no longer installed (removed) is silently dropped.
    function orderedIds() {
        const allIds = root.widgets.map(w => w.id)
        const known = settingsAdapter.order.filter(id => allIds.indexOf(id) !== -1)
        const uniqueKnown = known.filter((id, index) => known.indexOf(id) === index)
        const missing = allIds.filter(id => uniqueKnown.indexOf(id) === -1)
        return uniqueKnown.concat(missing)
    }
    function moveUp(id) {
        const ids = root.orderedIds()
        const i = ids.indexOf(id)
        if (i <= 0) return
        const tmp = ids[i - 1]
        ids[i - 1] = ids[i]
        ids[i] = tmp
        settingsAdapter.order = ids
    }
    function moveDown(id) {
        const ids = root.orderedIds()
        const i = ids.indexOf(id)
        if (i === -1 || i >= ids.length - 1) return
        const tmp = ids[i + 1]
        ids[i + 1] = ids[i]
        ids[i] = tmp
        settingsAdapter.order = ids
    }

    property FileView settingsView: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/custom-widgets-settings.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: settingsAdapter
            property var disabled: []
            property var order: []
        }
    }

    Component.onCompleted: refresh()
}
