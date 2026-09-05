import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Hyprland

// Walker-style launcher: one search box, one list, and the root level is
// a plain directory listing — "Apps", "Toggles" and "Power" are all
// folder entries, apps included, rather than apps being flattened in
// alongside the other two.
PanelWindow {
    id: launcher

    screen: Quickshell.screens[0]
    visible: false
    focusable: true

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Only dim behind the launcher when there's actually a window on the
    // current workspace to dim — on an empty workspace the dim just muddies
    // the wallpaper for no reason. Same activeWorkspaceHasWindows check as
    // Bar.qml, scoped to this launcher's own screen (it's the one PanelWindow
    // instance, always Quickshell.screens[0]).
    readonly property var hyprMonitor: {
        const list = Hyprland.monitors.values
        for (const m of list) if (m.name === launcher.screen.name) return m
        return null
    }
    property int windowEpoch: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow"
                || event.name === "movewindow" || event.name === "movewindowv2")
                launcher.windowEpoch++
        }
    }
    readonly property bool activeWorkspaceHasWindows: {
        const epoch = launcher.windowEpoch // forces recompute on every window event
        if (!launcher.hyprMonitor || !launcher.hyprMonitor.activeWorkspace) return false
        const wsId = launcher.hyprMonitor.activeWorkspace.id
        return Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === wsId)
    }
    color: launcher.activeWorkspaceHasWindows ? Qt.rgba(0, 0, 0, 0.35) : "transparent"

    property string mode: "root" // "root" | "apps" | "toggles" | "power" | "autostart" | "reload" | "settings" | "settings-bar" | "settings-timeregion" | "picklist:<field>" | "folder:<id>" | "folderpick" | "newfoldername" | "appmenu"
    property string query: ""
    property int selectedIndex: 0
    // Which folder to return to when backing out of the app submenu.
    property string returnMode: "apps"
    // The app the submenu (Launch/Hide/Unhide) is currently open for.
    property var contextApp: null

    readonly property var toggleItems: {
        const items = [
            { type: "toggle", id: "idle", name: "Stay Awake", active: ShellState.idleActive, aliases: ["caffeine", "idle inhibit", "keep awake"] },
            { type: "toggle", id: "wifi", name: "Wi-Fi", active: Networking.wifiEnabled, aliases: ["wifi", "wireless"] }
        ]
        if (Bluetooth.defaultAdapter)
            items.push({ type: "toggle", id: "bluetooth", name: "Bluetooth", active: Bluetooth.defaultAdapter.enabled, aliases: ["bt"] })
        return items
    }

    function _barWidgetName(id) {
        for (const w of BarSettings.widgets) {
            if (w.id === id) return w.name
        }
        return id
    }
    // Reflects the user's current order (not BarSettings.widgets' fixed
    // declaration order) — drag-reordered in the ListView delegate below.
    readonly property var barWidgetItems: BarSettings.orderedIds().map(id => ({
        type: "bar-widget",
        id: id,
        name: launcher._barWidgetName(id),
        active: BarSettings.isEnabled(id)
    }))

    readonly property var settingsItems: [
        { type: "folder", id: "settings-bar", name: "Bar Widgets", icon: "" },
        { type: "folder", id: "settings-timeregion", name: "Time & Region", icon: "" },
        { type: "folder", id: "autostart", name: "Autostart", icon: "" },
        { type: "folder", id: "reload", name: "Reload", icon: "" }
    ]

    readonly property var powerItems: [
        { type: "power", id: "logout", name: "Logout", danger: false, aliases: ["log out", "sign out", "exit"] },
        { type: "power", id: "suspend", name: "Suspend", danger: false, aliases: ["sleep"] },
        { type: "power", id: "reboot", name: "Reboot", danger: true, aliases: ["restart"] },
        { type: "power", id: "shutdown", name: "Shutdown", danger: true, aliases: ["poweroff", "power off", "turn off"] }
    ]

    // Hyprland reloads its config live on save already (see install.sh) —
    // this is for forcing it manually. Quickshell has no equivalent "reload
    // config" IPC call, so "reload" for it means killing and respawning the
    // process, same as the SUPER+CTRL+SHIFT+R keybinding in keybindings.lua.
    readonly property var reloadItems: [
        { type: "reload", id: "hyprland", name: "Reload Hyprland", danger: false, aliases: ["restart hyprland"] },
        { type: "reload", id: "quickshell", name: "Reload Quickshell", danger: false, aliases: ["restart quickshell", "restart bar"] }
    ]

    // Every non-hidden, non-Steam app, regardless of folder membership —
    // the base list folder lookups (folderApps below) filter from, and
    // autostartItems is built from, so an app doesn't vanish from those
    // just because appItems (the flat root list, right below) also
    // excludes it there.
    readonly property var browsableApps: AppIndex.apps
        .filter(a => !HiddenApps.isHidden(a.name) && !a.steam)
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal,
                     steam: !!a.steam, iconFile: a.iconFile || "" }))

    // Steam games are deliberately excluded here — like hidden apps, they're
    // only reachable through their own folder (Games), not flat-listed
    // alongside everything else too (they're excluded from browsableApps
    // itself, so no separate check needed). Same for anything in a custom
    // folder, unless that app's "Keep in Apps List" override is on (see
    // AppFolders.keepsInRoot / folderPickItems below).
    readonly property var appItems: launcher.browsableApps
        .filter(a => !AppFolders.isInAnyFolder(a.name) || AppFolders.keepsInRoot(a.name))

    readonly property var hiddenItems: AppIndex.apps
        .filter(a => HiddenApps.isHidden(a.name))
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal,
                     steam: !!a.steam, iconFile: a.iconFile || "" }))

    readonly property var steamAppItems: AppIndex.apps
        .filter(a => a.steam && !HiddenApps.isHidden(a.name))
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal,
                     steam: true, iconFile: a.iconFile || "" }))

    // Deliberately a curated allowlist, not every installed app — autostart
    // only makes sense for apps with a real "start minimized/to tray" flag
    // (checked against each app's own --help/docs; see autostart-launch.py).
    // Spotify/Bitwarden/Proton Pass were considered and left out: none of
    // them has a working CLI flag for it on Linux (Spotify dropped tray
    // support entirely; the other two only expose it as a GUI setting).
    readonly property var autostartCandidates: ["Telegram", "Element", "Vesktop", "Discord", "Steam"]

    readonly property var autostartItems: launcher.browsableApps
        .filter(a => launcher.autostartCandidates.includes(a.name))
        .map(a => ({ type: "autostart-app", name: a.name, exec: a.exec, icon: a.icon,
                     terminal: a.terminal, active: AutostartApps.isEnabled(a.name) }))

    readonly property var appMenuItems: {
        if (!launcher.contextApp) return []
        const hidden = HiddenApps.isHidden(launcher.contextApp.name)
        return [
            { type: "action", id: "launch", name: "Launch" },
            { type: "action", id: hidden ? "unhide" : "hide", name: hidden ? "Unhide" : "Hide" },
            { type: "action", id: "addfolder", name: "Add to Folder" }
        ]
    }

    // Folder rows mixed into the Apps listing itself (see currentItems'
    // "apps" branch below) rather than living behind their own menu: the
    // built-in Games (all installed Steam titles — see
    // AppIndex/list-apps.py) and Hidden folders, computed from other state
    // rather than stored here, plus whatever custom folders AppFolders
    // holds. Games is left out entirely when there are none, so a
    // non-Steam machine doesn't get an empty folder for something it will
    // never use; Hidden always shows, matching its old always-present
    // root-level slot.
    readonly property var folderListItems: {
        const items = []
        if (launcher.steamAppItems.length > 0) items.push({ type: "folder", id: "folder:games", name: "Games", icon: "" })
        for (const f of AppFolders.folders) items.push({ type: "folder", id: "folder:" + f.id, name: f.name, icon: "" })
        return items
    }
    // Always last, after every real app — separate from folderListItems
    // so it can be appended at the end instead of the front. Parenthesized
    // because a bare "{" here would be parsed as a QML statement block,
    // not the object literal it needs to be.
    readonly property var hiddenFolderItem: ({ type: "folder", id: "folder:hidden", name: "Hidden", icon: "" })
    function folderName(id) {
        if (id === "games") return "Games"
        if (id === "hidden") return "Hidden"
        const f = AppFolders.folders.find(f => f.id === id)
        return f ? f.name : "Folder"
    }
    function folderApps(id) {
        if (id === "games") return launcher.steamAppItems
        if (id === "hidden") return launcher.hiddenItems
        const f = AppFolders.folders.find(f => f.id === id)
        if (!f) return []
        return launcher.browsableApps.filter(a => f.apps.includes(a.name))
    }
    // Breadcrumb shown as a dim second line under a search result, since a
    // flat, cross-category query result loses the folder context browsing
    // normally has. Only ever called on rows from allItems (app/toggle/
    // power/reload/time-region action — bar-widget is deliberately absent
    // from allItems, see its comment there), so every branch here is
    // reachable. "use24hour" is a plain toggle type like idle/wifi/
    // bluetooth but lives under Settings > Time & Region, not Toggles, so
    // it needs its own check ahead of the generic toggle case.
    function pathFor(item) {
        if (item.type === "toggle" && item.id === "use24hour") return "Menu > Settings > Time & Region"
        if (item.type === "toggle") return "Menu > Toggles"
        if (item.type === "power") return "Menu > Power"
        if (item.type === "reload") return "Menu > Settings > Reload"
        if (item.type === "action") return "Menu > Settings > Time & Region"
        if (item.steam) return "Menu > Apps > Games"
        const folderNames = AppFolders.folders.filter(f => f.apps.includes(item.name)).map(f => f.name)
        return "Menu > Apps" + (folderNames.length > 0 ? " > " + folderNames.join(", ") : "")
    }
    // The "Add to Folder" submenu for whichever app is in contextApp — a
    // "+ New Folder" action plus every custom folder as an on/off toggle
    // (Games/Hidden aren't offered: their membership is automatic, not
    // something to hand-edit here).
    readonly property var folderPickItems: {
        if (!launcher.contextApp) return []
        const items = [{ type: "action", id: "newfolder", name: "+ New Folder" }]
        if (AppFolders.isInAnyFolder(launcher.contextApp.name))
            items.push({ type: "keepinroot-toggle", name: "Keep in Apps List", active: AppFolders.keepsInRoot(launcher.contextApp.name) })
        for (const f of AppFolders.folders)
            items.push({ type: "folder-toggle", id: f.id, name: f.name, active: AppFolders.hasApp(f.id, launcher.contextApp.name) })
        return items
    }
    function createFolderFromQuery() {
        const name = launcher.query.trim()
        if (!name) return
        const id = AppFolders.create(name)
        if (launcher.contextApp) AppFolders.addApp(id, launcher.contextApp.name)
        launcher.mode = "folderpick"
        launcher.query = ""
        launcher.selectedIndex = 0
    }

    // Turns a locale's territory ("en_AU.UTF-8" -> "AU") into its flag
    // emoji — algorithmic (each letter maps to a Unicode "regional
    // indicator symbol", U+1F1E6 + offset from 'A'), not a lookup table,
    // so it covers every country code for free. "" (no match, e.g. the
    // territory-less "C"/"C.utf8"/"POSIX") just means no flag shows.
    function flagForLocale(loc) {
        const m = loc.match(/_([A-Za-z]{2})/)
        if (!m) return ""
        let flag = ""
        for (const ch of m[1].toUpperCase()) {
            const offset = ch.charCodeAt(0) - 65
            if (offset < 0 || offset > 25) return ""
            flag += String.fromCodePoint(0x1F1E6 + offset)
        }
        return flag
    }
    function localeWithFlag(loc) {
        const flag = launcher.flagForLocale(loc)
        return flag ? flag + " " + loc : loc
    }

    // "Locale" isn't one setting — see TimeRegion.qml's own comment. Each
    // of the LC_* rows is independently overridable, falling back to
    // Language when not explicitly set. 24-Hour Time is deliberately a
    // plain toggle, not a locale pick — see TimeRegion.qml's comment on
    // why "12h vs 24h" isn't a real, independently-selectable locale fact.
    readonly property var timeRegionItems: [
        { type: "action", id: "edit-timezone", name: "Timezone: " + (TimeRegion.timezone || "(unknown)"), aliases: ["tz"] },
        { type: "action", id: "edit-lang", name: "Language: " + (TimeRegion.lang ? launcher.localeWithFlag(TimeRegion.lang) : "(unknown)"), aliases: ["locale"] },
        { type: "toggle", id: "use24hour", name: "24-Hour Time", active: TimeRegion.use24Hour, aliases: ["military time"] },
        { type: "action", id: "edit-lcnumeric", name: "Number Format: " + (TimeRegion.lcNumeric ? launcher.pickListPreview("lcnumeric", TimeRegion.lcNumeric) : "(same as Language)") },
        { type: "action", id: "edit-lcmonetary", name: "Currency: " + (TimeRegion.lcMonetary ? launcher.pickListPreview("lcmonetary", TimeRegion.lcMonetary) : "(same as Language)"), aliases: ["money"] },
        { type: "action", id: "edit-lccollate", name: "Sort Order: " + (TimeRegion.lcCollate ? launcher.localeWithFlag(TimeRegion.lcCollate) : "(same as Language)"), aliases: ["collation", "sorting"] }
    ]
    // Human label for a picklist:<field> mode's breadcrumb (see breadcrumb()
    // below) — kept next to pickListItems since both are keyed by the same
    // field name.
    function pickListLabel(field) {
        if (field === "timezone") return "Timezone"
        if (field === "lang") return "Language"
        if (field === "lcnumeric") return "Number Format"
        if (field === "lcmonetary") return "Currency"
        if (field === "lccollate") return "Sort Order"
        return "Value"
    }
    // Every valid zoneinfo name / generated locale, searchable rather than
    // typed from memory — activate() applies whichever gets picked (id
    // "pick:<value>", the field itself coming from the "picklist:<field>"
    // mode string) via the matching TimeRegion.set* call, which triggers
    // the polkit prompt (hyprpolkitagent) and refreshes the displayed
    // value once it's approved. Every LC_* field but Language itself also
    // gets a leading "clear the override" option.
    //
    // Number/Currency are abstracted all the way down to just the format
    // pattern ("1,234.56", "£1,234.56") — nobody picking "how should
    // numbers look" should have to know or care which locale code happens
    // to produce that, and dozens of locales share the same one anyway
    // (this is real glibc data from TimeRegion.localeInfo, not a guess).
    // pickListItems below dedupes down to the distinct patterns; whichever
    // locale first produced a given pattern is what's silently applied.
    // Language/Sort Order/Timezone have no such context-free preview, so
    // they still show the underlying code.
    function pickListPreview(field, loc) {
        const info = TimeRegion.localeInfo[loc] || {}
        if (field === "lcnumeric") return "1" + (info.thousandsSep || "") + "234" + (info.decimalPoint || ".") + "56"
        if (field === "lcmonetary") return info.currencySymbol ? info.currencySymbol + "1,234.56" : "(no currency symbol)"
        return loc
    }
    function pickListItems(field) {
        if (field === "timezone") return TimeRegion.timezones.map(tz => ({ type: "action", id: "pick:" + tz, name: tz }))
        if (field === "lang" || field === "lccollate")
            return TimeRegion.locales.map(loc => ({ type: "action", id: "pick:" + loc, name: launcher.localeWithFlag(loc) }))

        const seen = {}
        const options = []
        for (const loc of TimeRegion.locales) {
            const preview = launcher.pickListPreview(field, loc)
            if (seen[preview]) continue
            seen[preview] = true
            options.push({ type: "action", id: "pick:" + loc, name: preview })
        }
        return [{ type: "action", id: "pick:", name: "(same as Language)" }].concat(options)
    }

    // Icons are Nerd Font glyphs (Font Awesome set), not .desktop icons —
    // these aren't real installed apps, so there's nothing for
    // Quickshell.iconPath to resolve.
    readonly property var rootItems: [
        { type: "folder", id: "apps", name: "Apps", icon: "" },
        { type: "folder", id: "toggles", name: "Toggles", icon: "" },
        { type: "folder", id: "power", name: "Power", icon: "" },
        { type: "folder", id: "settings", name: "Settings", icon: "" },
        { type: "info", id: "info", name: "Info", icon: "" }
    ]

    // Everything selectable, flattened — search always looks through
    // apps + toggles + power actions + most Settings options at once,
    // regardless of which folder you're browsing. Hidden apps are
    // deliberately left out: they're only reachable through the Hidden
    // folder. Two Settings lists are also left out: autostartItems (each
    // entry there is an app already present in browsableApps, so
    // including it too would just duplicate that app in search results
    // under a different type — "autostart-app" — for no benefit; the
    // per-app minimize-on-launch toggle is only reachable by browsing
    // into Settings > Autostart) and barWidgetItems (its reordering-only
    // rows aren't meaningful outside the drag-to-reorder list itself, and
    // matching one from a global query would give it no way to actually
    // reorder — see isDraggable below, gated on an empty query for the
    // same reason — so it's only reachable by browsing into Settings >
    // Bar Widgets). reloadItems and timeRegionItems have no such
    // drawback and are fully searchable.
    readonly property var allItems: launcher.browsableApps.concat(launcher.steamAppItems).concat(launcher.toggleItems).concat(launcher.powerItems).concat(launcher.reloadItems).concat(launcher.timeRegionItems)

    readonly property var currentItems: {
        // Folders (Games/Hidden/custom) are mixed in with the regular apps
        // here rather than living behind their own root-level menu.
        if (launcher.mode === "apps") return launcher.folderListItems.concat(launcher.appItems).concat([launcher.hiddenFolderItem])
        if (launcher.mode === "toggles") return launcher.toggleItems
        if (launcher.mode === "power") return launcher.powerItems
        if (launcher.mode === "autostart") return launcher.autostartItems
        if (launcher.mode === "reload") return launcher.reloadItems
        if (launcher.mode === "settings") return launcher.settingsItems
        if (launcher.mode === "settings-bar") return launcher.barWidgetItems
        if (launcher.mode === "settings-timeregion") return launcher.timeRegionItems
        if (launcher.mode.indexOf("picklist:") === 0) return launcher.pickListItems(launcher.mode.slice(9))
        if (launcher.mode.indexOf("folder:") === 0) return launcher.folderApps(launcher.mode.slice(7))
        if (launcher.mode === "folderpick") return launcher.folderPickItems
        if (launcher.mode === "newfoldername") return []
        if (launcher.mode === "appmenu") return launcher.appMenuItems
        return launcher.rootItems
    }

    // Lower is better, and applies across every category at once (apps,
    // toggles, power actions, bar widgets) — e.g. the "Stay Awake" toggle
    // legitimately outranks an app it only substring-matches, same as any
    // other prefix hit would. A plain substring test (the old behavior)
    // ranks "Steam" above "Telegram" for query "te" — S-T-E-A-M contains
    // "te" too, and it only won on alphabetical luck (S < T). Humans expect
    // a query to match where a name *starts* first: name-prefix (tier 0),
    // then a word boundary inside the name (space, '-', '_', or a
    // lower→upper camelCase step, e.g. "Cast" in "GoogleCast" — tier 1),
    // then anywhere-substring (tier 2) last.
    //
    // Within a tier, an earlier match *relative to the name's own length*
    // breaks the tie — not raw character index, or "OBS Studio" would
    // always beat "Visual Studio Code" on "st" purely for being the shorter
    // string, even though the match sits proportionally later in it (index
    // 4 of 10 vs. 7 of 18: 0.40 vs 0.39). Encoded as tier + fraction so it
    // never crosses into a neighboring tier. Exact ties (two prefix
    // matches, e.g. "Steam" vs. "Stay Awake" on "st") are meant to fall
    // back to the underlying list's existing order (apps before toggles
    // before bar widgets, alphabetical within apps) — confirmed live that
    // QML's Array.sort does NOT reliably preserve that on a tie (Stay Awake
    // sorted before Steam despite matching rank and a later position in the
    // source list), so `filtered` below tie-breaks on original index
    // explicitly instead of trusting sort stability.
    function matchRank(name, q) {
        const lower = name.toLowerCase()
        if (lower.startsWith(q)) return 0
        for (let i = 1; i < name.length; i++) {
            const boundary = /[\s\-_]/.test(name[i - 1]) || (/[a-z]/.test(name[i - 1]) && /[A-Z]/.test(name[i]))
            if (boundary && lower.startsWith(q, i)) return 1 + i / name.length
        }
        return 2 + lower.indexOf(q) / name.length
    }
    // The same word-boundary rule matchRank uses (space/-/_/camelCase
    // step), but collecting just the boundary character itself instead of
    // ranking a substring match from it — "Reload Quickshell" -> "RQ",
    // "Stay Awake" -> "SA", "Visual Studio Code" -> "VSC". Lets an
    // abbreviation like "rq" or "vsc" find a multi-word item by initials
    // alone, the way a human would type it from memory.
    function initials(name) {
        let out = name.charAt(0)
        for (let i = 1; i < name.length; i++) {
            const boundary = /[\s\-_]/.test(name[i - 1]) || (/[a-z]/.test(name[i - 1]) && /[A-Z]/.test(name[i]))
            if (boundary) out += name[i]
        }
        return out
    }
    // Some items (mostly power/reload actions) are commonly asked for by a
    // different word than their displayed name — "poweroff" for Shutdown,
    // "restart" for Reboot/Reload — so those carry an `aliases` array
    // alongside `name` (see powerItems/reloadItems/toggleItems below).
    // Ranked the same as the name itself via matchRank, and the better
    // (lower) of the two wins, so an alias match never outranks an actual
    // name-prefix hit on a different item. Infinity means "no match at
    // all", filtered out by itemMatchRank's only caller below.
    //
    // Abbreviation hits (see initials() above) are folded in here too,
    // scored as the best possible word-boundary tier (1) — as deliberate a
    // query as landing on a real word boundary, just spelled out from
    // initials instead of a substring. Never beats an actual tier-0 name
    // prefix. Single-character queries are excluded: initials(name)[0] is
    // always name[0], so a 1-char query would just re-derive the tier-0
    // check above in a worse tier, for no benefit.
    function itemMatchRank(item, q) {
        let best = item.name.toLowerCase().includes(q) ? launcher.matchRank(item.name, q) : Infinity
        for (const alias of (item.aliases || [])) {
            if (!alias.toLowerCase().includes(q)) continue
            const rank = launcher.matchRank(alias, q)
            if (rank < best) best = rank
        }
        if (q.length > 1 && best > 1) {
            if (launcher.initials(item.name).toLowerCase().startsWith(q)) best = 1
            else if ((item.aliases || []).some(a => launcher.initials(a).toLowerCase().startsWith(q))) best = 1
        }
        return best
    }
    readonly property var filtered: {
        const q = launcher.query.toLowerCase()
        if (!q) return launcher.currentItems
        // A picklist gets its own scoped, local filter — a plain
        // sub-search of just that list, not the global cross-category one
        // below (which would just find nothing, since none of these are
        // part of allItems).
        if (launcher.mode.indexOf("picklist:") === 0)
            return launcher.currentItems
                .map((item, idx) => ({ item: item, idx: idx }))
                .filter(e => e.item.name.toLowerCase().includes(q))
                .sort((a, b) => launcher.matchRank(a.item.name, q) - launcher.matchRank(b.item.name, q) || a.idx - b.idx)
                .map(e => e.item)
        if (launcher.mode === "appmenu" || launcher.mode === "folderpick" || launcher.mode === "newfoldername") return launcher.currentItems
        return launcher.allItems
            .map((item, idx) => ({ item: item, idx: idx, rank: launcher.itemMatchRank(item, q) }))
            .filter(e => e.rank !== Infinity)
            .sort((a, b) => a.rank - b.rank || a.idx - b.idx)
            .map(e => e.item)
    }

    // Full breadcrumb for a given mode, same idea as pathFor's search-result
    // subtitles — used both for the header title itself and as the prefix
    // when a submenu (appmenu/folderpick/newfoldername) builds its own.
    function breadcrumb(m) {
        if (m === "apps") return "Menu > Apps"
        if (m === "toggles") return "Menu > Toggles"
        if (m === "power") return "Menu > Power"
        if (m === "autostart") return "Menu > Settings > Autostart"
        if (m === "reload") return "Menu > Settings > Reload"
        if (m === "settings") return "Menu > Settings"
        if (m === "settings-bar") return "Menu > Settings > Bar Widgets"
        if (m === "settings-timeregion") return "Menu > Settings > Time & Region"
        if (m.indexOf("picklist:") === 0) return "Menu > Settings > Time & Region > " + launcher.pickListLabel(m.slice(9))
        if (m.indexOf("folder:") === 0) return "Menu > Apps > " + launcher.folderName(m.slice(7))
        return "Menu"
    }

    readonly property string title: launcher.mode === "appmenu" ? launcher.breadcrumb(launcher.returnMode) + " > " + launcher.contextApp.name
        : launcher.mode === "folderpick" ? launcher.breadcrumb(launcher.returnMode) + " > " + launcher.contextApp.name + " > Add to Folder"
        : launcher.mode === "newfoldername" ? launcher.breadcrumb(launcher.returnMode) + " > " + launcher.contextApp.name + " > Add to Folder > New Folder"
        : launcher.mode.indexOf("picklist:") === 0 ? launcher.breadcrumb(launcher.mode)
        : launcher.query.length > 0 ? "Search"
        : launcher.breadcrumb(launcher.mode)

    // Whichever monitor Hyprland currently has focus on, matched back to
    // its Quickshell screen by name (PanelWindow.screen wants the latter,
    // not a HyprlandMonitor) — falls back to the first screen if Hyprland
    // hasn't reported a focused monitor yet.
    function activeScreen() {
        const mon = Hyprland.focusedMonitor
        if (mon) {
            for (const s of Quickshell.screens) {
                if (s.name === mon.name) return s
            }
        }
        return Quickshell.screens[0]
    }
    // SUPER+Q: straight into Apps.
    function openApps() {
        launcher.screen = launcher.activeScreen()
        launcher.mode = "apps"
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.visible = true
    }
    // SUPER+SHIFT+Q: the full root menu (Apps / Toggles / Power folders).
    function openFull() {
        launcher.screen = launcher.activeScreen()
        launcher.mode = "root"
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.visible = true
    }
    function close() {
        launcher.visible = false
    }
    function toggleApps() {
        if (launcher.visible) launcher.close()
        else launcher.openApps()
    }
    function toggleFull() {
        if (launcher.visible) launcher.close()
        else launcher.openFull()
    }
    function goBack() {
        if (launcher.mode === "newfoldername") {
            launcher.mode = "folderpick"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode === "folderpick") {
            launcher.mode = "appmenu"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode === "appmenu") {
            launcher.mode = launcher.returnMode
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode.indexOf("picklist:") === 0) {
            launcher.mode = "settings-timeregion"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode === "settings-bar" || launcher.mode === "settings-timeregion"
                   || launcher.mode === "autostart" || launcher.mode === "reload") {
            launcher.mode = "settings"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode.indexOf("folder:") === 0) {
            launcher.mode = "apps"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode !== "root") {
            launcher.mode = "root"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else {
            launcher.close()
        }
    }

    function launchApp(app) {
        if (app.terminal) Quickshell.execDetached(["kitty", "-e", "sh", "-c", app.exec])
        else Quickshell.execDetached(["sh", "-c", app.exec])
        launcher.close()
    }

    // Enter/Return/click: the item's primary action — launches an app
    // directly, same as before.
    function activate(item) {
        if (!item) return
        if (item.type === "folder") {
            launcher.mode = item.id
            launcher.query = ""
            launcher.selectedIndex = 0
            return
        }
        if (item.type === "app") {
            launcher.launchApp(item)
            return
        }
        if (item.type === "toggle") {
            if (item.id === "idle") ShellState.idleActive = !ShellState.idleActive
            else if (item.id === "wifi") Networking.wifiEnabled = !Networking.wifiEnabled
            else if (item.id === "bluetooth") Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
            else if (item.id === "use24hour") TimeRegion.setUse24Hour(!TimeRegion.use24Hour)
            return
        }
        if (item.type === "autostart-app") {
            AutostartApps.toggle(item.name)
            return
        }
        if (item.type === "bar-widget") {
            BarSettings.toggle(item.id)
            return
        }
        if (item.type === "folder-toggle") {
            AppFolders.toggleApp(item.id, launcher.contextApp.name)
            return
        }
        if (item.type === "keepinroot-toggle") {
            AppFolders.toggleKeepInRoot(launcher.contextApp.name)
            return
        }
        if (item.type === "info") {
            launcher.close()
            // --hold: fastfetch prints once and exits immediately, which
            // would otherwise close the window right away. --class +
            // window_rules.lua's float-center-info rule float/center/size
            // it the same way wlctl's window is (see NetworkIndicator.qml).
            Quickshell.execDetached(["kitty", "--hold", "--class", "sichos-info", "-e", "fastfetch"])
            return
        }
        if (item.type === "power") {
            // hyprshutdown only closes apps and exits Hyprland — it does not
            // touch the system — so reboot/shutdown chain the actual
            // systemctl call via --post-cmd, run once apps are already
            // closed and Hyprland has exited. Same binary as SUPER+M.
            const commands = {
                logout: ["hyprshutdown"],
                suspend: ["systemctl", "suspend"],
                reboot: ["hyprshutdown", "--post-cmd", "systemctl reboot"],
                shutdown: ["hyprshutdown", "--post-cmd", "systemctl poweroff"]
            }
            launcher.close()
            Quickshell.execDetached(commands[item.id])
            return
        }
        if (item.type === "reload") {
            launcher.close()
            const commands = {
                // A plain hyprctl subcommand, not hl.dsp.exec_cmd/dispatch —
                // see window_rules.lua's Firefox PiP rule notes on why
                // dispatcher args need Lua-shaped syntax on this build;
                // `hyprctl reload` itself isn't a dispatcher call at all.
                hyprland: ["hyprctl", "reload"],
                // Same command as keybindings.lua's SUPER+CTRL+SHIFT+R.
                quickshell: ["sh", "-c", "pkill quickshell; quickshell & disown"]
            }
            Quickshell.execDetached(commands[item.id])
            return
        }
        if (item.type === "action") {
            if (item.id.indexOf("pick:") === 0) {
                // Which field this applies to comes from the mode string
                // itself ("picklist:<field>"), not the item — the same
                // list of values (locales) is shared across several
                // fields, so the item alone can't tell them apart.
                const value = item.id.slice(5)
                const field = launcher.mode.slice(9)
                if (field === "timezone") TimeRegion.setTimezone(value)
                else if (field === "lang") TimeRegion.setLang(value)
                else if (field === "lcnumeric") TimeRegion.setLcNumeric(value)
                else if (field === "lcmonetary") TimeRegion.setLcMonetary(value)
                else if (field === "lccollate") TimeRegion.setLcCollate(value)
                launcher.mode = "settings-timeregion"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "launch") {
                launcher.launchApp(launcher.contextApp)
            } else if (item.id === "hide") {
                HiddenApps.hide(launcher.contextApp.name)
                launcher.mode = launcher.returnMode
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "unhide") {
                HiddenApps.unhide(launcher.contextApp.name)
                launcher.mode = launcher.returnMode
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "addfolder") {
                launcher.mode = "folderpick"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "newfolder") {
                launcher.mode = "newfoldername"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "edit-timezone") {
                launcher.mode = "picklist:timezone"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "edit-lang") {
                launcher.mode = "picklist:lang"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "edit-lcnumeric") {
                launcher.mode = "picklist:lcnumeric"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "edit-lcmonetary") {
                launcher.mode = "picklist:lcmonetary"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "edit-lccollate") {
                launcher.mode = "picklist:lccollate"
                launcher.query = ""
                launcher.selectedIndex = 0
            }
        }
    }

    // Right arrow: "enter" the item. Folders/toggles/power actions behave
    // the same as activate(); an app opens its Launch/Hide submenu instead
    // of launching straight away.
    function enter(item) {
        if (!item) return
        if (item.type === "app") {
            launcher.contextApp = item
            launcher.returnMode = launcher.mode
            launcher.mode = "appmenu"
            launcher.query = ""
            launcher.selectedIndex = 0
            return
        }
        launcher.activate(item)
    }

    IpcHandler {
        target: "launcher"
        function toggleApps() { launcher.toggleApps() }
        function toggleFull() { launcher.toggleFull() }
        function openApps() { launcher.openApps() }
        function openFull() { launcher.openFull() }
        function close() { launcher.close() }
    }

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sichos-launcher.active"

    Component.onCompleted: {
        Quickshell.execDetached(["rm", "-f", launcher.stateFile])
    }

    Component.onDestruction: {
        Quickshell.execDetached(["rm", "-f", launcher.stateFile])
    }

    onVisibleChanged: {
        if (launcher.visible) {
            input.forceActiveFocus()
            AppIndex.refresh()
            Quickshell.execDetached(["touch", launcher.stateFile])
        } else {
            Quickshell.execDetached(["rm", "-f", launcher.stateFile])
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: launcher.close()
    }

    Rectangle {
        id: box
        width: 600
        height: 525
        anchors.centerIn: parent
        color: Theme.background
        border.color: Theme.accent
        border.width: 4
        radius: 0

        // Swallows clicks so they don't fall through to the outer
        // click-to-close MouseArea.
        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10

            Row {
                width: parent.width
                height: 25
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // A full breadcrumb (see title/breadcrumb() below) can
                    // run long for a deep path — bounded and elided from
                    // the left so the leaf (what you're actually looking
                    // at) stays visible instead of the "Apps > " prefix.
                    width: 550
                    elide: Text.ElideLeft
                    text: "[ " + launcher.title + " ]"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 0
                color: Qt.rgba(0, 0, 0, 0.4)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                border.width: 1

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "❯"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                }

                TextInput {
                    id: input
                    anchors.left: prompt.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                    text: launcher.query

                    onTextChanged: {
                        launcher.query = text
                        launcher.selectedIndex = 0
                    }
                    // Left/Right double as back/select, but only at the
                    // text cursor's boundary so moving the cursor while
                    // typing a query still works normally.
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_PageDown) {
                            launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 5)
                            list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 5)
                            list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            launcher.enter(launcher.filtered[launcher.selectedIndex])
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backspace && input.text.length === 0) {
                            launcher.goBack()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left && input.cursorPosition === 0) {
                            launcher.goBack()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Right && input.cursorPosition === input.text.length) {
                            launcher.enter(launcher.filtered[launcher.selectedIndex])
                            event.accepted = true
                        }
                    }
                    Keys.onEscapePressed: launcher.goBack()
                    Keys.onDownPressed: {
                        launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 1)
                        list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                    }
                    Keys.onUpPressed: {
                        launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1)
                        list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                    }
                    Keys.onReturnPressed: {
                        if (launcher.mode === "newfoldername") launcher.createFolderFromQuery()
                        else launcher.activate(launcher.filtered[launcher.selectedIndex])
                    }
                    Keys.onEnterPressed: {
                        if (launcher.mode === "newfoldername") launcher.createFolderFromQuery()
                        else launcher.activate(launcher.filtered[launcher.selectedIndex])
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 115
                clip: true
                model: launcher.filtered

                // Row-level MouseAreas below only handle press/hover/click,
                // so an unhandled wheel bubbles up to here instead of
                // falling through to the default Flickable content-drag —
                // scrolling moves the selection, same as the arrow keys.
                WheelHandler {
                    onWheel: (event) => {
                        if (event.angleDelta.y < 0) launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 1)
                        else launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1)
                        list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                    }
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    // "toggle" (idle/wifi/bluetooth) and "autostart-app" both
                    // render as an On/Off pill instead of the ">" submenu arrow.
                    readonly property bool isToggleLike: row.modelData.type === "toggle" || row.modelData.type === "autostart-app" || row.modelData.type === "bar-widget" || row.modelData.type === "folder-toggle" || row.modelData.type === "keepinroot-toggle"
                    // A search query can mix bar-widget rows in among
                    // apps/toggles/power results (search spans everything),
                    // which breaks the index math dragging relies on — only
                    // draggable when the list is the plain, unfiltered folder.
                    readonly property bool isDraggable: row.modelData.type === "bar-widget" && launcher.query.length === 0
                    // Search results get a dim second line (see pathFor)
                    // showing where the result actually lives — every row
                    // that can appear in a search comes from allItems
                    // (app/toggle/power/bar-widget), so this is never blank.
                    readonly property bool showPath: launcher.query.length > 0
                    width: list.width
                    height: 54
                    radius: 0
                    color: row.index === launcher.selectedIndex ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : "transparent"
                    z: dragArea.drag.active ? 10 : 0

                    Rectangle {
                        visible: row.index === launcher.selectedIndex
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: Theme.accent
                    }

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 8
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            text: row.index === launcher.selectedIndex ? "❯" : ""
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                        }

                        Image {
                            readonly property bool hasRealIcon: row.modelData.type === "app" || row.modelData.type === "autostart-app"
                            visible: hasRealIcon
                            anchors.verticalCenter: parent.verticalCenter
                            // Steam games carry a raw cached file path (no
                            // icon-theme name to resolve — see
                            // list-apps.py) instead of the usual icon name.
                            source: hasRealIcon && row.modelData.iconFile ? ("file://" + row.modelData.iconFile)
                                : hasRealIcon && row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            width: 32
                            height: 32
                            sourceSize: Qt.size(32, 32)
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            visible: row.modelData.type !== "app" && row.modelData.type !== "autostart-app" && !!row.modelData.icon
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            horizontalAlignment: Text.AlignHCenter
                            text: row.modelData.icon || ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 20
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: row.modelData.name
                                color: row.modelData.type === "power" && row.modelData.danger ? Theme.critical : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 3
                            }
                            Text {
                                visible: row.showPath
                                text: row.showPath ? launcher.pathFor(row.modelData) : ""
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }

                    Text {
                        visible: !row.isToggleLike && row.modelData.type !== "action"
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: ">"
                        color: row.index === launcher.selectedIndex ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                    }

                    Rectangle {
                        id: onOffPill
                        visible: row.isToggleLike
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: 50
                        height: 22
                        radius: 0
                        color: row.isToggleLike && row.modelData.active ? Theme.success : Qt.rgba(1, 1, 1, 0.1)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: row.isToggleLike && row.modelData.active ? "On" : "Off"
                            color: row.isToggleLike && row.modelData.active ? "#1c1c1c" : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.selectedIndex = row.index
                        onClicked: launcher.activate(row.modelData)
                    }

                    // Declared after the row-wide MouseArea above so it sits
                    // on top of it in input stacking order — otherwise that
                    // MouseArea (being the later sibling) would swallow
                    // clicks/drags meant for this before they ever reached it.
                    // drag.target moves the whole delegate Rectangle itself;
                    // ListView assigns each delegate's y as a plain value
                    // (not a live binding) during layout, so this direct
                    // write doesn't fight anything — it just sticks until
                    // the next layout pass, which is exactly what lets the
                    // row stay wherever it's dropped until the model change
                    // below snaps everything back into its new order.
                    Text {
                        visible: row.isDraggable
                        anchors {
                            right: onOffPill.left
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: "⠿"
                        font.pixelSize: 16
                        color: dragArea.pressed ? Theme.accent : Theme.textMuted

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: row.isDraggable
                            cursorShape: Qt.SizeVerCursor
                            drag.target: row.isDraggable ? row : null
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: (list.count - 1) * row.height

                            onReleased: {
                                const targetIndex = Math.max(0, Math.min(list.count - 1, Math.round(row.y / row.height)))
                                const delta = targetIndex - row.index
                                if (delta > 0) {
                                    for (let s = 0; s < delta; s++) BarSettings.moveDown(row.modelData.id)
                                } else if (delta < 0) {
                                    for (let s = 0; s < -delta; s++) BarSettings.moveUp(row.modelData.id)
                                } else {
                                    row.y = row.index * row.height
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                height: 20
                text: "↑↓ move  ❯ select  esc back"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
