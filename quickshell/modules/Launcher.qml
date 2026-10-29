import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower as UP

// One card, three columns under a large search field: a rail of
// categories (Suggested, Apps, Games, the phone, Controls, Session,
// Settings) on the left, the list in the middle, and a detail pane on the
// right showing the selected item and what can be done with it. The
// category you're in sits as a chip inside the search field and scopes what
// typing searches; Backspace on an empty field steps back out (to
// Suggested, which searches everything, plus a calculator and a web search
// row). The card's top edge is fixed and it grows downward with its
// contents.
PanelWindow {
    id: launcher
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

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
    color: launcher.activeWorkspaceHasWindows ? Theme.backdrop : "transparent"

    property string mode: "root" // "root" | "apps" | "controls" | "session" | "autostart" | "settings" | "settings-bar" | "settings-plugins" | "settings-timeregion" | "picklist:<field>" | "folder:<id>" | "folderpick" | "newfoldername" | "pluginsource" | "pluginaddtype" | "pluginfolderpick"
    property string query: ""
    property int selectedIndex: 0
    // Which list to return to when backing out of Add to Folder.
    property string returnMode: "apps"
    // The app Add to Folder is open for.
    property var contextApp: null

    // Every switch the Control Center has (QuickSettings' tileToggle does
    // the same calls), grouped. `sub` is the dim status line under a row;
    // "choice" rows (the power profile) cycle on Enter and list their
    // values as the detail pane's buttons.
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource
    // Mute state only stays bound while tracked; nothing else tracks the
    // source unless the mic OSD or the Control Center is up.
    PwObjectTracker {
        objects: launcher.visible ? [launcher.audioSink, launcher.audioSource].filter(n => !!n) : []
    }
    function nodeName(n) {
        return n ? (n.description || n.nickname || n.name || "") : ""
    }
    readonly property string wifiName: {
        const dev = NetInfo._wifi
        if (!dev || !dev.connected) return ""
        for (const n of dev.networks.values) if (n.connected) return n.name
        return ""
    }
    readonly property bool airplane: !Networking.wifiEnabled && !(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
    readonly property string powerProfileName: UP.PowerProfiles.profile === UP.PowerProfile.Performance ? "Performance"
        : UP.PowerProfiles.profile === UP.PowerProfile.PowerSaver ? "Power Saver" : "Balanced"
    readonly property var controlItems: {
        const c = "Connectivity", d = "Display", snd = "Sound", f = "Focus", pw = "Power"
        const items = [
            { type: "toggle", id: "wifi", group: c, name: "Wi-Fi", active: Networking.wifiEnabled,
              sub: launcher.wifiName, aliases: ["wifi", "wireless", "network"] }
        ]
        if (Bluetooth.defaultAdapter)
            items.push({ type: "toggle", id: "bluetooth", group: c, name: "Bluetooth", active: Bluetooth.defaultAdapter.enabled, aliases: ["bt"] })
        items.push(
            { type: "toggle", id: "airplane", group: c, name: "Airplane Mode", active: launcher.airplane, aliases: ["flight mode", "radios off"] },
            { type: "toggle", id: "hotspot", group: c, name: "Hotspot", active: Hotspot.active || Hotspot.starting,
              sub: Hotspot.pending === "off" ? "Stopping…" : Hotspot.busy ? "Starting…"
                  : Hotspot.active ? (Hotspot.clients > 0 ? Hotspot.clients + (Hotspot.clients === 1 ? " device" : " devices") : Hotspot.ssid)
                  : Hotspot.armed ? "Again to turn Wi-Fi off" : Hotspot.error,
              aliases: ["tethering", "access point"] },
            { type: "toggle", id: "vpn", group: c, name: "Proton VPN", active: VpnStatus.connected || VpnStatus.connecting,
              sub: VpnStatus.busy ? "Disconnecting…" : VpnStatus.connecting ? "Connecting…" : VpnStatus.connected ? VpnStatus.server : "",
              aliases: ["vpn", "proton"] },
            { type: "toggle", id: "dns", group: c, name: "Private DNS", active: DnsSettings.active,
              sub: DnsSettings.busy ? "Switching…" : DnsSettings.error || DnsSettings.name, aliases: ["dns", "mullvad"] },
            { type: "toggle", id: "nightlight", group: d, name: "Night Light", active: ShellState.sunsetWarm,
              sub: ShellState.sunsetWarm ? ShellState.sunsetKelvin + "K" : "", aliases: ["warm light", "sunset", "blue light"] },
            { type: "toggle", id: "hdr", group: d, name: "HDR", active: HdrSettings.active, aliases: ["high dynamic range"] },
            { type: "toggle", id: "opaque", group: d, name: "Solid Terminal Background", active: ShellState.transparencyOpaque,
              aliases: ["opaque", "transparency"] },
            { type: "toggle", id: "barsolo", group: d, name: "Bar on This Screen Only", active: launcher.screen && ShellState.barSoloScreen === launcher.screen.name,
              aliases: ["hide bar", "single bar", "bar solo"] },
            { type: "toggle", id: "sound", group: snd, name: "Sound", active: !!(launcher.audioSink && launcher.audioSink.audio && !launcher.audioSink.audio.muted),
              sub: launcher.nodeName(launcher.audioSink), aliases: ["mute", "speakers", "audio"] },
            { type: "toggle", id: "micmute", group: snd, name: "Microphone", active: !!(launcher.audioSource && launcher.audioSource.audio && !launcher.audioSource.audio.muted),
              sub: launcher.nodeName(launcher.audioSource), aliases: ["mic", "mute mic"] },
            { type: "toggle", id: "idle", group: f, name: "Stay Awake", active: ShellState.idleActive, aliases: ["caffeine", "idle inhibit", "keep awake"] },
            { type: "toggle", id: "silence", group: f, name: "Do Not Disturb", active: ShellState.notificationsMuted,
              sub: ShellState.notificationsMuted && ShellState.notificationsMutedUntil > 0
                  ? "Until " + Qt.formatTime(new Date(ShellState.notificationsMutedUntil), TimeRegion.use24Hour ? "HH:mm" : "h:mm AP") : "",
              aliases: ["dnd", "silence", "mute notifications"] },
            { type: "toggle", id: "gamefocus", group: f, name: "Game Focus", active: GameFocus.enabled, aliases: ["dim other screens"] },
            { type: "choice", id: "powerprofile", group: pw, name: "Power Profile", sub: launcher.powerProfileName,
              aliases: ["performance", "power saver", "balanced", "battery"] },
            { type: "toggle", id: "lid", group: pw, name: "Sleep When Lid Closes", active: LidSettings.sleep,
              sub: LidSettings.sleep ? "" : "Screen off, keep working", aliases: ["lid"] }
        )
        return items
    }
    Binding {
        target: ShellState
        property: "launcherControlsShown"
        value: launcher.visible && (launcher.mode === "controls" || (launcher.mode === "root" && launcher.query.length > 0))
    }
    // The few Suggested shows; the rest are one Tab away.
    readonly property var suggestedControlIds: ["wifi", "bluetooth", "idle", "silence", "nightlight"]

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
        { type: "folder", id: "settings-plugins", name: "Custom Plugins", icon: "" },
        { type: "folder", id: "settings-timeregion", name: "Date, Time & Language", icon: "" },
        { type: "folder", id: "autostart", name: "Autostart", icon: "" },
        // Lived in the root list before; the root is Suggested now.
        { type: "info", id: "info", name: "System Info", icon: "" }
    ]

    // ~/.config/quickshell/custom/<id>/main.qml entries (CustomWidgets.qml),
    // plus a trailing action row that doubles as status: its label reflects
    // an install/remove in flight or the last one’s error, same idea as
    // "+ New Folder" above but for a background script instead of an
    // instant local edit. See CustomWidgets.qml’s own comment for why no
    // quickshell restart is needed after activating either row below —
    // confirmed live, unlike CustomWidget.qml’s per-widget hot-reload note.
    function _pluginLabel(id) {
        for (const w of CustomWidgets.widgets) {
            if (w.id === id) return w.label
        }
        return id
    }
    // Reflects the user's current order (not CustomWidgets.widgets' own,
    // install-time order) — drag-reordered in the ListView delegate below,
    // same as barWidgetItems.
    readonly property var pluginItems: {
        const items = CustomWidgets.orderedIds().map(id => ({
            type: "plugin", id: id, name: launcher._pluginLabel(id), icon: "",
            active: CustomWidgets.isEnabled(id)
        }))
        items.push({
            type: "action", id: "addplugin",
            name: CustomWidgets.busy ? "Installing…" : (CustomWidgets.lastError ? "⚠ " + CustomWidgets.lastError : "+ Add Plugin")
        })
        return items
    }
    function createPluginFromQuery() {
        const source = launcher.query.trim()
        if (!source || CustomWidgets.busy) return
        CustomWidgets.install(source)
        launcher.mode = "settings-plugins"
        launcher.query = ""
        launcher.selectedIndex = 0
    }
    // "+ Add Plugin" opens this chooser first rather than going straight to
    // the git-URL text prompt — a raw path typed by hand is exactly what
    // the folder picker below exists to avoid.
    readonly property var pluginAddTypeItems: [
        { type: "action", id: "addplugin-git", name: "Git URL" },
        { type: "action", id: "addplugin-folder", name: "Local Folder" }
    ]

    // Primitive (yazi-lite) folder picker for the "Local Folder" choice
    // above: list-dir.py enumerates one directory at a time rather than
    // walking the whole tree, so browsing stays cheap no matter how big
    // $HOME is. pluginDirEntries/pluginDirHasMainQml/pluginDirError are
    // populated by pluginDirProc below each time pluginBrowsePath changes.
    property string pluginBrowsePath: ""
    property var pluginDirEntries: []
    property bool pluginDirHasMainQml: false
    property string pluginDirError: ""
    // Guards an empty pluginBrowsePath (only possible before the picker's
    // ever been opened) from reaching list-dir.py as a blank argv, which
    // Python would resolve to quickshell's own CWD rather than failing
    // loudly. running = false before true (not just true, a no-op/restart
    // depending on build) forces a fresh run even mid-flight — fast
    // Enter-Enter-Enter navigation would otherwise risk pluginDirEntries
    // still reflecting a directory or two back by the time it lands.
    function refreshPluginDir() {
        if (!launcher.pluginBrowsePath) return
        pluginDirProc.running = false
        pluginDirProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/list-dir.py", launcher.pluginBrowsePath]
        pluginDirProc.running = true
    }
    // Shared by the ".." row (activate()) and goBack() (Left-arrow/Escape/
    // Backspace-on-empty all route through it) — Left-arrow in particular
    // fires constantly while browsing, since the query box sits empty most
    // of the time, so it has to mean the same "go up" as clicking ".."
    // rather than bailing out of the picker and losing pluginBrowsePath.
    function pluginDirUp() {
        const base = launcher.pluginBrowsePath.replace(/\/+$/, "") || "/"
        const idx = base.lastIndexOf("/")
        launcher.pluginBrowsePath = idx > 0 ? base.slice(0, idx) : "/"
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.refreshPluginDir()
    }
    function pluginDirDown(name) {
        const base = launcher.pluginBrowsePath.replace(/\/+$/, "") || "/"
        launcher.pluginBrowsePath = (base === "/" ? "" : base) + "/" + name
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.refreshPluginDir()
    }
    Process {
        id: pluginDirProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    launcher.pluginDirEntries = result.entries || []
                    launcher.pluginDirHasMainQml = !!result.selfHasMainQml
                    launcher.pluginDirError = result.error || ""
                } catch (e) {
                    launcher.pluginDirEntries = []
                    launcher.pluginDirHasMainQml = false
                    launcher.pluginDirError = "failed to list directory"
                }
            }
        }
    }
    // "Use This Folder" always leads (reachable the instant you land
    // somewhere worth installing, e.g. $HOME itself, without scrolling
    // past every subdirectory first) and is labelled up front when the
    // current directory has no main.qml — custom-widget.py would reject it
    // outright, so surface that before the user tries rather than after.
    readonly property var pluginFolderItems: {
        const items = [{
            type: "action", id: "selectfolder",
            name: launcher.pluginDirHasMainQml ? "✓ Use This Folder" : "✓ Use This Folder (no main.qml)"
        }]
        if (launcher.pluginBrowsePath !== "/")
            items.push({ type: "plugin-dir", id: "..", name: ".." })
        for (const e of launcher.pluginDirEntries)
            items.push({ type: "plugin-dir", id: e.name, name: e.name + "/" })
        return items
    }

    readonly property var powerItems: [
        { type: "power", id: "lock", name: "Lock", danger: false, aliases: ["lock screen"] },
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
    // The Session category: the power actions, then the reloads (moved out
    // of Settings).
    readonly property var sessionItems: launcher.inGroup(launcher.powerItems, "Session")
        .concat(launcher.inGroup(launcher.reloadItems, "Reload"))

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

    // Folder rows mixed into the Apps listing itself (see currentItems'
    // "apps" branch below) rather than living behind their own menu:
    // whatever custom folders AppFolders holds, plus Hidden (always last).
    // The installed Steam titles (AppIndex/list-apps.py) are the rail's own
    // Games category, folder:games -- left out of the rail entirely when
    // there are none, so a non-Steam machine doesn't get an empty one.
    // The paired phone's apps (PhoneApps, from the sichlink app): a root
    // folder named after the phone, right under Apps, while it's connected
    // -- its own entry rather than inside Apps, since these aren't PC apps
    // and SUPER+SHIFT+Q's flat Apps view stays PC-only. Picking one
    // opens it in the phone mirror (PhoneMirrorState.launchApp).
    readonly property bool phoneAppsAvailable: !!Sichlink.phone && !!Sichlink.phone.connected
    readonly property string phoneName: Sichlink.phone ? Sichlink.phone.name : "Phone"
    readonly property var phoneAppItems: !launcher.phoneAppsAvailable ? [] : PhoneApps.apps
        .map(a => ({ type: "phone-app", name: a.label, package: a.package, iconFile: a.icon || "" }))

    readonly property var folderListItems: {
        const items = []
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
        if (id === "phone") return launcher.phoneName
        const f = AppFolders.folders.find(f => f.id === id)
        return f ? f.name : "Folder"
    }
    function folderApps(id) {
        if (id === "games") return launcher.steamAppItems
        if (id === "hidden") return launcher.hiddenItems
        if (id === "phone") {
            // Still loading, nothing cached yet: one info row instead of
            // an empty folder.
            if (launcher.phoneAppItems.length === 0)
                // "notice": a row that does nothing ("info" is fastfetch).
                return [{ type: "notice", name: PhoneApps.loading ? "Loading the phone's apps…" : "No apps from the phone (is the sichlink app up to date?)" }]
            return launcher.phoneAppItems
        }
        const f = AppFolders.folders.find(f => f.id === id)
        if (!f) return []
        return launcher.browsableApps.filter(a => f.apps.includes(a.name))
    }
    // Breadcrumb shown as a dim second line under a search result, since a
    // flat, cross-category query result loses the folder context browsing
    // normally has. Only ever called on rows from allItems (app/toggle/
    // power/reload/time-region action — bar-widget is deliberately absent
    // from allItems, see its comment there), so every branch here is
    // reachable. "use24hour"/"ntp" are plain toggle types like idle/wifi/
    // bluetooth but live under Settings > Date, Time & Language, not
    // Controls, so they need their own check ahead of the generic toggle case.
    function pathFor(item) {
        if (item.type === "toggle" && (item.id === "use24hour" || item.id === "ntp")) return "Menu > Settings > Date, Time & Language"
        if (item.type === "toggle" || item.type === "choice") return "Menu > Controls"
        if (item.type === "power" || item.type === "reload") return "Menu > Session"
        if (item.type === "action") return "Menu > Settings > Date, Time & Language"
        if (item.steam) return "Menu > Games"
        if (item.type === "phone-app") return "Menu > " + launcher.phoneName
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

    // Date, Time & Language, in the terms other systems use: a time zone
    // by city and country with its UTC offset, a language by name, and a
    // Region -- one pick for every format (date, numbers, currency, units;
    // TimeRegion.setRegion) shown as a sample of each. The locale codes and
    // zoneinfo ids only show in the detail pane. "Locale" isn't one setting
    // underneath -- see TimeRegion.qml's own comment; an older per-category
    // override (LC_COLLATE, say) is kept as it is. 24-Hour Time is a plain
    // toggle, not a locale pick -- see TimeRegion.qml on why "12h vs 24h"
    // isn't a real, independently-selectable locale fact.
    //
    // locale -a lists one locale several times (en_GB, en_GB.iso885915,
    // en_GB.utf8): each is offered once, as its UTF-8 one -- ".utf8", or
    // the bare name where that's all there is (en_IN: glibc defines those
    // as UTF-8 only). They match by language_COUNTRY, so "en_US.UTF-8"
    // (what localectl reports) is "en_US.utf8" (what locale -a lists).
    // language_COUNTRY[@variant], without the encoding: what a locale is,
    // whichever of its spellings a list uses.
    function localeBase(loc) {
        return (loc || "").replace(/\.[^@]*/, "")
    }
    // The installed ones (the format pickers need a sample of each).
    readonly property var pickableLocales: {
        const byBase = {}
        for (const l of TimeRegion.locales) {
            if (/^(C|POSIX)\b/.test(l) || /@euro$/.test(l)) continue
            const utf8 = /\.utf-?8(@|$)/i.test(l)
            if (!utf8 && l.indexOf(".") !== -1) continue
            const b = launcher.localeBase(l)
            if (!byBase[b] || utf8) byBase[b] = l
        }
        return Object.keys(byBase).map(b => byBase[b])
    }
    function localeKey(loc) {
        return launcher.localeBase(loc)
    }
    function localeInfoFor(loc) {
        const b = launcher.localeBase(loc)
        const l = launcher.pickableLocales.find(p => launcher.localeBase(p) === b)
        return TimeRegion.localeInfo[l || loc] || TimeRegion.localeInfo[loc] || {}
    }
    // Every locale there's a language pack for (TimeRegion.catalog), for
    // the Language and Region pickers; until it's loaded, just the
    // installed ones. Names come from it in English ("Ukrainian
    // (Ukraine)"), else from glibc.
    readonly property var catalogByBase: {
        const m = {}
        for (const e of TimeRegion.catalog) m[launcher.localeBase(e.locale)] = e
        return m
    }
    function catalogFor(loc) {
        return launcher.catalogByBase[launcher.localeBase(loc)] || null
    }
    readonly property var allLocales: TimeRegion.catalog.length > 0 ? TimeRegion.catalog.map(e => e.locale) : launcher.pickableLocales
    function isInstalled(loc) {
        const e = launcher.catalogFor(loc)
        return e ? e.installed : launcher.pickableLocales.some(l => launcher.localeBase(l) === launcher.localeBase(loc))
    }
    function languageName(loc) {
        const e = launcher.catalogFor(loc)
        if (e) return e.langName + " (" + [e.variant, e.countryName].filter(t => t).join(", ") + ")"
        const i = launcher.localeInfoFor(loc)
        if (!i.langName) return loc || "Unknown"
        const lang = i.langName.charAt(0).toUpperCase() + i.langName.slice(1)
        return i.countryName ? lang + " (" + i.countryName + ")" : lang
    }
    // The language in itself ("українська"), from Qt's own locale data,
    // which has it whether or not glibc's pack is installed.
    function nativeLanguage(loc) {
        const b = launcher.localeBase(loc).split("@")[0]
        const q = Qt.locale(b)
        return q.name.split("_")[0] === b.split("_")[0] ? q.nativeLanguageName : ""
    }
    function countryOf(loc) {
        const e = launcher.catalogFor(loc)
        return e ? e.countryName : (launcher.localeInfoFor(loc).countryName || "")
    }
    readonly property var regionCountryCounts: {
        const c = {}
        for (const l of launcher.allLocales) { const n = launcher.countryOf(l); c[n] = (c[n] || 0) + 1 }
        return c
    }
    // The country, plus the language where several locales share it
    // (Ukraine: Ukrainian, Russian, Crimean Tatar formats differ).
    function regionName(loc) {
        const country = launcher.countryOf(loc)
        if (!country) return loc || "Unknown"
        if ((launcher.regionCountryCounts[country] || 0) < 2) return country
        const e = launcher.catalogFor(loc)
        const lang = e ? [e.langName, e.variant].filter(t => t).join(", ") : launcher.localeInfoFor(loc).langName
        return lang ? country + " (" + lang + ")" : country
    }
    function regionSample(loc) {
        if (!launcher.isInstalled(loc)) return "Downloads its formats when picked"
        const i = launcher.localeInfoFor(loc)
        return [i.date || "", "1" + (i.thousandsSep || "") + "234" + (i.decimalPoint || ".") + "56", i.currencySymbol || ""]
            .filter(t => t !== "").join("  ·  ")
    }
    readonly property string regionLocale: TimeRegion.region
    // What each format actually follows: its own override, else Language.
    readonly property string dateLocale: TimeRegion.lcTime || TimeRegion.lang
    readonly property string numberLocale: TimeRegion.lcNumeric || TimeRegion.lang
    readonly property string currencyLocale: TimeRegion.lcMonetary || TimeRegion.lang
    readonly property bool formatsMixed: launcher.localeBase(launcher.dateLocale) !== launcher.localeBase(launcher.numberLocale)
        || launcher.localeBase(launcher.dateLocale) !== launcher.localeBase(launcher.currencyLocale)
    function dateSample(loc) { return launcher.localeInfoFor(loc).date || "" }
    function numberSample(loc) {
        const i = launcher.localeInfoFor(loc)
        return "1" + (i.thousandsSep || "") + "234" + (i.decimalPoint || ".") + "56"
    }
    function currencySample(loc) {
        const i = launcher.localeInfoFor(loc)
        return i.currencyCode ? i.currencyCode + (i.currencySymbol && i.currencySymbol !== i.currencyCode ? " (" + i.currencySymbol + ")" : "")
            : i.currencySymbol || ""
    }
    // One picker row per distinct format (dozens of locales write dates
    // the same way), named by the format itself, with the countries that
    // use it under it. Picking a row sets the locale that's current if
    // it's in the group, else the group's first.
    function formatRows(sample, curLoc) {
        const groups = []
        const byKey = {}
        const sorted = launcher.pickableLocales.slice().sort((a, b) => launcher.regionName(a).localeCompare(launcher.regionName(b)))
        for (const l of sorted) {
            const key = sample(l)
            if (!key) continue
            if (!byKey[key]) { byKey[key] = { key: key, locs: [] }; groups.push(byKey[key]) }
            byKey[key].locs.push(l)
        }
        const curBase = launcher.localeBase(curLoc)
        const rows = groups.map(g => {
            const cur = g.locs.find(l => launcher.localeBase(l) === curBase)
            const names = g.locs.map(l => launcher.regionName(l))
            return { type: "action", id: "pick:" + (cur || g.locs[0]), name: g.key, isCurrent: !!cur,
                     sub: names.slice(0, 3).join(", ") + (names.length > 3 ? " and " + (names.length - 3) + " more" : ""),
                     aliases: names }
        })
        return rows.filter(r => r.isCurrent).map(r => Object.assign(r, { group: "Current" }))
            .concat(rows.filter(r => !r.isCurrent).map(r => Object.assign(r, { group: "Formats" })))
    }
    function zoneFor(id) {
        return TimeRegion.zoneInfo.find(z => z.id === id) || null
    }
    // "Kyiv, Ukraine"; an id timezones.py doesn't list (a legacy alias
    // like Europe/Kiev) falls back to its own last part.
    function zoneName(id) {
        const z = launcher.zoneFor(id)
        if (z) return z.id === "UTC" ? "UTC" : z.city + ", " + z.country
        return id ? id.split("/").pop().replace(/_/g, " ") : "Unknown"
    }
    function zoneOffset(z) {
        return z ? "UTC" + (z.offset === "+00:00" ? "" : z.offset) : ""
    }
    // A country's own note ("most of Spain") only where it has several zones.
    readonly property var zoneCountryCounts: {
        const c = {}
        for (const z of TimeRegion.zoneInfo) c[z.country] = (c[z.country] || 0) + 1
        return c
    }
    readonly property var timeRegionItems: {
        const dt = "Date & Time", lr = "Language & Region"
        const tz = launcher.zoneFor(TimeRegion.timezone)
        const now = new Date()
        const items = []
        if (TimeRegion.canNtp)
            items.push({ type: "toggle", id: "ntp", group: dt, name: "Set Time Automatically", active: TimeRegion.ntp,
                         sub: !TimeRegion.ntp ? "" : TimeRegion.ntpSynced ? "In sync with an internet time server" : "Waiting for a time server",
                         aliases: ["ntp", "sync time", "automatic time", "clock"] })
        items.push(
            { type: "action", id: "edit-timezone", group: dt, name: "Time Zone",
              sub: launcher.zoneName(TimeRegion.timezone) + (tz ? "  ·  " + launcher.zoneOffset(tz) : ""), aliases: ["timezone", "tz"] },
            { type: "toggle", id: "use24hour", group: dt, name: "24-Hour Time", active: TimeRegion.use24Hour,
              sub: Qt.formatTime(now, TimeRegion.use24Hour ? "HH:mm" : "h:mm AP"), aliases: ["military time", "clock format", "12-hour"] },
            { type: "action", id: "edit-lang", group: lr, name: "Language",
              sub: TimeRegion.installing ? "Installing " + TimeRegion.installing + "…" : TimeRegion.installError || launcher.languageName(TimeRegion.lang),
              aliases: ["locale"] },
            { type: "action", id: "edit-region", group: lr, name: "Region",
              sub: launcher.regionName(launcher.regionLocale) + (launcher.formatsMixed ? "  ·  Custom formats" : ""),
              aliases: ["formats", "country", "units"] },
            // Each one on its own; picking a Region resets all three to it.
            { type: "action", id: "edit-date", group: lr, name: "Date Format", sub: launcher.dateSample(launcher.dateLocale), aliases: ["date"] },
            { type: "action", id: "edit-number", group: lr, name: "Number Format", sub: launcher.numberSample(launcher.numberLocale),
              aliases: ["decimal", "thousands separator"] },
            { type: "action", id: "edit-currency", group: lr, name: "Currency", sub: launcher.currencySample(launcher.currencyLocale), aliases: ["money"] }
        )
        return items
    }
    // Human label for a picklist:<field> mode's breadcrumb (see breadcrumb()
    // below) — kept next to pickListItems since both are keyed by the same
    // field name.
    function pickListLabel(field) {
        if (field === "timezone") return "Time Zone"
        if (field === "lang") return "Language"
        if (field === "region") return "Region"
        if (field === "date") return "Date Format"
        if (field === "number") return "Number Format"
        if (field === "currency") return "Currency"
        return "Value"
    }
    // Every time zone / installed language / region, searchable rather than
    // typed from memory -- activate() applies whichever gets picked (id
    // "pick:<value>", the field itself coming from the "picklist:<field>"
    // mode string) via the matching TimeRegion.set* call, which triggers
    // the polkit prompt (hyprpolkitagent) and refreshes the displayed
    // value once it's approved. The current choice comes first, under its
    // own heading. A time zone is also found by its zoneinfo id, country,
    // abbreviation ("EET") or offset ("utc+02"), a language by its code.
    function pickListItems(field) {
        const list = (cur, all, rest) => cur.map(i => Object.assign(i, { group: "Current" }))
            .concat(all.map(i => Object.assign(i, { group: rest })))
        if (field === "timezone") {
            if (TimeRegion.zoneInfo.length === 0)
                return TimeRegion.timezones.map(tz => ({ type: "action", id: "pick:" + tz, name: tz }))
            const row = z => ({
                type: "action", id: "pick:" + z.id, name: z.id === "UTC" ? "UTC" : z.city,
                sub: [z.id === "UTC" ? z.country : z.country + (z.note && launcher.zoneCountryCounts[z.country] > 1 ? " (" + z.note + ")" : ""),
                      launcher.zoneOffset(z), z.abbr].filter(t => t).join("  ·  "),
                aliases: [z.id, z.country, z.abbr, "utc" + z.offset, z.note].filter(t => t)
            })
            const zones = TimeRegion.zoneInfo
            return list(zones.filter(z => z.id === TimeRegion.timezone).map(row),
                        zones.filter(z => z.id !== TimeRegion.timezone).map(row), "All Time Zones")
        }
        // A "notice" row while the full list loads (TimeRegion.loadCatalog).
        const loading = TimeRegion.catalogLoading ? [{ type: "notice", name: "Loading every language…", group: "" }] : []
        if (field === "lang") {
            const row = l => {
                const native = launcher.nativeLanguage(l)
                return { type: "action", id: "pick:" + l, name: launcher.languageName(l),
                         sub: [native !== launcher.languageName(l).split(" (")[0] ? native : "",
                               launcher.isInstalled(l) ? "" : "Downloads when picked"].filter(t => t).join("  ·  "),
                         aliases: [l, native].filter(t => t) }
            }
            const isCur = l => launcher.localeKey(l) === launcher.localeKey(TimeRegion.lang)
            const all = launcher.allLocales.slice().sort((a, b) => launcher.languageName(a).localeCompare(launcher.languageName(b)))
            return list(all.filter(isCur).map(row), all.filter(l => !isCur(l)).map(row), "Languages").concat(loading)
        }
        if (field === "region") {
            const row = l => ({ type: "action", id: "pick:" + l, name: launcher.regionName(l), sub: launcher.regionSample(l),
                                aliases: [l, launcher.countryOf(l)] })
            const isCur = l => !!TimeRegion.lcMeasurement && launcher.localeKey(l) === launcher.localeKey(TimeRegion.lcMeasurement)
            const all = launcher.allLocales.slice().sort((a, b) => launcher.regionName(a).localeCompare(launcher.regionName(b)))
            const match = { type: "action", id: "pick:", name: "Same as Language", sub: launcher.regionSample(TimeRegion.lang) }
            return list(TimeRegion.lcMeasurement ? all.filter(isCur).map(row) : [match],
                        (TimeRegion.lcMeasurement ? [match] : []).concat(all.filter(l => !isCur(l)).map(row)), "Regions").concat(loading)
        }
        if (field === "date") return launcher.formatRows(launcher.dateSample, launcher.dateLocale)
        if (field === "number") return launcher.formatRows(launcher.numberSample, launcher.numberLocale)
        if (field === "currency") return launcher.formatRows(launcher.currencySample, launcher.currencyLocale)
        return []
    }

    // Recently launched apps, newest first (names; whatever no longer
    // resolves to a visible app is just skipped).
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/launcher-recent.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: recentStore
            property var recent: []
        }
    }
    readonly property var recentItems: {
        const all = launcher.browsableApps.concat(launcher.steamAppItems)
        return recentStore.recent.map(n => all.find(a => a.name === n)).filter(a => !!a).slice(0, 5)
    }
    function inGroup(items, group) {
        return items.map(i => Object.assign({}, i, { group: group }))
    }
    // The root ("Suggested"): recent apps, a few controls, then the app
    // folders and every app (folders first, as in the Apps category).
    // `group` puts a section heading over each run (see the row delegate).
    // The other categories live in the rail, not as folder rows here.
    readonly property var rootItems: launcher.inGroup(launcher.recentItems, "Recent")
        .concat(launcher.inGroup(launcher.controlItems.filter(i => launcher.suggestedControlIds.includes(i.id)), "Controls"))
        .concat(launcher.inGroup(launcher.folderListItems.concat(launcher.appItems), "Apps"))

    // The left rail. Each entry is a top-level mode; railFor() maps any
    // deeper mode back to the entry it belongs under.
    readonly property var railItems: [
        { id: "root", name: "Suggested", icon: "", count: 0 },
        { header: "Browse" },
        { id: "apps", name: "Apps", icon: "", count: launcher.browsableApps.length }
    ].concat(launcher.steamAppItems.length > 0
        ? [{ id: "folder:games", name: "Games", icon: "\uf11b", count: launcher.steamAppItems.length }]
        : []).concat(launcher.phoneAppsAvailable
        ? [{ id: "folder:phone", name: launcher.phoneName, icon: "\u{f011c}", count: launcher.phoneAppItems.length }] // nf-md-cellphone
        : []).concat([
        { header: "System" },
        { id: "controls", name: "Controls", icon: "\uf205", count: launcher.controlItems.length },
        { id: "session", name: "Session", icon: "\uf011", count: launcher.sessionItems.length },
        { id: "settings", name: "Settings", icon: "", count: launcher.settingsItems.length }
    ])
    function railFor(m) {
        if (m === "folderpick" || m === "newfoldername") return launcher.railFor(launcher.returnMode)
        if (m === "root" || m === "folder:phone" || m === "folder:games" || m === "controls" || m === "session") return m
        if (m === "apps" || m.indexOf("folder:") === 0) return "apps"
        return "settings"
    }
    function openRail(id) {
        if (id === "folder:phone") PhoneApps.refresh()
        launcher.mode = id
        launcher.query = ""
        launcher.selectedIndex = 0
    }
    // Tab / Shift+Tab.
    function cycleRail(dir) {
        const ids = launcher.railItems.filter(r => !!r.id).map(r => r.id)
        const i = ids.indexOf(launcher.railFor(launcher.mode))
        launcher.openRail(ids[(i + dir + ids.length) % ids.length])
    }
    // What typing searches inside a category: everything in it, folders
    // included (Apps covers its custom folders too, so the chip never hides
    // an app that's one level down; games are their own category).
    function scopeItems(m) {
        if (m === "apps") return launcher.browsableApps
        if (m.indexOf("folder:") === 0) return launcher.folderApps(m.slice(7))
        if (m === "settings") return launcher.settingsItems.concat(launcher.timeRegionItems)
        return launcher.currentItems
    }

    // Everything selectable, flattened — a search from the root
    // (Suggested) looks through apps + toggles + power actions + most
    // Settings options at once; inside a category it's scopeItems() instead. Hidden apps are
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
    readonly property var allItems: launcher.browsableApps.concat(launcher.steamAppItems).concat(launcher.phoneAppItems).concat(launcher.controlItems).concat(launcher.powerItems).concat(launcher.reloadItems).concat(launcher.timeRegionItems)

    readonly property var currentItems: {
        // Folders (Games/Hidden/custom) are mixed in with the regular apps
        // here rather than living behind their own root-level menu.
        if (launcher.mode === "apps") return launcher.folderListItems.concat(launcher.appItems).concat([launcher.hiddenFolderItem])
        if (launcher.mode === "controls") return launcher.controlItems
        if (launcher.mode === "session") return launcher.sessionItems
        if (launcher.mode === "autostart") return launcher.autostartItems
        if (launcher.mode === "settings") return launcher.settingsItems
        if (launcher.mode === "settings-bar") return launcher.barWidgetItems
        if (launcher.mode === "settings-plugins") return launcher.pluginItems
        if (launcher.mode === "pluginsource") return []
        if (launcher.mode === "pluginaddtype") return launcher.pluginAddTypeItems
        if (launcher.mode === "pluginfolderpick") return launcher.pluginFolderItems
        if (launcher.mode === "settings-timeregion") return launcher.timeRegionItems
        if (launcher.mode.indexOf("picklist:") === 0) return launcher.pickListItems(launcher.mode.slice(9))
        if (launcher.mode.indexOf("folder:") === 0) return launcher.folderApps(launcher.mode.slice(7))
        if (launcher.mode === "folderpick") return launcher.folderPickItems
        if (launcher.mode === "newfoldername") return []
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
    // alongside `name` (see powerItems/reloadItems/controlItems).
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
        // Punctuation-blind fallback, only when nothing above matched — so
        // "stalker" finds "S.T.A.L.K.E.R. 2: Heart of Chornobyl" and "stalker
        // 2" still works despite the colon. Both sides get the same stripping
        // (the typed query may itself contain dots), and it's ranked by the
        // same tiers on the stripped name. An explicit punctuation list
        // rather than [^\w\s], which would also strip Cyrillic letters.
        if (best === Infinity) {
            const sq = launcher.stripPunct(q)
            if (sq) {
                for (const n of [item.name].concat(item.aliases || [])) {
                    const sn = launcher.stripPunct(n)
                    if (!sn.toLowerCase().includes(sq)) continue
                    const rank = launcher.matchRank(sn, sq)
                    if (rank < best) best = rank
                }
            }
        }
        return best
    }
    function stripPunct(s) {
        return s.replace(/[.,:;!?'"`’‘“”()\[\]{}\-_\/\\&+*#@~|™®©]/g, "").replace(/\s+/g, " ").trim()
    }
    readonly property var filtered: {
        const q = launcher.query.toLowerCase()
        if (!q) return launcher.currentItems
        // A picklist gets its own scoped, local filter — a plain
        // sub-search of just that list, not the global cross-category one
        // below (which would just find nothing, since none of these are
        // part of allItems).
        if (launcher.mode.indexOf("picklist:") === 0 || launcher.mode === "folder:phone")
            return launcher.currentItems
                .map((item, idx) => ({ item: item, idx: idx, rank: launcher.itemMatchRank(item, q) }))
                .filter(e => e.rank !== Infinity)
                .sort((a, b) => a.rank - b.rank || a.idx - b.idx)
                .map(e => e.item)
        // Same local-filter idea as picklist above, but "Use This Folder"
        // and ".." stay pinned regardless of the typed substring — they're
        // navigation, not something to search away by typing a directory
        // name.
        if (launcher.mode === "pluginfolderpick")
            return launcher.currentItems.filter(item => item.id === "selectfolder" || item.id === ".." || item.name.toLowerCase().includes(q))
        if (launcher.mode === "pluginaddtype" || launcher.mode === "folderpick" || launcher.mode === "newfoldername" || launcher.mode === "pluginsource") return launcher.currentItems
        if (launcher.mode !== "root")
            return launcher.scopeItems(launcher.mode)
                .map((item, idx) => ({ item: item, idx: idx, rank: launcher.itemMatchRank(item, q) }))
                .filter(e => e.rank !== Infinity)
                .sort((a, b) => a.rank - b.rank || a.idx - b.idx)
                .map(e => e.item)
        // Phone apps always after every PC result, whatever their rank:
        // searching "chrome" gives this PC's Chrome first, the phone's
        // (badged, see the row delegate) further down. A sum on top, a web
        // search always last.
        const value = launcher.calculate(launcher.query)
        const roll = launcher.randomFor(launcher.query)
        const calc = roll ? [roll]
            : value === null ? [] : [{ type: "calc", name: "= " + launcher.formatNumber(value),
                                       expression: launcher.query.trim(), value: launcher.formatNumber(value) }]
        return calc.concat(launcher.allItems
            .map((item, idx) => ({ item: item, idx: idx, rank: launcher.itemMatchRank(item, q),
                                   phone: item.type === "phone-app" ? 1 : 0 }))
            .filter(e => e.rank !== Infinity)
            .sort((a, b) => a.phone - b.phone || a.rank - b.rank || a.idx - b.idx)
            .map(e => e.item))
            .concat([{ type: "websearch", name: "Search the web for “" + launcher.query.trim() + "”", query: launcher.query.trim() }])
    }

    // The calculator row: + - * / % ^, parentheses, decimals (a comma
    // works as the point too), sqrt/sin/cos/tan/ln/log/abs/round and pi/e.
    // A small recursive-descent parser instead of eval(), so nothing typed
    // here ever runs as code. Returns null unless the query is a whole
    // expression with at least one operator or function -- a bare "42"
    // or an app name isn't a sum.
    function calculate(text) {
        const src = text.replace(/\s+/g, "").replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").toLowerCase()
        if (!/^[0-9.+\-*/%^()a-z]+$/.test(src) || !/[+\-*/%^(]/.test(src)) return null
        const fns = { sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, tan: Math.tan, ln: Math.log,
                      log: Math.log10, abs: Math.abs, round: Math.round }
        let i = 0
        function peek() { return src[i] }
        function expr() {
            let v = term()
            while (peek() === "+" || peek() === "-") v = src[i++] === "+" ? v + term() : v - term()
            return v
        }
        function term() {
            let v = power()
            while (peek() === "*" || peek() === "/" || peek() === "%") {
                const op = src[i++], r = power()
                v = op === "*" ? v * r : op === "/" ? v / r : v % r
            }
            return v
        }
        function power() {
            const b = unary()
            return peek() === "^" ? (i++, Math.pow(b, power())) : b
        }
        function unary() {
            if (peek() === "-") { i++; return -unary() }
            if (peek() === "+") { i++; return unary() }
            return atom()
        }
        function atom() {
            if (peek() === "(") {
                i++
                const v = expr()
                if (src[i++] !== ")") throw "paren"
                return v
            }
            const num = /^(\d+\.?\d*|\.\d+)/.exec(src.slice(i))
            if (num) { i += num[0].length; return parseFloat(num[0]) }
            const word = /^[a-z]+/.exec(src.slice(i))
            if (!word) throw "token"
            i += word[0].length
            if (word[0] === "pi") return Math.PI
            if (word[0] === "e") return Math.E
            const fn = fns[word[0]]
            if (!fn || peek() !== "(") throw "name"
            return fn(atom())
        }
        try {
            const v = expr()
            return i === src.length && isFinite(v) ? v : null
        } catch (e) {
            return null
        }
    }
    // "rand 1 30": a random integer from 1 to 30, both included (either
    // order; "rand 30" = 1 to 30). The number is kept for as long as the
    // query stays the same -- `filtered` re-evaluates on every unrelated
    // change too (a control flipping), and the row shouldn't reroll under
    // the cursor. _randStore is mutated in place, so writing it from inside
    // that binding doesn't notify anything; Roll Again bumps randEpoch.
    property int randEpoch: 0
    readonly property var _randStore: ({ key: "", value: 0 })
    function randomFor(text) {
        const m = /^\s*rand(?:om)?\s+(-?\d+)(?:\s+(-?\d+))?\s*$/i.exec(text)
        if (!m) return null
        const a = m[2] === undefined ? 1 : parseInt(m[1]), b = parseInt(m[2] === undefined ? m[1] : m[2])
        const lo = Math.min(a, b), hi = Math.max(a, b)
        const key = lo + ":" + hi + ":" + launcher.randEpoch
        if (launcher._randStore.key !== key) {
            launcher._randStore.key = key
            launcher._randStore.value = lo + Math.floor(Math.random() * (hi - lo + 1))
        }
        const v = String(launcher._randStore.value)
        return { type: "calc", random: true, name: "= " + v, value: v, expression: "Random integer, " + lo + " to " + hi }
    }
    // Up to 10 significant digits, without float noise (0.1+0.2 = 0.3).
    function formatNumber(v) {
        return String(parseFloat(v.toPrecision(10)))
    }

    // Full breadcrumb for a given mode, same idea as pathFor's search-result
    // subtitles — used both for the header title itself and as the prefix
    // when a submenu (folderpick/newfoldername) builds its own.
    function breadcrumb(m) {
        if (m === "apps") return "Menu > Apps"
        if (m === "controls") return "Menu > Controls"
        if (m === "session") return "Menu > Session"
        if (m === "autostart") return "Menu > Settings > Autostart"
        if (m === "settings") return "Menu > Settings"
        if (m === "settings-bar") return "Menu > Settings > Bar Widgets"
        if (m === "settings-plugins") return "Menu > Settings > Custom Plugins"
        if (m === "settings-timeregion") return "Menu > Settings > Date, Time & Language"
        if (m.indexOf("picklist:") === 0) return "Menu > Settings > Date, Time & Language > " + launcher.pickListLabel(m.slice(9))
        if (m === "folder:phone") return "Menu > " + launcher.phoneName
        if (m === "folder:games") return "Menu > Games"
        if (m.indexOf("folder:") === 0) return "Menu > Apps > " + launcher.folderName(m.slice(7))
        return "Menu"
    }

    readonly property string title: launcher.mode === "folderpick" ? launcher.breadcrumb(launcher.returnMode) + " > " + launcher.contextApp.name + " > Add to Folder"
        : launcher.mode === "newfoldername" ? launcher.breadcrumb(launcher.returnMode) + " > " + launcher.contextApp.name + " > Add to Folder > New Folder"
        : launcher.mode === "pluginaddtype" ? launcher.breadcrumb("settings-plugins") + " > Add Plugin"
        : launcher.mode === "pluginsource" ? launcher.breadcrumb("settings-plugins") + " > Add Plugin > Git URL"
        : launcher.mode === "pluginfolderpick" ? launcher.breadcrumb("settings-plugins") + " > Add Plugin > " + launcher.pluginBrowsePath + (launcher.pluginDirError ? " (⚠ " + launcher.pluginDirError + ")" : "")
        : launcher.breadcrumb(launcher.mode)
    // The search field's chip: where you are, without the path to it.
    readonly property string chipText: launcher.title.split(" > ").pop()
    readonly property string placeholder: launcher.mode === "newfoldername" ? "New folder name, then Enter"
        : launcher.mode === "pluginsource" ? "Git URL of the plugin, then Enter"
        : launcher.mode === "root" ? "Search apps, controls and settings, or type a sum"
        : "Search " + launcher.chipText
    // Over the list: the path inside a category, or the result count.
    readonly property string listHeading: launcher.query.length > 0
        ? launcher.filtered.length + (launcher.filtered.length === 1 ? " result" : " results") + (launcher.mode !== "root" ? " in " + launcher.chipText : "")
        : launcher.mode === "root" ? "Suggested" : launcher.title.replace(/^Menu > /, "").split(" > ").join("  ›  ")
    onModeChanged: if (launcher.mode === "settings-timeregion" || launcher.mode.indexOf("picklist:") === 0) TimeRegion.loadCatalog()
    onFilteredChanged: if (launcher.selectedIndex >= launcher.filtered.length) launcher.selectedIndex = Math.max(0, launcher.filtered.length - 1)

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
    // SUPER+SHIFT+Q: straight into Apps.
    function openApps() {
        launcher.screen = launcher.activeScreen()
        launcher.mode = "apps"
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.visible = true
    }
    // SUPER+Q: the root (Suggested), which searches everything.
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
        } else if (launcher.mode === "pluginfolderpick" && launcher.pluginBrowsePath !== "/") {
            // Left-arrow/Backspace-on-empty land here constantly while
            // browsing (see pluginDirUp's own comment) — only leave the
            // picker once there's nowhere further up to go.
            launcher.pluginDirUp()
        } else if (launcher.mode === "pluginsource" || launcher.mode === "pluginfolderpick") {
            launcher.mode = "pluginaddtype"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode === "pluginaddtype") {
            launcher.mode = "settings-plugins"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode === "folderpick") {
            launcher.mode = launcher.returnMode
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode.indexOf("picklist:") === 0) {
            launcher.mode = "settings-timeregion"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode === "settings-bar" || launcher.mode === "settings-plugins" || launcher.mode === "settings-timeregion"
                   || launcher.mode === "autostart") {
            launcher.mode = "settings"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode.indexOf("folder:") === 0) {
            launcher.mode = launcher.mode === "folder:phone" || launcher.mode === "folder:games" ? "root" : "apps"
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

    function setPowerProfile(p) {
        UP.PowerProfiles.profile = p
    }

    function launchApp(app) {
        recentStore.recent = [app.name].concat(recentStore.recent.filter(n => n !== app.name)).slice(0, 10)
        if (app.terminal) Quickshell.execDetached(["kitty", "-e", "sh", "-c", app.exec])
        else Quickshell.execDetached(["sh", "-c", app.exec])
        launcher.close()
    }

    // Enter/Return/click: the item's primary action — launches an app
    // directly, same as before.
    function activate(item) {
        if (!item) return
        if (item.type === "phone-app") {
            PhoneMirrorState.launchApp(item.package, launcher.screen.name)
            launcher.close()
            return
        }
        if (item.type === "folder") {
            if (item.id === "folder:phone") PhoneApps.refresh()
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
            // Same calls as the Control Center's tiles (QuickSettings'
            // tileToggle), so the state persists the same way.
            const a = launcher.audioSink, m = launcher.audioSource
            switch (item.id) {
            case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break
            case "bluetooth": ShellState.setBluetooth(!Bluetooth.defaultAdapter.enabled); break
            case "airplane": ShellState.setAirplane(!launcher.airplane); break
            case "hotspot": Hotspot.toggle(); break
            case "vpn": VpnStatus.toggle(); break
            case "dns": DnsSettings.toggle(); break
            case "nightlight": ShellState.forceSunsetWarm(!ShellState.sunsetWarm); break
            case "hdr": HdrSettings.toggleActive(); break
            case "opaque": ShellState.setTransparencyOpaque(!ShellState.transparencyOpaque); break
            case "barsolo": ShellState.toggleBarSolo(launcher.screen.name); break
            case "sound": if (a && a.audio) a.audio.muted = !a.audio.muted; break
            case "micmute": if (m && m.audio) m.audio.muted = !m.audio.muted; break
            case "idle": ShellState.setIdleActive(!ShellState.idleActive, 0); break
            case "silence": ShellState.setNotificationsMuted(!ShellState.notificationsMuted, 0); break
            case "gamefocus": GameFocus.enabled = !GameFocus.enabled; break
            case "lid": LidSettings.setSleep(!LidSettings.sleep); break
            case "use24hour": TimeRegion.setUse24Hour(!TimeRegion.use24Hour); break
            case "ntp": TimeRegion.setNtp(!TimeRegion.ntp); break
            }
            return
        }
        // Enter cycles the power profile; the detail pane picks one directly.
        if (item.type === "choice") {
            const p = UP.PowerProfiles.profile
            launcher.setPowerProfile(p === UP.PowerProfile.PowerSaver ? UP.PowerProfile.Balanced
                : p === UP.PowerProfile.Balanced ? UP.PowerProfile.Performance : UP.PowerProfile.PowerSaver)
            return
        }
        if (item.type === "calc") {
            Quickshell.execDetached(["wl-copy", item.value])
            launcher.close()
            return
        }
        if (item.type === "websearch") {
            Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(item.query)])
            launcher.close()
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
        if (item.type === "plugin") {
            CustomWidgets.toggle(item.id)
            return
        }
        // Folder picker row (Settings > Custom Plugins > Add Plugin > Local
        // Folder): click/Enter navigates straight in, same as a "folder"
        // row above — no separate submenu needed since there's nothing
        // else to do with a directory here besides enter it or (via
        // "selectfolder", a plain action row, not this type) install it.
        if (item.type === "plugin-dir") {
            if (item.id === "..") launcher.pluginDirUp()
            else launcher.pluginDirDown(item.id)
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
            // PowerMenu.qml owns logout/reboot/shutdown (closes every
            // window gracefully, lists what's left, then runs the real
            // command), so both menus behave the same; see its header.
            launcher.close()
            Quickshell.execDetached(["quickshell", "ipc", "call", "power", "run", item.id])
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
                const apply = () => {
                    if (field === "timezone") TimeRegion.setTimezone(value)
                    else if (field === "lang") TimeRegion.setLang(value)
                    else if (field === "region") TimeRegion.setRegion(value)
                    else if (field === "date") TimeRegion.setLcTime(value)
                    else if (field === "number") TimeRegion.setLcNumeric(value)
                    else if (field === "currency") TimeRegion.setLcMonetary(value)
                }
                // Not installed: its language pack first (one password
                // prompt), then the pick. The row shows the progress.
                const entry = field === "lang" || field === "region" ? launcher.catalogFor(value) : null
                if (entry && !entry.installed) {
                    if (TimeRegion.installing) return
                    TimeRegion.install(entry, apply)
                } else {
                    apply()
                }
                launcher.mode = "settings-timeregion"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "newfolder") {
                launcher.mode = "newfoldername"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "addplugin") {
                if (CustomWidgets.busy) return
                launcher.mode = "pluginaddtype"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "addplugin-git") {
                launcher.mode = "pluginsource"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "addplugin-folder") {
                launcher.pluginBrowsePath = Quickshell.env("HOME")
                launcher.mode = "pluginfolderpick"
                launcher.query = ""
                launcher.selectedIndex = 0
                launcher.refreshPluginDir()
            } else if (item.id === "selectfolder") {
                if (CustomWidgets.busy) return
                CustomWidgets.install(launcher.pluginBrowsePath)
                launcher.mode = "settings-plugins"
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id.indexOf("edit-") === 0) {
                // edit-timezone / edit-lang / edit-region
                launcher.mode = "picklist:" + item.id.slice(5)
                launcher.query = ""
                launcher.selectedIndex = 0
            }
        }
    }

    // Keeps a row of context around the selection: the rows either side of
    // it stay in view, so it sits second from the edge while moving, except
    // at the very first or last item. Called from key/wheel moves only, not
    // hover -- scrolling under the pointer would re-target the hover.
    property point lastPointer: Qt.point(-1, -1)
    function revealSelected() {
        const n = list.count
        if (n === 0) return
        const s = launcher.selectedIndex
        list.positionViewAtIndex(Math.max(0, s - 1), ListView.Contain)
        list.positionViewAtIndex(Math.min(n - 1, s + 1), ListView.Contain)
        list.positionViewAtIndex(s, ListView.Contain)
    }

    // The detail pane is open on every open (reset on close); Ctrl+I or
    // the header's info button put it away and bring it back.
    property bool detailOpen: true
    // ← moves the keyboard to the rail: ↑/↓ then step through the
    // categories (each opens as you land on it, like Tab), → / Enter / Esc
    // or typing go back to the list. The text field keeps the real focus
    // throughout; this only redirects the arrows.
    property bool railFocus: false
    function stepRail(dir) {
        const ids = launcher.railItems.filter(r => !!r.id).map(r => r.id)
        const i = ids.indexOf(launcher.railFor(launcher.mode))
        const next = Math.max(0, Math.min(ids.length - 1, i + dir))
        if (next !== i) launcher.openRail(ids[next])
    }
    // The detail pane shows the selected row -- or, inside an app's or a
    // plugin's own submenu, that app/plugin.
    readonly property bool inContextMenu: launcher.mode === "folderpick"
        || launcher.mode === "newfoldername"
    readonly property var detailItem: launcher.inContextMenu ? launcher.contextApp
        : (launcher.filtered[launcher.selectedIndex] || null)
    function hasRealIcon(item) {
        return !!item && (item.type === "app" || item.type === "autostart-app" || item.type === "phone-app")
            && !!(item.iconFile || item.icon)
    }
    // An app folder's icon: the icons of its first four apps in a 2x2 grid,
    // like a phone's home-screen folder. Empty (glyph instead) for the
    // phone's folder, Settings' sub-folders and a folder of icon-less apps.
    function folderPreview(item) {
        if (!item || item.type !== "folder" || item.id.indexOf("folder:") !== 0 || item.id === "folder:phone") return []
        return launcher.folderApps(item.id.slice(7)).filter(a => launcher.hasRealIcon(a)).slice(0, 4).map(a => launcher.iconSource(a))
    }
    // What a folder row holds, for the detail pane's list.
    function folderContents(item) {
        if (!item || item.type !== "folder") return []
        if (item.id.indexOf("folder:") === 0) return launcher.folderApps(item.id.slice(7))
        return ({ "settings-bar": launcher.barWidgetItems, "settings-plugins": launcher.pluginItems,
                  "settings-timeregion": launcher.timeRegionItems, autostart: launcher.autostartItems })[item.id] || []
    }
    function iconSource(item) {
        if (!launcher.hasRealIcon(item)) return ""
        // Steam games carry a raw cached file path (no icon-theme name to
        // resolve — see list-apps.py); phone apps PNGs the sichlink daemon wrote.
        return item.iconFile ? "file://" + item.iconFile : Quickshell.iconPath(item.icon, true)
    }
    // Nerd Font (Font Awesome) glyph for rows without a real app icon.
    function glyphFor(item) {
        if (!item) return ""
        if (item.icon && !launcher.hasRealIcon(item)) return item.icon
        if (item.type === "toggle")
            return ({ idle: "\uf0f4", wifi: "\uf1eb", bluetooth: "\uf293", barsolo: "\uf108", use24hour: "\uf017", ntp: "\uf021",
                      airplane: "\uf072", hotspot: "\uf09e", vpn: "\uf132", dns: "\uf233", nightlight: "\uf186",
                      hdr: "\uf185", opaque: "\uf120", sound: item.active ? "\uf028" : "\uf026",
                      micmute: item.active ? "\uf130" : "\uf131", silence: "\uf1f6", gamefocus: "\uf11b",
                      lid: "\uf109" })[item.id] || "\uf205"
        if (item.type === "choice") return "\uf0e7"
        if (item.type === "calc") return "\uf1ec"
        if (item.type === "websearch") return "\uf0ac"
        if (item.type === "power")
            return ({ lock: "\uf023", logout: "", suspend: "", reboot: "", shutdown: "" })[item.id] || ""
        if (item.type === "reload") return ""
        if (item.type === "bar-widget") return ""
        if (item.type === "plugin-dir" || item.type === "folder-toggle") return ""
        if (item.type === "keepinroot-toggle") return ""
        if (item.type === "action" && launcher.mode === "picklist:timezone") return "\uf0ac"
        if (item.type === "action" && launcher.mode.indexOf("picklist:") === 0)
            return ({ "picklist:date": "\uf073", "picklist:number": "\uf292", "picklist:currency": "\uf3d1",
                      "picklist:region": "\uf279" })[launcher.mode] || (item.id === "pick:" ? "\uf0c1" : "\uf1ab")
        if (item.type === "action") return item.id === "edit-timezone" ? "\uf0ac" : item.id === "edit-lang" ? "\uf1ab"
            : item.id === "edit-region" ? "\uf279" : item.id === "edit-date" ? "\uf073"
            : item.id === "edit-number" ? "\uf292" : item.id === "edit-currency" ? "\uf3d1" : item.id.indexOf("pick:") === 0 ? "" : ""
        if (item.type === "app" || item.type === "autostart-app") return ""
        return ""
    }
    function typeLabel(item) {
        if (!item) return ""
        if (item.type === "app") return item.steam ? "Steam game" : "Application"
        return ({ "phone-app": "Phone app", folder: "Folder", toggle: "Control", choice: "Control", power: "Session", reload: "Reload",
                  calc: "Calculator", websearch: "Web search",
                  "autostart-app": "Autostart app", "bar-widget": "Bar widget", plugin: "Custom plugin",
                  info: "System information", action: "Setting", "plugin-dir": "Directory",
                  "folder-toggle": "Folder", "keepinroot-toggle": "Option" })[item.type] || ""
    }
    function detailRows(item) {
        if (!item) return []
        if (item.type === "app") {
            const rows = [["Location", launcher.pathFor(item).replace(/^Menu > /, "").split(" > ").join(" › ")], ["Command", item.exec]]
            if (item.terminal) rows.push(["Runs in", "Terminal"])
            return rows
        }
        if (item.type === "phone-app") return [["Package", item.package]]
        if (item.type === "folder" && item.id.indexOf("folder:") === 0) return [["Items", String(launcher.folderApps(item.id.slice(7)).length)]]
        if (item.type === "toggle" && item.sub) return [["State", item.active ? "On" : "Off"], ["Status", item.sub]]
        if (item.type === "toggle" || item.type === "autostart-app" || item.type === "bar-widget" || item.type === "plugin")
            return [["State", item.active ? "On" : "Off"]]
        if (item.type === "choice") return [["Current", item.sub]]
        if (item.type === "action" && item.id.indexOf("pick:") === 0 && launcher.mode === "picklist:timezone")
            return [["Time zone", item.id.slice(5)]].concat(item.sub ? [["Offset", item.sub.split("  ·  ").slice(1).join(" · ")]] : [])
        if (item.type === "action" && item.id.indexOf("pick:") === 0
            && (launcher.mode === "picklist:date" || launcher.mode === "picklist:number" || launcher.mode === "picklist:currency"))
            return [["Used in", (item.aliases || []).join(", ")], ["Takes effect", "The next time you log in"]]
        if (item.type === "action" && item.id.indexOf("pick:") === 0 && launcher.mode.indexOf("picklist:") === 0)
            return (item.id !== "pick:" ? [["Locale", item.id.slice(5)]] : []).concat(item.sub ? [["Formats", item.sub.split("  ·  ").join(" · ")]] : [])
                .concat([["Takes effect", "The next time you log in"]])
        if (item.id === "edit-timezone") return [["Current", item.sub.split("  ·  ").join(" · ")], ["Time zone", TimeRegion.timezone]]
        if (item.id === "edit-lang") return [["Current", item.sub], ["Locale", TimeRegion.lang], ["Takes effect", "The next time you log in"]]
        if (item.id === "edit-region") return [["Current", launcher.regionName(launcher.regionLocale)],
                                              ["Date", launcher.dateSample(launcher.dateLocale)], ["Numbers", launcher.numberSample(launcher.numberLocale)],
                                              ["Currency", launcher.currencySample(launcher.currencyLocale)], ["Takes effect", "The next time you log in"]]
        if (item.id === "edit-date" || item.id === "edit-number" || item.id === "edit-currency")
            return [["Current", item.sub], ["Takes effect", "The next time you log in"]]
        if (item.type === "calc") return [[item.random ? "Range" : "Expression", item.random ? item.expression.replace(/^Random integer, /, "") : item.expression], ["Result", item.value]]
        return []
    }
    // The pane's buttons. `key` is the shortcut shown beside one; inside a
    // context submenu Enter acts on the list instead, so none are shown.
    function actionsFor(item) {
        if (!item) return []
        const t = item.type
        let acts
        if (t === "app") acts = [
            { id: "launch", label: item.steam ? "Play" : "Launch", key: "↵" },
            HiddenApps.isHidden(item.name) ? { id: "unhide", label: "Unhide", key: "Ctrl H" } : { id: "hide", label: "Hide", key: "Ctrl H" },
            { id: "addfolder", label: "Add to Folder", key: "Ctrl F" }
        ].concat(item.steam ? [{ id: "gamefocus", label: GameFocus.enabled ? "Game Focus: On" : "Game Focus: Off", key: "" }] : [])
        else if (t === "choice") {
            // Enter cycles; each button sets one. Performance only where
            // power-profiles-daemon offers it.
            const opts = [{ id: "profile-saver", label: "Power Saver", p: UP.PowerProfile.PowerSaver },
                          { id: "profile-balanced", label: "Balanced", p: UP.PowerProfile.Balanced }]
            if (UP.PowerProfiles.hasPerformanceProfile) opts.push({ id: "profile-performance", label: "Performance", p: UP.PowerProfile.Performance })
            acts = [{ id: "activate", label: "Next Profile", key: "↵" }]
                .concat(opts.map(o => ({ id: o.id, label: (UP.PowerProfiles.profile === o.p ? "✓  " : "") + o.label, key: "" })))
        }
        else if (t === "calc") acts = [{ id: "activate", label: "Copy Result", key: "↵" }]
            .concat(item.random ? [{ id: "reroll", label: "Roll Again", key: "" }] : [])
        else if (t === "websearch") acts = [{ id: "activate", label: "Search", key: "↵" }]
        else if (t === "phone-app") acts = [{ id: "activate", label: "Open in Phone Mirror", key: "↵" }]
        else if (t === "folder" || t === "info" || t === "plugin-dir") acts = [{ id: "activate", label: "Open", key: "↵" }]
        else if (t === "toggle" || t === "keepinroot-toggle") acts = [{ id: "activate", label: item.active ? "Turn Off" : "Turn On", key: "↵" }]
        else if (t === "folder-toggle") acts = [{ id: "activate", label: (item.active ? "Remove from " : "Add to ") + item.name, key: "↵" }]
        else if (t === "autostart-app") acts = [{ id: "activate", label: item.active ? "Don't Start on Login" : "Start on Login", key: "↵" }]
        else if (t === "bar-widget") acts = [{ id: "activate", label: item.active ? "Hide from Bar" : "Show on Bar", key: "↵" }]
        else if (t === "plugin") acts = [
            { id: "activate", label: CustomWidgets.isEnabled(item.id) ? "Disable" : "Enable", key: "↵" },
            { id: "plugin-remove", label: "Remove", key: "", danger: true }
        ]
        else if (t === "power") acts = [{ id: "activate", label: item.name, key: "↵", danger: item.danger }]
        else if (t === "notice") acts = []
        else acts = [{ id: "activate", label: "Select", key: "↵" }]
        if (launcher.inContextMenu) acts = acts.map(a => Object.assign({}, a, { key: "" }))
        return acts
    }
    function runAction(item, id) {
        if (!item) return
        if (id === "activate") launcher.activate(item)
        else if (id === "launch") launcher.launchApp(item)
        else if (id === "hide") HiddenApps.hide(item.name)
        else if (id === "unhide") HiddenApps.unhide(item.name)
        else if (id === "gamefocus") GameFocus.enabled = !GameFocus.enabled
        else if (id === "reroll") launcher.randEpoch++
        else if (id === "profile-saver") launcher.setPowerProfile(UP.PowerProfile.PowerSaver)
        else if (id === "profile-balanced") launcher.setPowerProfile(UP.PowerProfile.Balanced)
        else if (id === "profile-performance") launcher.setPowerProfile(UP.PowerProfile.Performance)
        else if (id === "plugin-remove") {
            CustomWidgets.remove(item.id)
        } else if (id === "addfolder") {
            if (!launcher.inContextMenu) launcher.returnMode = launcher.mode
            launcher.contextApp = item
            launcher.mode = "folderpick"
            launcher.query = ""
            launcher.selectedIndex = 0
        }
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
            // Reset while hidden (its slide is off then, see the pane's
            // Behavior), not on the next open, which played the pane
            // sliding in front of you.
            launcher.detailOpen = true
            launcher.railFocus = false
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: launcher.close()
    }

    // Soft drop shadow under the card (drawn first, so beneath it) -- solid
    // cards only. Under a glass card it shows through as a dark smudge, and
    // on top of the dimmed backdrop it pushes alpha past the glass layer
    // rule's ignore_alpha, so Hyprland blurs a hard-edged ring around the
    // card (observed: odd shadows whenever a window was open behind it).
    RectangularShadow {
        visible: !Theme.glassOn(launcher.screen)
        anchors.fill: box
        radius: box.radius
        offset.y: Theme.surfaceShadowOffset
        blur: Theme.surfaceShadowBlur
        color: Theme.surfaceShadow
        // Follows the card's open animation (SurfaceAppear) instead of
        // sitting at full strength under a card that's still fading in.
        opacity: box.opacity
        scale: box.scale
        transformOrigin: box.transformOrigin
    }

    // A key's label in the footer and beside the detail pane's actions.
    component Keycap: Rectangle {
        id: cap
        property string label: ""
        implicitWidth: capText.implicitWidth + 12
        implicitHeight: 18
        radius: 4
        color: Theme.controlFill
        border.color: Theme.surfaceBorder
        border.width: 1
        Text {
            id: capText
            anchors.centerIn: parent
            text: cap.label
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
    }

    Squircle {
        id: box
        SurfaceAppear { target: box; shown: launcher.visible; origin: Item.Top }
        // A fixed size whatever it lists, in the proportions of the monitor
        // it opened on (the PanelWindow fills that screen), so it reads as
        // a small copy of the screen rather than a box that changes shape.
        width: Math.min(1350, launcher.width - 96)
        height: Math.round(width * launcher.height / Math.max(1, launcher.width))
        anchors.centerIn: parent
        color: Theme.surfaceFor(launcher.screen)
        borderColor: Theme.surfaceBorder
        borderWidth: Theme.surfaceBorderWidth
        radius: Theme.surfaceSquircleRadius

        // Swallows clicks so they don't fall through to the outer
        // click-to-close MouseArea.
        MouseArea { anchors.fill: parent }

        Item {
            id: header
            width: parent.width
            height: 72

            Text {
                id: searchGlyph
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 7
            }

            // Where you are; clicking it steps back out, same as Backspace
            // on an empty field.
            Rectangle {
                id: chip
                visible: launcher.mode !== "root"
                anchors.left: searchGlyph.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: chipRow.implicitWidth + 20
                height: 30
                radius: Theme.controlRadius
                color: chipMouse.containsMouse ? Theme.hoverFill : Theme.selectedFill

                Row {
                    id: chipRow
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 260)
                        elide: Text.ElideLeft
                        text: launcher.chipText
                        color: Theme.text
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize + 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.goBack()
                }
            }

            TextInput {
                id: input
                anchors.left: chip.visible ? chip.right : searchGlyph.right
                anchors.leftMargin: 14
                anchors.right: detailButton.left
                anchors.rightMargin: 14
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize + 9
                text: launcher.query

                Text {
                    visible: input.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: launcher.placeholder
                    color: Theme.textDim
                    font: input.font
                }

                onTextChanged: {
                    launcher.query = text
                    launcher.selectedIndex = 0
                    launcher.railFocus = false
                }
                // ← (at the text cursor's start) goes to the rail, → (at its
                // end) back to the list -- only at the ends, so editing the
                // query still works; otherwise they move the text cursor.
                // Going in and out of folders is Enter and Backspace/Esc.
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_PageDown) {
                        launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 5)
                        launcher.revealSelected()
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageUp) {
                        launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 5)
                        launcher.revealSelected()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Tab) {
                        launcher.cycleRail(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Backtab) {
                        launcher.cycleRail(-1)
                        event.accepted = true
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_I) {
                        launcher.detailOpen = !launcher.detailOpen
                        event.accepted = true
                    } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_H || event.key === Qt.Key_F)) {
                        const item = launcher.detailItem
                        if (item && item.type === "app")
                            launcher.runAction(item, event.key === Qt.Key_F ? "addfolder" : (HiddenApps.isHidden(item.name) ? "unhide" : "hide"))
                        event.accepted = true
                    } else if (event.key === Qt.Key_Backspace && input.text.length === 0) {
                        launcher.goBack()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Left && input.cursorPosition === 0) {
                        launcher.railFocus = true
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right && input.cursorPosition === input.text.length && launcher.railFocus) {
                        launcher.railFocus = false
                        event.accepted = true
                    } else if (launcher.railFocus && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                        launcher.railFocus = false
                        event.accepted = true
                    }
                }
                Keys.onEscapePressed: {
                    if (launcher.railFocus) launcher.railFocus = false
                    else launcher.goBack()
                }
                Keys.onDownPressed: {
                    if (launcher.railFocus) { launcher.stepRail(1); return }
                    launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 1)
                    launcher.revealSelected()
                }
                Keys.onUpPressed: {
                    if (launcher.railFocus) { launcher.stepRail(-1); return }
                    launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1)
                    launcher.revealSelected()
                }
                Keys.onReturnPressed: {
                    if (launcher.mode === "newfoldername") launcher.createFolderFromQuery()
                    else if (launcher.mode === "pluginsource") launcher.createPluginFromQuery()
                    else launcher.activate(launcher.filtered[launcher.selectedIndex])
                }
                Keys.onEnterPressed: {
                    if (launcher.mode === "newfoldername") launcher.createFolderFromQuery()
                    else if (launcher.mode === "pluginsource") launcher.createPluginFromQuery()
                    else launcher.activate(launcher.filtered[launcher.selectedIndex])
                }
            }

            Rectangle {
                id: detailButton
                anchors.right: escCap.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: Theme.controlRadius
                color: launcher.detailOpen ? Theme.selectedFill : detailMouse.containsMouse ? Theme.controlFill : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\uf05a" // info-circle
                    color: launcher.detailOpen || detailMouse.containsMouse ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                }
                MouseArea {
                    id: detailMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.detailOpen = !launcher.detailOpen
                }
            }

            Keycap {
                id: escCap
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                label: "esc"
            }
        }

        Rectangle { y: header.height; width: parent.width; height: 1; color: Theme.separator }

        Item {
            id: body
            y: header.height + 1
            width: parent.width
            height: box.height - header.height - footer.height - 2

            Rectangle {
                id: rail
                width: 220
                height: parent.height
                color: Qt.rgba(0, 0, 0, 0.14)

                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.separator }

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 2

                    Repeater {
                        model: launcher.railItems
                        delegate: Item {
                            id: railEntry
                            required property var modelData
                            readonly property bool current: !!modelData.id && launcher.railFor(launcher.mode) === modelData.id
                            width: parent.width
                            height: modelData.header ? 32 : 42

                            SectionLabel {
                                visible: !!railEntry.modelData.header
                                x: 12
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                bottomPadding: 0
                                text: railEntry.modelData.header || ""
                            }

                            Rectangle {
                                visible: !railEntry.modelData.header
                                anchors.fill: parent
                                radius: Theme.controlRadius
                                color: railEntry.current ? Theme.selectedFill : railMouse.containsMouse ? Theme.controlFill : "transparent"
                                // While the arrows drive the rail: its current entry gets the ring.
                                border.color: Theme.accent
                                border.width: railEntry.current && launcher.railFocus ? 2 : 0

                                Text {
                                    x: 12
                                    width: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: railEntry.modelData.icon || ""
                                    color: railEntry.current ? Theme.text : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 5
                                }
                                Text {
                                    x: 42
                                    width: parent.width - 40 - 40
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: railEntry.modelData.name || ""
                                    color: railEntry.current ? Theme.text : Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize + 2
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: railEntry.modelData.count > 0 ? railEntry.modelData.count : ""
                                    color: Theme.textDim
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                                MouseArea {
                                    id: railMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        launcher.openRail(railEntry.modelData.id)
                                        launcher.railFocus = false
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: listColumn
                x: rail.width
                width: parent.width - rail.width - detail.width
                height: parent.height

                Text {
                    id: listHeading
                    x: 20
                    y: 14
                    width: parent.width - 40
                    height: launcher.listHeading ? 26 : 0
                    visible: launcher.listHeading !== ""
                    // A deep path (plugin folder picker) can run long; keep
                    // the leaf end visible.
                    elide: Text.ElideLeft
                    text: launcher.listHeading
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                ListView {
                    id: list
                    x: 8
                    y: listHeading.y + listHeading.height + (launcher.listHeading ? 2 : -6)
                    width: parent.width - 16
                    height: parent.height - y - 8
                    clip: true
                    model: launcher.filtered
                    boundsBehavior: Flickable.StopAtBounds

                    // Row-level MouseAreas below only handle press/hover/click,
                    // so an unhandled wheel bubbles up to here instead of
                    // falling through to the default Flickable content-drag —
                    // scrolling moves the selection, same as the arrow keys.
                    // One row per wheel notch (120 units): a touchpad sends many
                    // small deltas, and stepping on each one raced through the list.
                    WheelHandler {
                        property real pending: 0
                        onWheel: (event) => {
                            pending += event.angleDelta.y
                            let steps = 0
                            while (pending <= -120) { pending += 120; steps++ }
                            while (pending >= 120) { pending -= 120; steps-- }
                            if (steps === 0) return
                            launcher.selectedIndex = Math.max(0, Math.min(launcher.filtered.length - 1, launcher.selectedIndex + steps))
                            launcher.revealSelected()
                        }
                    }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        // These render a switch instead of nothing/a chevron;
                        // a plugin's Remove is in the detail pane.
                        readonly property bool isToggleLike: row.modelData.type === "toggle" || row.modelData.type === "autostart-app" || row.modelData.type === "bar-widget" || row.modelData.type === "folder-toggle" || row.modelData.type === "keepinroot-toggle" || row.modelData.type === "plugin"
                        // A search query can mix bar-widget/plugin rows in among
                        // apps/toggles/power results (search spans everything),
                        // which breaks the index math dragging relies on — only
                        // draggable when the list is the plain, unfiltered folder.
                        readonly property bool isDraggable: (row.modelData.type === "bar-widget" || row.modelData.type === "plugin") && launcher.query.length === 0
                        // Search results get a dim second line (see pathFor)
                        // showing where the result actually lives.
                        readonly property bool showPath: launcher.query.length > 0 && launcher.mode === "root"
                        readonly property bool selected: row.index === launcher.selectedIndex
                        // Section heading over the first row of each `group`
                        // run (Suggested only; drag-reorder lists never have
                        // one, so their fixed row height still holds).
                        readonly property bool showGroup: launcher.query.length === 0 && !!row.modelData.group
                            && (row.index === 0 || launcher.filtered[row.index - 1].group !== row.modelData.group)
                        readonly property int groupHeight: row.showGroup ? 32 : 0
                        width: list.width
                        height: row.groupHeight + 50
                        z: dragArea.drag.active ? 10 : 0

                        SectionLabel {
                            visible: row.showGroup
                            x: 12
                            y: row.groupHeight - height - 7
                            bottomPadding: 0
                            text: row.modelData.group || ""
                        }

                        Rectangle {
                            id: rowBg
                            y: row.groupHeight
                            width: parent.width
                            height: 50
                            radius: Theme.controlRadius
                            // Dimmer while the arrows drive the rail instead.
                            color: row.selected ? (launcher.railFocus ? Theme.controlFill : Theme.hoverFill) : "transparent"

                            // First, so the switch and drag handle declared
                            // below sit above it and get their own clicks.
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                // Only a pointer that really moved selects: when
                                // the keyboard scrolls the list, Qt re-delivers
                                // hover to whichever row slid under a still
                                // pointer, which yanked the selection there.
                                onPositionChanged: (mouse) => {
                                    const p = mapToItem(null, mouse.x, mouse.y)
                                    if (p.x === launcher.lastPointer.x && p.y === launcher.lastPointer.y) return
                                    launcher.lastPointer = p
                                    launcher.selectedIndex = row.index
                                }
                                onClicked: launcher.activate(row.modelData)
                            }

                            Item {
                                id: iconSlot
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32

                                Image {
                                    anchors.fill: parent
                                    visible: launcher.hasRealIcon(row.modelData)
                                    source: launcher.iconSource(row.modelData)
                                    sourceSize: Qt.size(64, 64)
                                    fillMode: Image.PreserveAspectFit

                                    // Search results: a phone app gets a small phone
                                    // badge on its icon's corner (like a shortcut's
                                    // arrow), so it isn't mistaken for this PC's
                                    // app of the same name.
                                    Rectangle {
                                        visible: row.modelData.type === "phone-app" && launcher.query.length > 0
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.rightMargin: -5
                                        anchors.bottomMargin: -5
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: Theme.surfaceRaised
                                        border.width: 2
                                        border.color: Theme.surface
                                        // HeaderIcon centers the glyph's measured ink;
                                        // a plain Text sat low and to the left.
                                        HeaderIcon {
                                            anchors.centerIn: parent
                                            glyph: "\u{f011c}" // nf-md-cellphone
                                            inkHeight: 10
                                            color: Theme.text
                                        }
                                    }
                                }
                                Rectangle {
                                    id: rowFolder
                                    readonly property var icons: launcher.folderPreview(row.modelData)
                                    // Larger than the 32px slot it's centred on (the
                                    // row has the room): four icons in a 32px tile
                                    // read as specks.
                                    anchors.centerIn: parent
                                    width: 40
                                    height: 40
                                    visible: icons.length > 0
                                    radius: 10
                                    color: Theme.controlFill
                                    border.color: Theme.surfaceBorder
                                    border.width: 1
                                    Grid {
                                        anchors.centerIn: parent
                                        columns: 2
                                        spacing: 2
                                        Repeater {
                                            model: rowFolder.icons
                                            delegate: Image {
                                                required property var modelData
                                                width: 16
                                                height: 16
                                                source: modelData
                                                sourceSize: Qt.size(32, 32)
                                                fillMode: Image.PreserveAspectFit
                                            }
                                        }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !launcher.hasRealIcon(row.modelData) && !rowFolder.visible
                                    text: launcher.glyphFor(row.modelData)
                                    color: row.modelData.danger ? Theme.critical : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 8
                                }
                            }

                            Column {
                                anchors.left: iconSlot.right
                                anchors.leftMargin: 14
                                anchors.right: trailing.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.modelData.name
                                    color: (row.modelData.type === "power" || row.modelData.type === "action") && row.modelData.danger ? Theme.critical : Theme.text
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize + 4
                                }
                                // Under a search result: where it lives (calc and
                                // web rows have no place); otherwise a control's status.
                                Text {
                                    readonly property bool hasPath: row.showPath && row.modelData.type !== "calc" && row.modelData.type !== "websearch"
                                    visible: text !== ""
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: hasPath ? launcher.pathFor(row.modelData).replace(/^Menu > /, "").split(" > ").join(" › ")
                                        : row.modelData.type === "calc" ? row.modelData.expression
                                        : (row.modelData.sub || "")
                                    color: Theme.textDim
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }

                            Row {
                                id: trailing
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                // drag.target moves the whole delegate itself;
                                // ListView assigns each delegate's y as a plain
                                // value (not a live binding) during layout, so
                                // this direct write doesn't fight anything — it
                                // just sticks until the next layout pass, which
                                // is exactly what lets the row stay wherever
                                // it's dropped until the model change below
                                // snaps everything back into its new order.
                                Text {
                                    visible: row.isDraggable
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "⠿"
                                    font.pixelSize: Theme.fontSize + 3
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
                                            const mover = row.modelData.type === "plugin" ? CustomWidgets : BarSettings
                                            const targetIndex = Math.max(0, Math.min(list.count - 1, Math.round(row.y / row.height)))
                                            const delta = targetIndex - row.index
                                            if (delta > 0) {
                                                for (let s = 0; s < delta; s++) mover.moveDown(row.modelData.id)
                                            } else if (delta < 0) {
                                                for (let s = 0; s < -delta; s++) mover.moveUp(row.modelData.id)
                                            } else {
                                                row.y = row.index * row.height
                                            }
                                        }
                                    }
                                }

                                Switch {
                                    visible: row.isToggleLike
                                    checked: !!row.modelData.active
                                    onToggled: launcher.activate(row.modelData)
                                }

                                // Something further in: a folder or a directory.
                                Text {
                                    visible: row.modelData.type === "folder" || row.modelData.type === "plugin-dir"
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ""
                                    color: row.selected ? Theme.text : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: launcher.filtered.length === 0 && launcher.mode !== "newfoldername" && launcher.mode !== "pluginsource"
                    x: 20
                    y: list.y + 12
                    text: launcher.query ? "Nothing matches “" + launcher.query + "”" : "Nothing here yet"
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            Rectangle {
                id: detail
                anchors.right: parent.right
                width: launcher.detailOpen ? 320 : 0
                height: parent.height
                visible: width > 0
                clip: true
                color: Qt.rgba(0, 0, 0, 0.10)
                Behavior on width {
                    enabled: launcher.visible
                    NumberAnimation { duration: Theme.openDuration; easing.type: Easing.OutCubic }
                }

                Rectangle { width: 1; height: parent.height; color: Theme.separator }

                Column {
                    id: detailInfo
                    visible: !!launcher.detailItem
                    x: 26
                    y: 28
                    width: 320 - 52
                    spacing: 6

                    Item {
                        width: 64
                        height: 64
                        Image {
                            anchors.fill: parent
                            visible: launcher.hasRealIcon(launcher.detailItem)
                            source: launcher.iconSource(launcher.detailItem)
                            sourceSize: Qt.size(128, 128)
                            fillMode: Image.PreserveAspectFit
                        }
                        Rectangle {
                            id: detailFolder
                            readonly property var icons: launcher.folderPreview(launcher.detailItem)
                            anchors.fill: parent
                            visible: icons.length > 0
                            radius: 16
                            color: Theme.controlFill
                            border.color: Theme.surfaceBorder
                            border.width: 1
                            Grid {
                                anchors.centerIn: parent
                                columns: 2
                                spacing: 4
                                Repeater {
                                    model: detailFolder.icons
                                    delegate: Image {
                                        required property var modelData
                                        width: 26
                                        height: 26
                                        source: modelData
                                        sourceSize: Qt.size(52, 52)
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: !launcher.hasRealIcon(launcher.detailItem) && !detailFolder.visible
                            radius: 16
                            color: Theme.selectedFill
                            Text {
                                anchors.centerIn: parent
                                text: launcher.glyphFor(launcher.detailItem)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 30
                            }
                        }
                    }
                    Item { width: 1; height: 6 }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: launcher.detailItem ? launcher.detailItem.name : ""
                        color: Theme.text
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize + 6
                        font.bold: true
                    }
                    Text {
                        text: launcher.typeLabel(launcher.detailItem)
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Item { width: 1; height: 8 }
                    Repeater {
                        model: launcher.detailRows(launcher.detailItem)
                        delegate: Row {
                            required property var modelData
                            spacing: 12
                            Text {
                                width: 64
                                text: modelData[0]
                                color: Theme.textDim
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                width: 268 - 64 - 12
                                elide: Text.ElideMiddle
                                text: modelData[1]
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                    }
                }

                // A folder's contents, between its header and the actions;
                // clicking one runs it like the main list would.
                ListView {
                    id: detailList
                    x: 16
                    width: 320 - 32
                    anchors.top: detailInfo.bottom
                    anchors.topMargin: 14
                    anchors.bottom: detailActions.top
                    anchors.bottomMargin: 10
                    visible: count > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: launcher.folderContents(launcher.detailItem)
                    delegate: Rectangle {
                        id: sub
                        required property var modelData
                        width: detailList.width
                        height: 34
                        radius: Theme.controlRadius
                        color: subMouse.containsMouse ? Theme.controlFill : "transparent"

                        Item {
                            id: subIcon
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            Image {
                                anchors.fill: parent
                                visible: launcher.hasRealIcon(sub.modelData)
                                source: launcher.iconSource(sub.modelData)
                                sourceSize: Qt.size(40, 40)
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !launcher.hasRealIcon(sub.modelData)
                                text: launcher.glyphFor(sub.modelData)
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 2
                            }
                        }
                        Text {
                            anchors.left: subIcon.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: sub.modelData.name
                            color: subMouse.containsMouse ? Theme.text : Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        MouseArea {
                            id: subMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcher.activate(sub.modelData)
                        }
                    }
                }

                Column {
                    id: detailActions
                    x: 16
                    width: 320 - 32
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16
                    spacing: 2

                    Repeater {
                        model: launcher.actionsFor(launcher.detailItem)
                        delegate: Rectangle {
                            id: act
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 34
                            radius: Theme.controlRadius
                            color: act.index === 0 ? Theme.selectedFill : actMouse.containsMouse ? Theme.controlFill : "transparent"

                            Text {
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: act.modelData.label
                                color: act.modelData.danger ? Theme.critical : act.index === 0 || actMouse.containsMouse ? Theme.text : Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize + 1
                            }
                            Keycap {
                                visible: act.modelData.key !== ""
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                label: act.modelData.key
                            }
                            MouseArea {
                                id: actMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcher.runAction(launcher.detailItem, act.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        Rectangle { y: body.y + body.height; width: parent.width; height: 1; color: Theme.separator }

        Item {
            id: footer
            y: body.y + body.height + 1
            width: parent.width
            height: 40

            Row {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18
                Repeater {
                    model: launcher.railFocus ? [["↑↓", "Category"], ["→", "Back to List"]] : [["←", "Categories"], ["Ctrl I", "Details"]]
                    delegate: Row {
                        required property var modelData
                        spacing: 6
                        Keycap { label: modelData[0]; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: Theme.textDim
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18
                Repeater {
                    model: [["↵", "Open"], ["Esc", "Back"]]
                    delegate: Row {
                        required property var modelData
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: Theme.textDim
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Keycap { label: modelData[0]; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }
}
