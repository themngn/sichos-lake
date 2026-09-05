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

    // A quickshell restart (reboot, or a dev hot-reload that doesn't
    // preserve the NotificationServer) resets D-Bus notification ids back
    // to a small counter, so the first notifications of a new session can
    // reuse a notifId that's still sitting, unwithdrawn, in the history
    // persisted from a previous session. Namespacing every stored/looked-up
    // notifId with a token generated fresh each time this singleton is
    // constructed keeps add()'s replace-dedup below and removeByNotifId()'s
    // withdrawal matching scoped to the current session only, so a stale
    // entry from a prior boot can never be silently merged with, or deleted
    // by, an unrelated new notification that happens to reuse the same id.
    readonly property string sessionId: Date.now() + "-" + Math.floor(Math.random() * 1e6)

    function add(entry) {
        const notifId = entry.notifId !== undefined ? root.sessionId + ":" + entry.notifId : undefined
        // Many senders (progress dialogs, chat apps bumping an unread
        // count, media players) don't send a brand new notification to
        // update one already on screen — they reuse the same D-Bus id
        // (replaces_id), and the server fires onNotification again for
        // each such generation. Treating every generation as a new
        // history entry both floods the list with duplicates for what the
        // user perceives as a single notification, and defeats
        // removeByNotifId() below when the app eventually withdraws it
        // (only the single newest match gets dropped, leaving older
        // generations of the same notification stuck in history forever)
        // — so an update replaces its own previous entry in place instead
        // of stacking a new one.
        const idx = notifId !== undefined ? adapter.entries.findIndex(e => e.notifId === notifId) : -1
        const withId = Object.assign(
            { id: idx !== -1 ? adapter.entries[idx].id : Date.now() + "-" + Math.floor(Math.random() * 10000) },
            entry, notifId !== undefined ? { notifId } : {})
        const rest = idx !== -1 ? adapter.entries.filter((_, i) => i !== idx) : adapter.entries
        adapter.entries = [withId].concat(rest).slice(0, root.maxEntries)
    }
    function remove(id) {
        adapter.entries = adapter.entries.filter(e => e.id !== id)
    }
    // notifId is the sender's own D-Bus notification id (namespaced with
    // sessionId above), not this store's own `id`.
    function removeByNotifId(notifId) {
        const idx = adapter.entries.findIndex(e => e.notifId === root.sessionId + ":" + notifId)
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
