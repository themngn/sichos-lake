pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Current system timezone/locale, and the means to change them, for the
// launcher's Settings > Time & Region screen. Both timedatectl/localectl
// go through their systemd D-Bus services (org.freedesktop.timedate1/
// locale1), which polkit gates — hyprpolkitagent (already autostarted, see
// autostart.lua) pops the auth prompt automatically, same as Nautilus
// mounting a LUKS drive, so no explicit pkexec/sudo is needed here.
//
// "Locale" isn't one setting — LANG is the fallback every category (date/
// time, numbers, currency, sort order, ...) uses unless a category has its
// own explicit override, which is what lang/lcNumeric/lcMonetary/
// lcCollate below are. `localectl set-locale` REPLACES the whole locale
// config with exactly the assignments it's given (it doesn't merge with
// what's already set) — so applyLocale() always resends every category
// together, not just the one that changed, or the others would silently
// revert to the C/POSIX default.
//
// 12-hour vs 24-hour isn't one of those categories: it's not a real,
// independently-selectable locale fact (glibc locales each hard-code one
// hour convention baked into a whole language+territory bundle — there's
// no "en_US but 24-hour"), and picking a locale just to get a clock format
// is exactly the "not a proper switch" complaint that use24Hour below
// fixes — a plain, persisted on/off preference for the quickshell bar's
// own clock (ClockWidget.qml), the same way a normal OS's clock-format
// toggle works (it doesn't touch system locale either).
QtObject {
    id: root

    property string timezone: ""
    property string lang: ""
    property string lcNumeric: ""
    property string lcMonetary: ""
    property string lcCollate: ""
    // The full valid-value lists (Launcher.qml turns these into a
    // searchable list instead of a free-text field — nobody has
    // "Europe/Kyiv" or "en_US.UTF-8" memorized character-for-character).
    property var timezones: []
    property var locales: []
    // locale name -> {decimalPoint, thousandsSep, currencySymbol} — real
    // glibc-derived facts (see locale-info.sh) Launcher.qml uses to show a
    // human preview ("1,234.56", "£") instead of the bare locale code for
    // the categories where that's meaningful.
    property var localeInfo: ({})

    readonly property bool use24Hour: adapter.use24Hour
    function setUse24Hour(value) { adapter.use24Hour = value }

    function refresh() {
        tzProc.running = true
        localeProc.running = true
    }
    function setTimezone(tz) {
        Quickshell.execDetached(["timedatectl", "set-timezone", tz])
        refreshTimer.restart()
    }
    // value === "" clears that category's override (falls back to lang).
    function setLang(value) { root.lang = value; root.applyLocale() }
    function setLcNumeric(value) { root.lcNumeric = value; root.applyLocale() }
    function setLcMonetary(value) { root.lcMonetary = value; root.applyLocale() }
    function setLcCollate(value) { root.lcCollate = value; root.applyLocale() }
    function applyLocale() {
        const args = ["LANG=" + root.lang]
        if (root.lcNumeric) args.push("LC_NUMERIC=" + root.lcNumeric)
        if (root.lcMonetary) args.push("LC_MONETARY=" + root.lcMonetary)
        if (root.lcCollate) args.push("LC_COLLATE=" + root.lcCollate)
        Quickshell.execDetached(["localectl", "set-locale"].concat(args))
        refreshTimer.restart()
    }

    property Process tzProc: Process {
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector { onStreamFinished: root.timezone = text.trim() }
    }
    property Process localeProc: Process {
        command: ["localectl", "status"]
        stdout: StdioCollector { onStreamFinished: root._parseLocaleStatus(text) }
    }
    function _parseLocaleStatus(text) {
        function extract(varName) {
            const m = text.match(new RegExp(varName + "=(\\S+)"))
            return m ? m[1] : ""
        }
        root.lang = extract("LANG") || "en_US.UTF-8"
        root.lcNumeric = extract("LC_NUMERIC")
        root.lcMonetary = extract("LC_MONETARY")
        root.lcCollate = extract("LC_COLLATE")
    }
    // Both list-populating calls: fetched once at startup, not on every
    // screen open — the set of valid zoneinfo names and generated locales
    // doesn't change within a running session.
    property Process tzListProc: Process {
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: root.timezones = text.split("\n").filter(s => s.length > 0) }
    }
    property Process localeListProc: Process {
        command: ["locale", "-a"]
        stdout: StdioCollector { onStreamFinished: root.locales = text.split("\n").filter(s => s.length > 0) }
    }
    property Process localeInfoProc: Process {
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/locale-info.sh"]
        stdout: StdioCollector { onStreamFinished: root._parseLocaleInfo(text) }
    }
    function _parseLocaleInfo(text) {
        const info = {}
        for (const line of text.split("\n")) {
            if (!line) continue
            const parts = line.split("|")
            info[parts[0]] = {
                decimalPoint: parts[1] || "",
                thousandsSep: parts[2] || "",
                currencySymbol: parts[3] || ""
            }
        }
        root.localeInfo = info
    }
    // The polkit prompt above takes a moment for the user to approve, so
    // the refreshed value is fetched after a short delay rather than
    // immediately (which would just re-read the pre-change one).
    property Timer refreshTimer: Timer {
        interval: 1500
        onTriggered: root.refresh()
    }

    property FileView _use24HourFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/time-region.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property bool use24Hour: true
        }
    }

    Component.onCompleted: {
        refresh()
        tzListProc.running = true
        localeListProc.running = true
        localeInfoProc.running = true
    }
}
