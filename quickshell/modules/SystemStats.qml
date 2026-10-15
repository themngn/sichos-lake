pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / RAM / temperature (plus GPU, fan, swap, network, disk and uptime)
// for the Control Center's System tile. Polls /proc and the hwmon/drm sensors
// only while the Control Center's main page is open (on any screen) -- nothing
// runs the rest of the time. Keeps the last `historyLength` samples for the
// 2-row tile's graphs.
QtObject {
    id: root

    readonly property bool active: ShellState.activePopup === "quicksettings"
    readonly property int historyLength: 40

    property real cpu: 0      // 0..1
    property real ram: 0      // 0..1
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real temp: 0     // degrees C, 0 = no sensor
    property var cpuHistory: []
    property var ramHistory: []

    property real gpu: -1     // 0..1, -1 = no gpu_busy_percent (non-AMD)
    property var gpuHistory: []
    property real gpuTemp: 0  // degrees C, 0 = no sensor
    property real apuWatts: 0 // W, 0 = no sensor
    property int fanRpm: 0    // 0 = no fan sensor (or fan stopped)
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    property real netRx: 0    // bytes/s
    property real netTx: 0
    property var netRxHistory: []
    property var netTxHistory: []
    property real diskUsedGb: 0 // of "/"
    property real diskTotalGb: 0
    property real uptimeSec: 0

    property var _lastCpu: null
    property var _lastNet: null

    // "1.2 MB/s" / "80 KB/s" / "0 B/s" -- one decimal only below 10 so the
    // tile's text doesn't jitter in width every sample.
    function rateText(bps) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"]
        let v = Math.max(0, bps), i = 0
        while (v >= 1000 && i < units.length - 1) { v /= 1024; i++ }
        return (i > 0 && v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[i]
    }

    // Two largest units only: "3d 2h", "4h 10m", "12m".
    function durationText(sec) {
        const m = Math.floor(sec / 60) % 60, h = Math.floor(sec / 3600) % 24, d = Math.floor(sec / 86400)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    function _push(list, v) {
        const out = list.concat([v])
        return out.length > root.historyLength ? out.slice(out.length - root.historyLength) : out
    }

    function _sample() {
        root._stat.reload()
        root._mem.reload()
        if (root._tempPath) root._temp.reload()
        if (root._gpuBusyPath) root._gpuBusy.reload()
        if (root._gpuTempPath) root._gpuTempFile.reload()
        if (root._powerPath) root._power.reload()
        if (root._fanPath) root._fan.reload()
        root._net.reload()
        root._uptime.reload()

        // First line of /proc/stat: cpu user nice system idle iowait irq softirq steal ...
        const line = (root._stat.text().split("\n")[0] || "").trim().split(/\s+/).slice(1).map(Number)
        if (line.length >= 4) {
            const idle = line[3] + (line[4] || 0)
            const total = line.reduce((a, b) => a + b, 0)
            if (root._lastCpu) {
                const dt = total - root._lastCpu.total
                if (dt > 0) root.cpu = Math.max(0, Math.min(1, 1 - (idle - root._lastCpu.idle) / dt))
            }
            root._lastCpu = { idle: idle, total: total }
        }

        const mem = {}
        for (const l of root._mem.text().split("\n")) {
            const m = l.match(/^(\w+):\s+(\d+)/)
            if (m) mem[m[1]] = Number(m[2])
        }
        if (mem.MemTotal) {
            const used = mem.MemTotal - (mem.MemAvailable || mem.MemFree || 0)
            root.ram = used / mem.MemTotal
            root.ramUsedGb = used / 1048576
            root.ramTotalGb = mem.MemTotal / 1048576
        }
        if (mem.SwapTotal !== undefined) {
            root.swapTotalGb = mem.SwapTotal / 1048576
            root.swapUsedGb = (mem.SwapTotal - (mem.SwapFree || 0)) / 1048576
        }

        if (root._tempPath) {
            const t = Number(root._temp.text().trim())
            if (t > 0) root.temp = t / 1000
        }

        if (root._gpuBusyPath) {
            const g = parseInt(root._gpuBusy.text())
            if (!isNaN(g)) root.gpu = Math.max(0, Math.min(1, g / 100))
        }
        if (root._gpuTempPath) {
            const t = Number(root._gpuTempFile.text().trim())
            if (t > 0) root.gpuTemp = t / 1000
        }
        if (root._powerPath) {
            const p = Number(root._power.text().trim())
            if (p > 0) root.apuWatts = p / 1e6
        }
        if (root._fanPath) root.fanRpm = Number(root._fan.text().trim()) || 0

        // /proc/net/dev: "iface: rxBytes p e d f fr c m txBytes ...". Only real
        // links count -- loopback, VPN tunnels and container/VM bridges would
        // either double-count traffic (a VPN's bytes also cross wlp*) or show
        // purely local traffic.
        let rx = 0, tx = 0
        for (const l of root._net.text().split("\n")) {
            const m = l.match(/^\s*([^:\s]+):\s*(.*)$/)
            if (!m || /^(lo|tun|wg|proton|docker|veth|virbr|br-)/.test(m[1])) continue
            const f = m[2].trim().split(/\s+/).map(Number)
            if (f.length >= 9) { rx += f[0]; tx += f[8] }
        }
        // Timed by the wall clock, not the nominal interval: Timer ticks drift
        // under load, which would show as fake rate spikes.
        const now = Date.now()
        if (root._lastNet) {
            const dt = (now - root._lastNet.t) / 1000
            // A counter going backwards (interface went away) would be a
            // negative rate; clamp instead of showing nonsense for one tick.
            if (dt > 0) {
                root.netRx = Math.max(0, (rx - root._lastNet.rx) / dt)
                root.netTx = Math.max(0, (tx - root._lastNet.tx) / dt)
            }
        }
        root._lastNet = { t: now, rx: rx, tx: tx }

        const up = parseFloat(root._uptime.text())
        if (!isNaN(up)) root.uptimeSec = up

        root.cpuHistory = root._push(root.cpuHistory, root.cpu)
        root.ramHistory = root._push(root.ramHistory, root.ram)
        if (root.gpu >= 0) root.gpuHistory = root._push(root.gpuHistory, root.gpu)
        root.netRxHistory = root._push(root.netRxHistory, root.netRx)
        root.netTxHistory = root._push(root.netTxHistory, root.netTx)
    }

    // Dropping the last net sample on close: a delta spanning the closed
    // period would show as one huge spike on the next open. Done on close,
    // not open, since the timer's triggeredOnStart may sample before this
    // handler runs.
    onActiveChanged: {
        if (active) root._df.running = true
        else root._lastNet = null
    }

    property Timer _timer: Timer {
        interval: 1500
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root._sample()
    }

    property FileView _stat: FileView { path: "/proc/stat"; printErrors: false }
    property FileView _mem: FileView { path: "/proc/meminfo"; printErrors: false }
    property FileView _temp: FileView { path: root._tempPath; printErrors: false }
    property FileView _gpuBusy: FileView { path: root._gpuBusyPath; printErrors: false }
    property FileView _gpuTempFile: FileView { path: root._gpuTempPath; printErrors: false }
    property FileView _power: FileView { path: root._powerPath; printErrors: false }
    property FileView _fan: FileView { path: root._fanPath; printErrors: false }
    property FileView _net: FileView { path: "/proc/net/dev"; printErrors: false }
    property FileView _uptime: FileView { path: "/proc/uptime"; printErrors: false }

    // Disk usage barely moves within one open of the card, so it's read once
    // per open rather than forking df every tick.
    property Process _df: Process {
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = (text.trim().split("\n")[1] || "").trim().split(/\s+/).map(Number)
                if (f.length >= 2 && f[1] > 0) {
                    root.diskUsedGb = f[0] / 1073741824
                    root.diskTotalGb = f[1] / 1073741824
                }
            }
        }
    }

    // CPU package sensor: k10temp (AMD) or coretemp (Intel), found by name
    // since hwmonN numbering changes between boots.
    property string _tempPath: ""
    property Process _findTemp: Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); "
            + "case $n in k10temp|coretemp|zenpower) echo $h/temp1_input; exit;; esac; done"]
        stdout: StdioCollector { onStreamFinished: root._tempPath = text.trim() }
    }

    // Same idea for the GPU: amdgpu's hwmon has the edge temp and package power
    // (on an APU power1_input is the whole SoC; older kernels only expose
    // power1_average), and the busy counter lives on the drm card, whose
    // cardN number also isn't stable (card0 vs card1 with simpledrm). Fan:
    // the first hwmon reporting a spinning fan1, preferring the vendor
    // driver (`asus` here) over the generic acpi_fan, which also reports one
    // but is only the firmware's coarser view of the same fan.
    property string _gpuBusyPath: ""
    property string _gpuTempPath: ""
    property string _powerPath: ""
    property string _fanPath: ""
    property Process _findSensors: Process {
        running: true
        command: ["sh", "-c", "for c in /sys/class/drm/card*/device/gpu_busy_percent; do "
            + "[ -r $c ] && { echo busy=$c; break; }; done; "
            + "for h in /sys/class/hwmon/hwmon*; do "
            + "if [ \"$(cat $h/name 2>/dev/null)\" = amdgpu ] && [ -z \"$g\" ]; then g=1; "
            + "[ -r $h/temp1_input ] && echo gtemp=$h/temp1_input; "
            + "for p in power1_input power1_average; do [ -r $h/$p ] && { echo power=$h/$p; break; }; done; fi; "
            + "if [ -z \"$f\" ] && [ \"$(cat $h/fan1_input 2>/dev/null)\" -gt 0 ] 2>/dev/null; then "
            + "if [ \"$(cat $h/name)\" = acpi_fan ]; then a=${a:-$h/fan1_input}; else f=$h/fan1_input; fi; fi; "
            + "done; [ -n \"${f:-$a}\" ] && echo fan=${f:-$a}"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=")
                    if (i < 0) continue
                    const k = l.slice(0, i), v = l.slice(i + 1)
                    if (k === "busy") root._gpuBusyPath = v
                    else if (k === "gtemp") root._gpuTempPath = v
                    else if (k === "power") root._powerPath = v
                    else if (k === "fan") root._fanPath = v
                }
            }
        }
    }
}
