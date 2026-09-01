pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Past notifications shown in the bar's Notification Center popup
// (NotificationCenter.qml). Independent of the live toasts in
// Notifications.qml — a toast expiring on its own timeout, or the user
// dismissing/clicking it away, doesn't erase its record here; those are
// still things worth being able to scroll back to, so only Clear All (or
// clicking an individual entry) removes them. The one case that *does*
// auto-remove is the sender itself withdrawing the notification (D-Bus
// CloseNotification — e.g. Telegram closing a message notification once
// it's been read in-app) — that's the app saying the notification is no
// longer relevant, which is different from it merely having been shown
// already, so Notifications.qml calls removeByNotifId() for that case only.
// Entries store the raw appIcon/image strings from the notification rather
// than a resolved path, same as Notifications.qml, so NotificationCenter.qml
// resolves them the same way at render time.
QtObject {
    id: root

    readonly property int maxEntries: 50

    function add(entry) {
        const withId = Object.assign(
            { id: Date.now() + "-" + Math.floor(Math.random() * 10000) }, entry)
        adapter.entries = [withId].concat(adapter.entries).slice(0, root.maxEntries)
    }
    function remove(id) {
        adapter.entries = adapter.entries.filter(e => e.id !== id)
    }
    // notifId is the sender's own D-Bus notification id (not this store's
    // own `id`) — findIndex/splice instead of filter so only the single
    // newest match is dropped, since entries are newest-first and ids can
    // in principle repeat across a long enough session.
    function removeByNotifId(notifId) {
        const idx = adapter.entries.findIndex(e => e.notifId === notifId)
        if (idx === -1) return
        const next = adapter.entries.slice()
        next.splice(idx, 1)
        adapter.entries = next
    }
    function clear() {
        adapter.entries = []
    }

    readonly property var entries: adapter.entries

    property FileView view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/notification-history.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property var entries: []
        }
    }
}
