pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
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

        // A run of separate notifications (distinct notifIds, so not the
        // replaces_id case above) sharing the same app+summary -- e.g. a
        // Telegram chat sending several messages in a row, each announced
        // as its own notification but all titled "<contact> -> <chat>" --
        // otherwise floods this list with near-duplicate rows. Folding a
        // new one into the most recent entry instead, as long as it's
        // still the same app+summary and nothing else has landed in
        // between (i.e. it's genuinely consecutive, not just "same title,
        // sometime earlier"), keeps one row per burst with a count badge
        // (rendered in NotificationCenter.qml) instead.
        const top = adapter.entries[0]
        if (idx === -1 && top && top.appName === entry.appName && top.summary === entry.summary) {
            // `bodies` carries every message in the run (oldest first) so
            // NotificationCenter.qml can expand the merged row and show
            // each one in full -- `body`/`time` alone (overwritten to the
            // newest message below via the entry spread) would silently
            // discard everything but the latest message's text.
            const priorBodies = top.bodies || [{ body: top.body, time: top.time }]
            const merged = Object.assign({}, top, entry, {
                id: top.id,
                count: (top.count || 1) + 1,
                bodies: priorBodies.concat([{ body: entry.body, time: entry.time }])
            }, notifId !== undefined ? { notifId } : {})
            adapter.entries = [merged].concat(adapter.entries.slice(1))
            return
        }

        const withId = Object.assign(
            { id: idx !== -1 ? adapter.entries[idx].id : Date.now() + "-" + Math.floor(Math.random() * 10000) },
            entry, notifId !== undefined ? { notifId } : {})
        const rest = idx !== -1 ? adapter.entries.filter((_, i) => i !== idx) : adapter.entries
        adapter.entries = [withId].concat(rest).slice(0, root.maxEntries)
    }
    // Live Notification objects by namespaced notifId, so a history entry
    // can still reach its notification's own actions (NotificationCenter's
    // click -> the sender's "default" action, e.g. Telegram opening that
    // chat) for as long as it's tracked -- see Notifications.qml's grace
    // timer for how long that is. Deliberately not part of the persisted
    // adapter: these are live objects, meaningless after a restart (and
    // rebuilt from NotificationServer's re-announcement after a hot-reload,
    // since registerLive() is called for lastGeneration ones too).
    property var live: ({})
    function registerLive(notification) {
        root.live[root.sessionId + ":" + notification.id] = notification
    }
    function unregisterLive(notifId) {
        delete root.live[root.sessionId + ":" + notifId]
    }
    // The live notification behind a history entry, if it's still tracked.
    function liveFor(entry) {
        const n = entry.notifId !== undefined ? root.live[entry.notifId] : undefined
        return n && n.tracked ? n : null
    }

    // Brings up the app behind a notification that has no usable action of
    // its own (or no longer has a live notification at all): focus its
    // existing window, or launch it if none is open. Shared by the toast
    // (Notifications.qml) and Notification Center clicks.
    function focusOrLaunchApp(desktopEntry, appName) {
        const app = (desktopEntry && DesktopEntries.byId(desktopEntry))
            || (appName && DesktopEntries.heuristicLookup(appName))
            || null
        // Window classes this app's windows could plausibly carry: the
        // desktop file's StartupWMClass first (the one that's actually
        // authoritative), then its id / the sender's names as fallbacks.
        const classes = [app && app.startupClass, app && app.id, desktopEntry, appName]
            .filter(c => c)
            .map(c => c.toLowerCase())
        const window = Hyprland.toplevels.values.find(t => {
            // lastIpcObject is empty for windows opened after quickshell
            // started (see Workspaces.qml's addressClassMap comment).
            const cls = (t.lastIpcObject && t.lastIpcObject.class) || (t.wayland && t.wayland.appId)
            return cls && classes.includes(cls.toLowerCase())
        })
        if (window) {
            // `hyprctl dispatch` doesn't work on this Lua-config build --
            // hl.dispatch via eval is the supported route (see CLAUDE.md).
            const addr = "0x" + window.address.replace(/^0x/, "")
            Quickshell.execDetached(["hyprctl", "eval",
                "hl.dispatch(hl.dsp.focus({ window = " + JSON.stringify("address:" + addr) + " }))"])
        } else if (app) {
            app.execute()
        }
    }

    function remove(id) {
        adapter.entries = adapter.entries.filter(e => e.id !== id)
    }
    // Dismisses a single message out of a folded (count > 1) entry's
    // `bodies` run -- NotificationCenter.qml's expanded-message close
    // glyph. Collapses the entry back down to a plain, non-folded shape
    // (no count/bodies field, same as an entry add() has never merged
    // anything into) once only one message is left, rather than leaving a
    // count-1 badge/bodies array of length 1 around.
    function removeMessage(id, index) {
        const idx = adapter.entries.findIndex(e => e.id === id)
        if (idx === -1) return
        const entry = adapter.entries[idx]
        if (!entry.bodies || entry.bodies.length <= 1) {
            root.remove(id)
            return
        }
        const bodies = entry.bodies.slice()
        bodies.splice(index, 1)
        const next = adapter.entries.slice()
        if (bodies.length === 1) {
            const only = bodies[0]
            const collapsed = Object.assign({}, entry, { body: only.body, time: only.time })
            delete collapsed.count
            delete collapsed.bodies
            next[idx] = collapsed
        } else {
            // body/time always mirror the newest remaining message (last
            // in bodies), same convention add()'s merge uses for the
            // collapsed-row preview text.
            const newest = bodies[bodies.length - 1]
            next[idx] = Object.assign({}, entry, { bodies, count: bodies.length, body: newest.body, time: newest.time })
        }
        adapter.entries = next
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
