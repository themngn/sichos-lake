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

    // A genuine quickshell restart (crash+relaunch, reboot) resets D-Bus
    // notification ids back to a small counter, so the first notifications
    // of a new process can reuse a notifId that's still sitting, unwithdrawn,
    // in the history persisted from a previous process. Namespacing every
    // stored/looked-up notifId with a token scoped to the current process
    // keeps add()'s replace-dedup below and removeByNotifId()'s withdrawal
    // matching from silently merging with, or deleting, an unrelated new
    // notification that happens to reuse the same id after a restart.
    // Deliberately Quickshell.processId, not a value regenerated fresh here
    // (e.g. Date.now()) -- this singleton itself gets torn down and rebuilt
    // on every QML hot-reload (confirmed live: a plain content-edit save
    // changes this object's construction, not just the touched file), while
    // the underlying NotificationServer and its D-Bus id counter survive
    // that same reload untouched (NotificationServer.keepOnReload, default
    // true). A token that changed on every reload made removeByNotifId()
    // fail for anything added before the last reload -- i.e. real
    // withdrawal was broken by the exact case (editing this repo) this
    // machine spends the most time in. processId is stable across reload
    // and still changes on the restarts this is actually meant to guard
    // against.
    readonly property string sessionId: String(Quickshell.processId)

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
        // Without this, a notification still open across a hot-reload (see
        // sessionId above) fires onNotification -> add() -> writeAdapter()
        // as soon as this singleton is reconstructed, which can race the
        // FileView's own async initial read: if the write lands first, it
        // overwrites the on-disk file with just that one entry before the
        // real persisted history was ever loaded into adapter.entries --
        // confirmed live, this silently discarded the entire history file
        // down to 1-2 entries. blockLoading forces the JsonAdapter's initial
        // population to finish before anything else in this file's
        // Component.onCompleted-equivalent (i.e. before any add() from a
        // reload-carried-over notification) can run.
        blockLoading: true
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property var entries: []
        }
    }
}
