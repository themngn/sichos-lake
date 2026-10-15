pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Details for the Control Center's network card: address, Wi-Fi link
// (band / channel / bitrate / signal), wired speed and live traffic. Nothing
// polls unless `active` is set -- the card binds it to "open", so the shell
// doesn't spawn nmcli/iw every few seconds just to keep hidden text fresh.
QtObject {
    id: root

    property bool active: false
    readonly property int historyLength: 40

    function _deviceOfType(type) {
        for (const d of Networking.devices.values) if (d.type === type) return d
        return null
    }
    readonly property var _wifi: _deviceOfType(DeviceType.Wifi)
    readonly property var _wired: _deviceOfType(DeviceType.Wired)
    readonly property bool _wifiUp: !!_wifi && _wifi.connected
    readonly property bool _wiredUp: !!_wired && _wired.hasLink && _wired.connected

    // Wi-Fi wins when both are up: that's the link the card is about, and a
    // docked laptop with both usually routes through whichever NM prefers
    // anyway -- showing the wireless details is the more useful default.
    readonly property string iface: _wifiUp ? _wifi.name : _wiredUp ? _wired.name : ""
    readonly property bool isWifi: _wifiUp

    property string ipv4: ""
    property string gateway: ""

    property string wifiBand: ""
    property int wifiChannel: 0
    property int wifiRate: 0      // Mb/s, current tx bitrate
    property int wifiDbm: 0       // 0 = unknown

    // Quickshell reports the negotiated speed directly; 0 while there's no link.
    readonly property int wiredSpeed: _wiredUp ? _wired.linkSpeed : 0

    property real rxRate: 0       // bytes/s
    property real txRate: 0
    property var rxHistory: []
    property var txHistory: []

    // Only the states worth a warning get text; Full and Unknown (checks
    // disabled) stay quiet so the card doesn't cry wolf.
    readonly property string connectivity: {
        switch (Networking.connectivity) {
        case NetworkConnectivity.None: return "No internet"
        case NetworkConnectivity.Portal: return "Sign-in needed"
        case NetworkConnectivity.Limited: return "Limited"
        default: return ""
        }
    }

    function rateText(bps) {
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024) return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    function _push(list, v) {
        const out = list.concat([v])
        return out.length > root.historyLength ? out.slice(out.length - root.historyLength) : out
    }

    // Channel from centre frequency -- iw's link output has the frequency
    // but not the channel number, and the formula is fixed per band.
    function _channel(mhz) {
        if (mhz === 2484) return 14
        if (mhz < 3000) return Math.round((mhz - 2407) / 5)
        if (mhz < 5925) return Math.round((mhz - 5000) / 5)
        return Math.round((mhz - 5950) / 5)
    }

    function _parseLink(text) {
        const vals = {}
        for (const l of text.split("\n")) {
            const m = l.match(/^(\w+)=(.*)$/)
            if (m) vals[m[1]] = m[2]
            const f = l.match(/^\s*freq:\s*([\d.]+)/)
            if (f) vals.freq = f[1]
            const s = l.match(/^\s*signal:\s*(-?\d+)/)
            if (s) vals.signal = s[1]
            const t = l.match(/^\s*tx bitrate:\s*([\d.]+)/)
            if (t) vals.txrate = t[1]
        }
        // IP4.ADDRESS carries the prefix ("192.168.31.224/24"); the card wants the bare address.
        root.ipv4 = (vals.ADDR || "").split("/")[0]
        root.gateway = vals.GW || ""

        if (!root.isWifi) {
            root.wifiBand = ""
            root.wifiChannel = 0
            root.wifiRate = 0
            root.wifiDbm = 0
            return
        }
        // iw has the live tx bitrate (it moves with MCS); nmcli's RATE is
        // only the last-scan figure, so it's the fallback when iw is missing.
        const freq = Number(vals.freq || (vals.NMFREQ || "").replace(/\D/g, "")) || 0
        root.wifiBand = freq <= 0 ? "" : freq < 3000 ? "2.4 GHz" : freq < 5925 ? "5 GHz" : "6 GHz"
        root.wifiChannel = freq > 0 ? root._channel(freq) : Number(vals.NMCHAN || 0)
        root.wifiRate = Math.round(Number(vals.txrate || (vals.NMRATE || "").replace(/\D/g, "")) || 0)
        root.wifiDbm = Number(vals.signal || 0)
    }

    // One shell round trip for everything slow-moving. `-g` output has no
    // field names, so each value is tagged KEY= for the parser; the nmcli
    // wifi row is read from cache (--rescan no) and only used if iw fails.
    property Process _link: Process {
        command: ["sh", "-c",
            "i=\"$1\"; nmcli -g IP4.ADDRESS device show \"$i\" | head -n1 | sed 's/^/ADDR=/'; "
            + "nmcli -g IP4.GATEWAY device show \"$i\" | sed 's/^/GW=/'; "
            + "[ \"$2\" = 1 ] || exit 0; "
            + "iw dev \"$i\" link 2>/dev/null || true; "
            + "nmcli -t -f IN-USE,CHAN,FREQ,RATE dev wifi list ifname \"$i\" --rescan no 2>/dev/null "
            + "| awk -F: '$1==\"*\"{print \"NMCHAN=\"$2; print \"NMFREQ=\"$3; print \"NMRATE=\"$4; exit}'",
            "sh", root.iface, root.isWifi ? "1" : "0"]
        stdout: StdioCollector { onStreamFinished: root._parseLink(text) }
    }

    property Timer _linkTimer: Timer {
        interval: 2500
        repeat: true
        running: root.active && root.iface !== ""
        triggeredOnStart: true
        onTriggered: if (!root._link.running) root._link.running = true
    }

    // Byte counters: the previous sample is dropped whenever the interface
    // changes so a Wi-Fi -> Ethernet switch doesn't read as a giant spike.
    property var _last: null

    function _sampleTraffic() {
        root._rx.reload()
        root._tx.reload()
        const rx = Number(root._rx.text().trim())
        const tx = Number(root._tx.text().trim())
        const now = Date.now()
        if (isNaN(rx) || isNaN(tx) || root._rx.text() === "") return
        if (root._last && root._last.iface === root.iface) {
            const dt = (now - root._last.t) / 1000
            if (dt > 0) {
                root.rxRate = Math.max(0, (rx - root._last.rx) / dt)
                root.txRate = Math.max(0, (tx - root._last.tx) / dt)
            }
            root.rxHistory = root._push(root.rxHistory, root.rxRate)
            root.txHistory = root._push(root.txHistory, root.txRate)
        }
        root._last = { iface: root.iface, rx: rx, tx: tx, t: now }
    }

    property Timer _trafficTimer: Timer {
        interval: 1000
        repeat: true
        running: root.active && root.iface !== ""
        triggeredOnStart: true
        onTriggered: root._sampleTraffic()
        // Stale rates would otherwise linger in the card on the next open.
        onRunningChanged: if (!running) { root._last = null; root.rxRate = 0; root.txRate = 0 }
    }

    property FileView _rx: FileView {
        path: root.iface ? "/sys/class/net/" + root.iface + "/statistics/rx_bytes" : ""
        printErrors: false
    }
    property FileView _tx: FileView {
        path: root.iface ? "/sys/class/net/" + root.iface + "/statistics/tx_bytes" : ""
        printErrors: false
    }
}
