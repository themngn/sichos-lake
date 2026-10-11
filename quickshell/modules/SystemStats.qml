pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / RAM / temperature for the Control Center's System tile. Polls
// /proc and the CPU's hwmon sensor only while the Control Center's main page
// is open (on any screen) -- nothing runs the rest of the time. Keeps the
// last `historyLength` samples for the 2-row tile's graphs.
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

    property var _lastCpu: null

    function _push(list, v) {
        const out = list.concat([v])
        return out.length > root.historyLength ? out.slice(out.length - root.historyLength) : out
    }

    function _sample() {
        root._stat.reload()
        root._mem.reload()
        if (root._tempPath) root._temp.reload()

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

        if (root._tempPath) {
            const t = Number(root._temp.text().trim())
            if (t > 0) root.temp = t / 1000
        }

        root.cpuHistory = root._push(root.cpuHistory, root.cpu)
        root.ramHistory = root._push(root.ramHistory, root.ram)
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

    // CPU package sensor: k10temp (AMD) or coretemp (Intel), found by name
    // since hwmonN numbering changes between boots.
    property string _tempPath: ""
    property Process _findTemp: Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); "
            + "case $n in k10temp|coretemp|zenpower) echo $h/temp1_input; exit;; esac; done"]
        stdout: StdioCollector { onStreamFinished: root._tempPath = text.trim() }
    }
}
