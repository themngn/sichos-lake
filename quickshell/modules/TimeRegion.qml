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
    property string lcTime: ""
    property string lcMeasurement: ""
    property string lcPaper: ""
    property string lcAddress: ""
    property string lcTelephone: ""
    // "Set automatically": systemd-timesyncd via timedate1 (timedatectl
    // set-ntp), same polkit path as the timezone.
    property bool ntp: false
    property bool ntpSynced: false
    property bool canNtp: true
    // The full valid-value lists (Launcher.qml turns these into a
    // searchable list instead of a free-text field — nobody has
    // "Europe/Kyiv" or "en_US.UTF-8" memorized character-for-character).
    property var timezones: []
    property var locales: []
    // locale name -> {decimalPoint, thousandsSep, currencySymbol, langName,
    // countryName, date, currencyCode} — real glibc-derived facts (see locale-info.sh)
    // Launcher.qml uses to show "English (United Kingdom)", "31/12/26",
    // "1,234.56", "£" instead of the bare locale code.
    property var localeInfo: ({})
    // Every locale there is a language pack for, installed or not
    // (scripts/locale-catalog.py): [{locale, langName, countryName,
    // variant, pkg, installed}]. Loaded when a Language/Region picker
    // first opens (loadCatalog), not at startup -- it reads dnf's metadata.
    property var catalog: []
    property bool catalogLoading: false
    function loadCatalog() {
        if (root.catalog.length === 0 && !root._catalogProc.running) root._catalogProc.running = true
    }
    property Process _catalogProc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/locale-catalog.py"]
        onRunningChanged: root.catalogLoading = running
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.catalog = JSON.parse(text) } catch (e) { }
            }
        }
    }
    // Picking a locale that isn't installed installs its language pack
    // (pkexec: hyprpolkitagent asks for the password, as for the timezone),
    // re-reads the locale lists, then makes the pick: localectl refuses a
    // locale that isn't installed. `installing` is the pack's language
    // while dnf runs; a failure lands in installError.
    property string installing: ""
    property string installError: ""
    property var _afterInstall: null
    function install(entry, then) {
        if (root._installProc.running) return
        root.installing = entry.langName
        root.installError = ""
        root._afterInstall = then
        root._installProc.command = ["pkexec", "dnf", "install", "-y", entry.pkg]
        root._installProc.running = true
    }
    property Process _installProc: Process {
        stderr: StdioCollector { id: installErr }
        onExited: (code) => {
            if (code === 0) {
                root._pendingAfterLists = root._afterInstall
                root.catalog = []
                root.loadCatalog()
                root.localeListProc.running = true
                root.localeInfoProc.running = true
            } else {
                // 126/127: the password prompt was dismissed or failed.
                root.installError = code === 126 || code === 127 ? "Not installed: no permission"
                    : "Couldn't install " + root.installing + (installErr.text.trim() ? ": " + installErr.text.trim().split("\n").pop() : "")
            }
            root.installing = ""
            root._afterInstall = null
        }
    }
    // Runs the pick once the new locale shows up in localeInfo.
    property var _pendingAfterLists: null
    onLocaleInfoChanged: {
        if (root._pendingAfterLists) {
            const f = root._pendingAfterLists
            root._pendingAfterLists = null
            f()
        }
    }
    // [{id, city, country, note, offset, abbr}] (scripts/timezones.py):
    // the zones a person would pick, with names instead of zoneinfo ids.
    property var zoneInfo: []

    readonly property bool use24Hour: adapter.use24Hour
    function setUse24Hour(value) { adapter.use24Hour = value }

    function refresh() {
        tzProc.running = true
        localeProc.running = true
    }
    function setNtp(on) {
        Quickshell.execDetached(["timedatectl", "set-ntp", on ? "true" : "false"])
        refreshTimer.restart()
    }
    // The Region (what other systems call it): a country's units, paper
    // size, address and phone formats -- and its date, number and currency
    // formats too, but only those still following the old region (or the
    // language): one picked on its own (setLcTime & co.) stays as it is,
    // as on macOS. "" = same as Language. Sort order stays with the
    // language.
    readonly property string region: root.lcMeasurement || root.lang
    function _base(loc) { return (loc || "").replace(/\.[^@]*/, "") }
    function setRegion(value) {
        const old = root._base(root.region)
        const follows = v => !v || root._base(v) === old
        if (follows(root.lcTime)) root.lcTime = value
        if (follows(root.lcNumeric)) root.lcNumeric = value
        if (follows(root.lcMonetary)) root.lcMonetary = value
        root.lcMeasurement = value
        root.lcPaper = value
        root.lcAddress = value
        root.lcTelephone = value
        root.applyLocale()
    }
    function setTimezone(tz) {
        Quickshell.execDetached(["timedatectl", "set-timezone", tz])
        refreshTimer.restart()
    }
    // value === "" clears that category's override (falls back to lang).
    function setLang(value) { root.lang = value; root.applyLocale() }
    function setLcNumeric(value) { root.lcNumeric = value; root.applyLocale() }
    function setLcMonetary(value) { root.lcMonetary = value; root.applyLocale() }
    function setLcTime(value) { root.lcTime = value; root.applyLocale() }
    function setLcCollate(value) { root.lcCollate = value; root.applyLocale() }
    function applyLocale() {
        const args = ["LANG=" + root.lang]
        if (root.lcNumeric) args.push("LC_NUMERIC=" + root.lcNumeric)
        if (root.lcMonetary) args.push("LC_MONETARY=" + root.lcMonetary)
        if (root.lcCollate) args.push("LC_COLLATE=" + root.lcCollate)
        if (root.lcTime) args.push("LC_TIME=" + root.lcTime)
        if (root.lcMeasurement) args.push("LC_MEASUREMENT=" + root.lcMeasurement)
        if (root.lcPaper) args.push("LC_PAPER=" + root.lcPaper)
        if (root.lcAddress) args.push("LC_ADDRESS=" + root.lcAddress)
        if (root.lcTelephone) args.push("LC_TELEPHONE=" + root.lcTelephone)
        Quickshell.execDetached(["localectl", "set-locale"].concat(args))
        refreshTimer.restart()
    }

    property Process tzProc: Process {
        command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP", "-p", "NTPSynchronized", "-p", "CanNTP"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {}
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0) v[line.slice(0, i)] = line.slice(i + 1)
                }
                root.timezone = v.Timezone || ""
                root.ntp = v.NTP === "yes"
                root.ntpSynced = v.NTPSynchronized === "yes"
                root.canNtp = v.CanNTP !== "no"
            }
        }
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
        root.lcTime = extract("LC_TIME")
        root.lcMeasurement = extract("LC_MEASUREMENT")
        root.lcPaper = extract("LC_PAPER")
        root.lcAddress = extract("LC_ADDRESS")
        root.lcTelephone = extract("LC_TELEPHONE")
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
                currencySymbol: parts[3] || "",
                langName: parts[4] || "",
                countryName: parts[5] || "",
                date: parts[6] || "",
                currencyCode: parts[7] || ""
            }
        }
        root.localeInfo = info
    }
    property Process zoneInfoProc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/timezones.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.zoneInfo = JSON.parse(text) } catch (e) { root.zoneInfo = [] }
            }
        }
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
        zoneInfoProc.running = true
    }
}
