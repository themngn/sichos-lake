pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Battery details for the Control Center's power card: health, cycles,
// live wattage and UPower's charge limit (stop charging at chargeLimitEnd%,
// resume below chargeLimitStart%). Levels and wattage come from Quickshell's
// UPower binding and update by themselves; only the sysfs bits (cycle count,
// design capacity) need polling, and that runs only while `active` -- the
// card binds it to "open". The charge-limit properties aren't in Quickshell's
// binding, so they're read over D-Bus with busctl.
QtObject {
    id: root

    property bool active: false

    // The physical battery rather than UPower.displayDevice: the display
    // device is an aggregate and never reports health.
    readonly property var battery: {
        const devs = UPower.devices.values
        for (let i = 0; i < devs.length; i++)
            if (devs[i].isLaptopBattery) return devs[i]
        return null
    }
    readonly property bool present: !!(battery && battery.isPresent)
    readonly property bool onBattery: UPower.onBattery

    readonly property real energyWh: present ? battery.energy : 0
    readonly property real energyFullWh: present ? battery.energyCapacity : 0
    property real designWh: 0
    property int cycles: -1

    // UPower's own figure when it has one (0..100), else full vs. design.
    readonly property real healthPercent: present && battery.healthSupported && battery.healthPercentage > 0
        ? battery.healthPercentage
        : designWh > 0 && energyFullWh > 0 ? Math.min(100, energyFullWh / designWh * 100) : -1

    // UPower's rate is unsigned; sign it so callers can show "-12.3 W"
    // while draining and "+30 W" while charging.
    readonly property real watts: !present ? 0
        : battery.state === UPowerDeviceState.Discharging ? -battery.changeRate
        : battery.state === UPowerDeviceState.Charging ? battery.changeRate : 0

    function timeText() {
        const d = root.battery
        if (!d || !d.isPresent) return ""
        if (d.state === UPowerDeviceState.FullyCharged) return "Full"
        const charging = d.state === UPowerDeviceState.Charging
        const secs = charging ? d.timeToFull : d.timeToEmpty
        if (!(secs > 0)) return ""
        const h = Math.floor(secs / 3600)
        const m = Math.round((secs % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m" + (charging ? " to full" : " left")
    }

    // --- Charge limit (UPower >= 1.90, ChargeThreshold* on the battery) ---

    property bool chargeLimitSupported: false
    property bool chargeLimitEnabled: false
    property int chargeLimitStart: 0
    property int chargeLimitEnd: 0
    property bool chargeLimitBusy: false
    property string chargeLimitError: ""

    property string _batteryPath: ""

    function setChargeLimit(on) {
        if (!root._batteryPath || root.chargeLimitBusy) return
        root.chargeLimitError = ""
        root.chargeLimitBusy = true
        root._setLimit.command = ["busctl", "call", "--system", "org.freedesktop.UPower", root._batteryPath,
            "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", on ? "true" : "false"]
        root._setLimit.running = true
    }

    function _readLimit() {
        if (!root._readLimitProc.running) root._readLimitProc.running = true
    }

    onActiveChanged: if (active) _readLimit()
    Component.onCompleted: _readLimit()

    // Finds the battery's object path (the name follows the kernel's, e.g.
    // battery_BAT0 / battery_BAT1) and prints the four properties in order,
    // one "<type> <value>" line each.
    property Process _readLimitProc: Process {
        command: ["sh", "-c", "p=$(upower -e | grep -m1 /battery_) || exit 1; echo \"$p\"; "
            + "busctl get-property --system org.freedesktop.UPower \"$p\" org.freedesktop.UPower.Device "
            + "ChargeThresholdSupported ChargeThresholdEnabled ChargeStartThreshold ChargeEndThreshold"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                root._batteryPath = lines[0] || ""
                // Older UPower lacks the properties: busctl fails, leaving
                // just the path line, and the limit stays unsupported.
                if (lines.length < 5) { root.chargeLimitSupported = false; return }
                const val = l => (l || "").trim().split(/\s+/)[1]
                root.chargeLimitSupported = val(lines[1]) === "true"
                root.chargeLimitEnabled = val(lines[2]) === "true"
                root.chargeLimitStart = Number(val(lines[3])) || 0
                root.chargeLimitEnd = Number(val(lines[4])) || 0
            }
        }
    }

    // polkit lets the active session toggle this without a password; any
    // refusal ends up in chargeLimitError for the card to show.
    property Process _setLimit: Process {
        stderr: StdioCollector { id: _setErr }
        onExited: (code) => {
            root.chargeLimitBusy = false
            if (code !== 0) root.chargeLimitError = _setErr.text.trim() || "Failed to change the charge limit"
            root._readLimit()
        }
    }

    // --- sysfs: cycle count and design capacity ---

    function _sampleSysfs() {
        if (!root._sysPath) return
        root._cycleFile.reload()
        root._designFile.reload()
        root._chargeDesignFile.reload()
        root._voltageFile.reload()
        const c = parseInt(root._cycleFile.text())
        root.cycles = c > 0 ? c : -1
        // energy_full_design is µWh; batteries that report in charge (µAh)
        // need the design voltage (µV) to get to Wh.
        const e = Number(root._designFile.text().trim())
        const q = Number(root._chargeDesignFile.text().trim())
        const v = Number(root._voltageFile.text().trim())
        root.designWh = e > 0 ? e / 1e6 : q > 0 && v > 0 ? q * v / 1e12 : 0
    }

    property Timer _timer: Timer {
        interval: 10000
        repeat: true
        running: root.active && root._sysPath !== ""
        triggeredOnStart: true
        onTriggered: root._sampleSysfs()
    }

    // nativePath is the power_supply name ("BAT0"); found at runtime since
    // some laptops number it BAT1. blockLoading: reload() is otherwise async
    // and text() right after it still returns the old (initially empty) read.
    readonly property string _sysPath: present && battery.nativePath
        ? "/sys/class/power_supply/" + battery.nativePath.split("/").pop() : ""
    property FileView _cycleFile: FileView { path: root._sysPath ? root._sysPath + "/cycle_count" : ""; blockLoading: true; printErrors: false }
    property FileView _designFile: FileView { path: root._sysPath ? root._sysPath + "/energy_full_design" : ""; blockLoading: true; printErrors: false }
    property FileView _chargeDesignFile: FileView { path: root._sysPath ? root._sysPath + "/charge_full_design" : ""; blockLoading: true; printErrors: false }
    property FileView _voltageFile: FileView { path: root._sysPath ? root._sysPath + "/voltage_min_design" : ""; blockLoading: true; printErrors: false }
}
