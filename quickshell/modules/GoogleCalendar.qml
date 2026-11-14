pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Google Calendar events for the hub (month grid dots, day agenda) and their
// reminders, from scripts/gcal.py (read-only Calendar API, the user's own
// OAuth client; sign-in = `gcal.py auth` in kitty, see its header).
//
// A singleton on purpose: the hub exists once per screen, so a fetch or a
// reminder timer inside it would run (and notify) once per monitor.
// Reminders are Google's own popup reminders (per event, or the calendar's
// defaults), posted with notify-send so they go through Notifications.qml
// like any other notification; which ones have fired is kept on disk,
// because quickshell re-creates this object on every hot-reload.
QtObject {
    id: root

    // "loading" until the first answer, then gcal.py's "ok" / "needsAuth" / "error".
    property string status: "loading"
    property string error: ""
    property bool stale: false
    property real fetched: 0
    property var events: []
    // "YYYY-MM-DD" -> [event, ...], in start order (all-day first per start).
    readonly property var byDay: {
        const m = {}
        for (const e of root.events)
            for (const d of e.days) (m[d] = m[d] || []).push(e)
        for (const d in m)
            m[d].sort((a, b) => (b.allDay - a.allDay) || (a.start - b.start))
        return m
    }
    readonly property bool connected: root.status === "ok"
    readonly property bool busy: root._proc.running

    function dayKey(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
            + "-" + String(d.getDate()).padStart(2, "0")
    }
    function eventsOn(key) { return root.byDay[key] || [] }

    // The agenda: `key`'s events; with fewer than `min`, the next days' are
    // added (a whole day at a time, each event once) until there are `min`.
    // Items: {event, day} -- day = the day it's listed under.
    function agenda(key, min) {
        const out = [], seen = {}
        const [y, m, d] = key.split("-").map(Number)
        for (let i = 0; i < 120; i++) {
            const k = root.dayKey(new Date(y, m - 1, d + i))
            if (i > 0 && out.length >= min) break
            for (const e of root.eventsOn(k)) {
                if (seen[e.id]) continue
                // A multi-day event that started before a following day is
                // already over by its listing there; only show it on its first day.
                if (i > 0 && e.days[0] !== k) continue
                seen[e.id] = true
                out.push({ event: e, day: k })
            }
        }
        return out
    }

    function refresh() {
        if (!root._proc.running) root._proc.running = true
    }
    // Hub open: refresh if the last answer is more than 2 minutes old.
    function refreshIfStale() {
        if (Date.now() - root._lastRun > 120000) root.refresh()
    }
    function connect() {
        Quickshell.execDetached(["kitty", "--class", "sichos-gcal", "--hold", "python3",
            Quickshell.env("HOME") + "/.config/quickshell/scripts/gcal.py", "auth"])
    }
    function open(e) {
        Quickshell.execDetached(["xdg-open", e && e.link ? e.link : "https://calendar.google.com/"])
    }

    function _apply(data) {
        root.status = data.state || "error"
        root.error = data.error || ""
        root.stale = !!data.stale
        root.fetched = data.fetched || 0
        root.events = data.events || []
    }

    property real _lastRun: 0
    property Process _proc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/gcal.py", "fetch"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._lastRun = Date.now()
                try { root._apply(JSON.parse(text)) } catch (e) { root.status = "error" }
                root._checkReminders()
            }
        }
    }
    // The last result on the first frame (gcal.py keeps it, 0600), before
    // the first fetch's network round trips.
    property FileView _cache: FileView {
        path: Quickshell.env("HOME") + "/.cache/sichos/gcal.json"
        printErrors: false
        onLoaded: {
            if (root.status !== "loading") return
            try { root._apply(JSON.parse(text())) } catch (e) {}
        }
    }
    property Timer _poll: Timer {
        interval: 300000 // 5 min
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    // The first fetch waits a little: at login quickshell starts alongside
    // autostart.lua's keyring unlock (gcal.py also checks the keyring is up
    // and keeps the cache if not). The cache above covers the wait.
    property Timer _firstFetch: Timer {
        interval: 8000
        running: true
        onTriggered: root.refresh()
    }

    // --- reminders ---
    // Fired "<event id>@<reminder ms>" keys, pruned after a day.
    property var _fired: ({})
    property FileView _firedFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/sichos/gcal-notified.json"
        printErrors: false
        onLoaded: {
            try { root._fired = JSON.parse(text()) } catch (e) {}
            root._firedReady = true
        }
        onLoadFailed: root._firedReady = true // none yet
    }
    property bool _firedReady: false
    property Timer _remindTick: Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root._checkReminders()
    }
    function _checkReminders() {
        // Not read yet (first second after a reload): wait, or every
        // reminder still in its window would fire a second time.
        if (!root._firedReady) return
        const now = Date.now()
        let changed = false
        for (const e of root.events) {
            for (const r of e.remind) {
                // 10 minutes of slack covers a suspend or a late poll; never
                // for an event that's already over.
                if (now < r || now - r > 600000 || now >= e.end) continue
                const key = e.id + "@" + r
                if (root._fired[key]) continue
                root._fired[key] = r
                changed = true
                root._notify(e)
            }
        }
        for (const k in root._fired)
            if (now - root._fired[k] > 86400000) { delete root._fired[k]; changed = true }
        if (changed) root._firedFile.setText(JSON.stringify(root._fired))
    }
    function _when(e) {
        const fmt = TimeRegion.use24Hour ? "HH:mm" : "h:mm AP"
        if (e.allDay) return "All day"
        const mins = Math.round((e.start - Date.now()) / 60000)
        const rel = mins <= 0 ? "Now" : mins < 60 ? "In " + mins + " min"
            : "In " + Math.round(mins / 60) + " h"
        return rel + " · " + Qt.formatTime(new Date(e.start), fmt) + "–" + Qt.formatTime(new Date(e.end), fmt)
    }
    function _notify(e) {
        const body = [root._when(e), e.location].filter(x => !!x).join("\n")
        // Title, body and link go in as positional arguments, never spliced
        // into the script. Clicking the toast ("default") opens the event.
        Quickshell.execDetached(["sh", "-c",
            'a=$(notify-send -a "Google Calendar" -i x-office-calendar --action=default=Open -- "$1" "$2"); '
            + '[ "$a" = default ] && xdg-open "$3"',
            "sh", e.title, body, e.link || "https://calendar.google.com/"])
    }

    property IpcHandler _ipc: IpcHandler {
        target: "calendar"
        function refresh(): void { root.refresh() }
    }
}
