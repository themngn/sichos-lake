pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// DNS for the Control Center's DNS tile: the network's own (DHCP) servers,
// or Mullvad's filtering resolver over DNS over TLS. The choice is
// kept in ~/.config/quickshell/dns.json and applied per connection by
// scripts/dns.sh (see its header for why not NetworkManager's global DNS)
// -- so while one is on, `nmcli monitor` re-applies it whenever another
// network connects.
Singleton {
    id: root

    // Mullvad's resolvers (mullvad.net/help/dns-over-https-and-dns-over-tls):
    // Base blocks ads, trackers and malware.
    readonly property var presets: [
        { id: "auto", label: "Default", name: "Default", desc: "The network's own, unfiltered", host: "", v4: "", v6: "" },
        { id: "base", label: "Mullvad Base", name: "Mullvad Base", desc: "Blocks ads, trackers and malware", host: "base.dns.mullvad.net", v4: "194.242.2.4", v6: "2a07:e340::4" }
    ]
    function preset(id) { return root.presets.find(p => p.id === id) || null }

    readonly property string current: root.preset(_adapter.preset) ? _adapter.preset : "auto"
    readonly property bool active: root.current !== "auto"
    readonly property string name: root.preset(root.current).name
    readonly property string desc: root.preset(root.current).desc
    property bool busy: false
    property string error: ""

    // The tap: off, or back to the last Mullvad one.
    function toggle() { root.set(root.active ? "auto" : _adapter.last) }

    function set(id) {
        if (!root.preset(id) || id === root.current) return
        _adapter.preset = id
        if (id !== "auto") _adapter.last = id
        root._apply()
    }

    function _apply() {
        const p = root.preset(root.current)
        const script = Quickshell.env("HOME") + "/.config/quickshell/scripts/dns.sh"
        // A second change while one runs: queued, applied when it exits.
        if (root._proc.running) { root._again = true; return }
        root.error = ""
        root.busy = true
        root._proc.command = p.id === "auto" ? [script, "apply", "off"] : [script, "apply", p.host, p.v4, p.v6]
        root._proc.running = true
    }
    property bool _again: false
    property Process _proc: Process {
        stderr: StdioCollector { id: _err }
        onExited: (code) => {
            root.busy = false
            if (code !== 0) root.error = _err.text.trim().split("\n").pop() || "Couldn't change DNS"
            if (root._again) { root._again = false; root._apply() }
        }
    }

    // Another network connecting gets the resolver too. Debounced: one
    // connect is a burst of lines, and dns.sh's own reapply adds more (it
    // skips connections that already match, so that settles).
    property Process _monitor: Process {
        command: ["nmcli", "monitor"]
        running: root.active && root._loaded
        stdout: SplitParser {
            onRead: (line) => { if (/: connected/.test(line)) root._reapply.restart() }
        }
    }
    property Timer _reapply: Timer { interval: 1500; onTriggered: if (root.active) root._apply() }

    property bool _loaded: false
    property FileView _file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/dns.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        // Networks joined while the shell wasn't running.
        onLoaded: { root._loaded = true; if (root.active) root._apply() }
        onLoadFailed: root._loaded = true
        adapter: JsonAdapter {
            id: _adapter
            property string preset: "auto"
            property string last: "base"
        }
    }
}
