pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Proton VPN for the Control Center's VPN tile and page (VpnPage.qml).
// Actions go through Proton's own CLI, which the Flatpak (com.protonvpn.www,
// 4.18+) ships next to the GUI as `protonvpn` (`flatpak run
// --command=protonvpn`): it shares the app's sign-in, settings.json and
// server cache, and does connect (fastest / country / city / server, Secure
// Core, P2P, Tor), disconnect and `config set`. Every connection is an
// ordinary NetworkManager connection (WireGuard or OpenVPN, named
// "ProtonVPN <server>"), so state is still read from nmcli -- that also
// catches connections made from the app itself. Polled only while the
// Control Center's main page or the VPN page is open, or the launcher's
// Controls (ShellState.launcherControlsShown).
QtObject {
    id: root

    readonly property bool active: ShellState.activePopup === "quicksettings" || ShellState.activePopup === "qs-vpn"
        || ShellState.launcherControlsShown
    property string connection: "" // active Proton connection's name, "" = off
    property bool busy: false
    readonly property bool connected: root.connection !== ""
    // CLI call in flight: "connect" / "disconnect" / "settings", "" = idle,
    // and what's being connected to ("Fastest", "Germany", "DE#12").
    property string pending: ""
    property string pendingLabel: ""
    // The last call's failure, from the CLI's own "Error: ..." line.
    property string error: ""
    // "ProtonVPN JP#12" -> "JP#12"
    readonly property string server: root.connection.replace(/^ProtonVPN\s*/i, "")
    // NetworkManager is still activating the connection, or the app logged
    // "Connecting" moments ago (it checks the server and fetches certificates
    // before any NM connection exists, so nmcli alone misses most of it).
    property bool _nmConnecting: false
    // ...or a CLI connect is still running (it fetches the certificate and
    // picks the server before NM sees anything).
    readonly property bool connecting: !root.connected && (root._nmConnecting || root.pending === "connect")
    property string device: ""   // tunnel interface, e.g. "proton0" / "tun0"
    property string protocol: "" // "WireGuard" / "OpenVPN"
    property real connectedSince: 0 // epoch ms, 0 = off

    // Per-server details from the app's cached server list; looked up once
    // per server change (see _lookup), "" / -1 until then or if not found.
    property string country: ""  // ISO 3166 exit country, e.g. "JP"
    property string city: ""
    property int load: -1        // server load %, as of the app's last refresh
    property bool secureCore: false // routed through a Secure Core entry country
    readonly property string countryFlag: root.country.length === 2
        ? String.fromCodePoint(...[...root.country].map(c => 0x1F1E6 + c.charCodeAt(0) - 65))
        : ""

    // Account-wide app settings, not per-connection state; reflects what the
    // app will apply, so it's meaningful while disconnected too.
    readonly property var _settingsJson: {
        try { return JSON.parse(root._settingsFile.text()) } catch (e) { return ({}) }
    }
    readonly property bool killSwitch: (root._settingsJson.killswitch ?? 0) !== 0
    readonly property bool netShield: (root._settingsJson.features?.netshield ?? 0) !== 0
    readonly property int netShieldLevel: root._settingsJson.features?.netshield ?? 0 // 0 off, 1 malware, 2 + ads/trackers
    readonly property bool portForwarding: !!root._settingsJson.features?.port_forwarding
    readonly property bool vpnAccelerator: root._settingsJson.features?.vpn_accelerator ?? true
    readonly property bool moderateNat: !!root._settingsJson.features?.moderate_nat
    readonly property bool ipv6: !!root._settingsJson.ipv6
    readonly property string protocolSetting: root._settingsJson.protocol ?? ""

    readonly property string _appDir: Quickshell.env("HOME") + "/.var/app/com.protonvpn.www"

    // The server to reconnect to: the last one connected to from anywhere
    // (the app's or the CLI's log), else our own recent list; "" = never
    // connected, and the tap falls back to the fastest server.
    property string _loggedServer: ""
    readonly property string lastServer: root._loggedServer || (root.recent && root.recent.length ? root.recent[0].name : "")
    // Tile tap / header switch: off -> the last server, on -> off.
    function toggle() {
        if (root.connected || root.connecting || root.pending === "connect") root.disconnect()
        else if (root.lastServer) root.connect({ server: root.lastServer })
        else root.connect({ label: "Fastest" })
    }
    // opts: { server, country, city, secureCore, p2p, tor, random, label }.
    // The CLI picks the fastest match by Proton's score, and replaces a
    // current connection itself.
    function connect(opts) {
        const a = ["connect"]
        if (opts.server) a.push(opts.server)
        else if (opts.city) a.push("--city", opts.city)
        else if (opts.country) a.push("--country", opts.country)
        if (opts.secureCore) a.push("--securecore")
        if (opts.p2p) a.push("--p2p")
        if (opts.tor) a.push("--tor")
        if (opts.random) a.push("--random")
        root._run("connect", opts.label || opts.server || opts.city || opts.country || "Fastest", a)
    }
    function disconnect() {
        root.busy = root.connected
        root._run("disconnect", "", ["disconnect"])
    }
    // CLI setting names/values (`protonvpn config set --help`): kill-switch
    // off|standard, netshield off|malware-only|malware-ads-trackers,
    // port-forwarding / vpn-accelerator / moderate-nat / ipv6 on|off.
    function setSetting(name, value) {
        root._run("settings", "", ["config", "set", name, value])
    }
    function openApp() {
        Quickshell.execDetached(["flatpak", "run", "com.protonvpn.www"])
    }

    // Proton's country code -> a flag emoji ("UK" is GB in ISO 3166).
    function flagFor(code) {
        const c = code === "UK" ? "GB" : (code || "")
        return c.length === 2 ? String.fromCodePoint(...[...c].map(ch => 0x1F1E6 + ch.charCodeAt(0) - 65)) : ""
    }

    // One CLI call at a time; a new one stops the running one (Disconnect
    // while a connect is still negotiating). `flatpak run` passes the kill
    // on (--die-with-parent), so the CLI inside goes too.
    property var _queued: null
    function _run(kind, label, args) {
        root.error = ""
        root.pending = kind
        root.pendingLabel = label
        const cmd = ["timeout", "90", "flatpak", "run", "--command=protonvpn", "com.protonvpn.www"].concat(args)
        if (root._cli.running) {
            root._queued = cmd
            root._cli.running = false
        } else {
            root._cli.command = cmd
            root._cli.running = true
        }
        root._poll.restart()
    }
    property Process _cli: Process {
        stdout: StdioCollector { id: cliOut }
        stderr: StdioCollector { id: cliErr }
        onExited: (code) => {
            if (root._queued) {
                root._cli.command = root._queued
                root._queued = null
                root._cli.running = true
                return
            }
            if (code !== 0) {
                // click's "Error: <message>" (usage errors carry a "Usage:"
                // block first); fall back to the last line of anything.
                const all = (cliErr.text + "\n" + cliOut.text).split("\n").map(l => l.trim()).filter(l => l)
                const err = all.find(l => l.startsWith("Error:"))
                root.error = err ? err.replace(/^Error:\s*/, "")
                    : code === 124 ? "Timed out" : (all[all.length - 1] || "Failed (" + code + ")")
            }
            if (root.pending === "settings") root._settingsFile.reload()
            root.pending = ""
            root.pendingLabel = ""
            root.busy = false
            root._poll.restart()
        }
    }

    // Server list (scripts/vpn-servers.py over the app's cache): countries
    // once per page open, a country's servers when it's expanded.
    property var countries: []
    property var servers: ({}) // country code -> [[name, city, load, features], ...]
    property bool loadingCountries: false
    property string _serversFor: ""
    readonly property string _script: Quickshell.env("HOME") + "/.config/quickshell/scripts/vpn-servers.py"
    function loadCountries() {
        if (root._countriesProc.running) return
        root.loadingCountries = true
        root._countriesProc.running = true
    }
    function loadServers(code) {
        if (root.servers[code] || root._serversProc.running) return
        root._serversFor = code
        root._serversProc.command = ["python3", root._script, code]
        root._serversProc.running = true
    }
    property Process _countriesProc: Process {
        command: ["python3", root._script]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.countries = JSON.parse(text).countries || [] } catch (e) { root.countries = [] }
                root.servers = ({}) // loads may have moved; re-read on expand
                root.loadingCountries = false
            }
        }
    }
    property Process _serversProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                let list = []
                try { list = JSON.parse(text).servers || [] } catch (e) {}
                const m = Object.assign({}, root.servers)
                m[root._serversFor] = list
                root.servers = m
            }
        }
    }

    // Recently used servers, newest first, kept across restarts.
    readonly property var recent: recentAdapter.servers
    // Starred countries and servers, in the order they were added:
    // { kind: "country" | "server", id: "DE" | "DE#12", label, country, city }.
    readonly property var favorites: recentAdapter.favorites || []
    function isFavorite(kind, id) {
        return root.favorites.some(f => f.kind === kind && f.id === id)
    }
    function toggleFavorite(entry) {
        const has = root.isFavorite(entry.kind, entry.id)
        recentAdapter.favorites = has ? root.favorites.filter(f => !(f.kind === entry.kind && f.id === entry.id))
            : root.favorites.concat([entry])
        root._recentFile.writeAdapter()
    }
    function connectFavorite(f) {
        if (f.kind === "server") root.connect({ server: f.id })
        else root.connect({ country: f.id, label: f.label })
    }
    // Once the country lookup is in (it runs on the same change).
    property Timer _remember: Timer {
        interval: 1500
        onTriggered: {
            if (root.server === "") return
            const list = (recentAdapter.servers || []).filter(r => r.name !== root.server)
            list.unshift({ name: root.server, country: root.country, city: root.city })
            recentAdapter.servers = list.slice(0, 5)
            root._recentFile.writeAdapter()
        }
    }
    // Recent servers and favorites share one file.
    property FileView _recentFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/vpn-recent.json"
        printErrors: false
        adapter: JsonAdapter {
            id: recentAdapter
            property var servers: []
            property var favorites: []
        }
    }

    // nmcli -t escapes ':' (and '\') inside fields with a backslash, so a
    // plain split(":") would cut a name that contains one.
    function _splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const ch = line[i]
            if (ch === "\\" && i + 1 < line.length) cur += line[++i]
            else if (ch === ":") { out.push(cur); cur = "" }
            else cur += ch
        }
        out.push(cur)
        return out
    }
    // Log timestamps carry microseconds ("...T07:42:43.762952+00:00"), which
    // Date.parse doesn't accept; milliseconds + Z is enough.
    function _logTime(stamp) {
        const t = Date.parse(stamp.slice(0, 23) + "Z")
        return isNaN(t) ? 0 : t
    }

    onConnectionChanged: {
        if (!root.connected) {
            root.connectedSince = 0
            root.device = ""
            root.protocol = ""
        }
        // The app rewrites settings.json atomically (new inode), which a file
        // watch can miss; a connection change is when the app most likely
        // touched it, so re-read then as a fallback.
        root._settingsFile.reload()
    }
    onServerChanged: {
        if (root.server !== "") root._remember.restart()
        root.country = ""
        root.city = ""
        root.load = -1
        root.secureCore = false
        if (root.server === "") return
        root._lookup.running = false
        root._lookup.command = ["jq", "-r", "--arg", "n", root.server,
            "first(.LogicalServers[] | select(.Name == $n))"
            + " | [.ExitCountry, .EntryCountry, .City // \"\", .Load // -1] | @tsv",
            root._appDir + "/cache/Proton/VPN/serverlist.json"]
        root._lookup.running = true
    }

    property Process _proc: Process {
        // The log's last state line rides along so `connecting` and the real
        // connect time come from the same poll, without a second process.
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE,DEVICE,STATE connection show --active; echo ---;"
            + " grep -h 'CONN:STATE_CHANGED' \"$1\" 2>/dev/null | tail -n 1; echo ---;"
            // Last server asked for, by the app or the CLI (both log every
            // attempt; ISO timestamps sort across the two files).
            + " grep -h 'CONN.CONNECT:START' \"$1\" \"$2\" 2>/dev/null | sort | tail -n 1",
            "sh", root._appDir + "/cache/Proton/VPN/logs/vpn-app.log", root._appDir + "/cache/Proton/VPN/logs/vpn-cli.log"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [nmPart, logPart = "", lastPart = ""] = text.split("\n---\n")
                const last = lastPart.match(/\| Server: (\S+)/)
                if (last) root._loggedServer = last[1]
                let found = null
                for (const line of nmPart.split("\n")) {
                    const f = root._splitTerse(line)
                    if (/^proton/i.test(f[0])) { found = f; break }
                }
                const activated = found !== null && found[3] === "activated"

                // "<time> | <module> | INFO | CONN:STATE_CHANGED | Connected"
                const log = logPart.trim().split(" | ")
                const logState = log.length >= 5 ? log[4] : ""
                const logTime = log.length >= 5 ? root._logTime(log[0]) : 0
                // Only a fresh "Connecting" counts: if the app was killed
                // mid-connect the line stays last in the log forever.
                const logConnecting = logState === "Connecting" && Date.now() - logTime < 60000

                const name = activated ? found[0] : ""
                if (name !== root.connection) {
                    // "Connected (initial state)" is the app restarting onto
                    // an existing tunnel, not the moment it came up.
                    root.connectedSince = name === "" ? 0
                        : logState === "Connected" && logTime > 0 ? logTime : Date.now()
                    root.connection = name
                }
                if (activated) {
                    // WireGuard's NM device is the tunnel itself; for OpenVPN
                    // it's the underlying link, so the tun name is taken from
                    // the IP interface instead (see _ipIface).
                    root.protocol = found[1] === "wireguard" ? "WireGuard" : "OpenVPN"
                    if (found[1] === "wireguard") root.device = found[2]
                    else if (root.device === "" && !root._ipIface.running) {
                        root._ipIface.command = ["nmcli", "-g", "GENERAL.IP-IFACE", "connection", "show", "id", name]
                        root._ipIface.running = true
                    }
                }
                root._nmConnecting = !activated && (found?.[3] === "activating" || logConnecting)
                root.busy = false
            }
        }
    }
    property Process _ipIface: Process {
        stdout: StdioCollector {
            onStreamFinished: if (root.connected) root.device = text.trim()
        }
    }
    property Process _lookup: Process {
        // serverlist.json is ~24 MB, far too big to parse in QML; jq pulls the
        // one row out in a fraction of a second.
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.replace(/\n$/, "").split("\t")
                if (f.length < 4 || f[0] === "") return
                // Proton uses "UK"; the flag (and ISO 3166) want "GB".
                root.country = f[0] === "UK" ? "GB" : f[0]
                root.secureCore = f[1] !== "" && f[1] !== f[0]
                root.city = f[2]
                const load = parseInt(f[3])
                root.load = isNaN(load) ? -1 : load
            }
        }
    }
    property FileView _settingsFile: FileView {
        path: root._appDir + "/config/Proton/VPN/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    property Timer _poll: Timer {
        interval: 3000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: if (!root._proc.running) root._proc.running = true
    }
}
