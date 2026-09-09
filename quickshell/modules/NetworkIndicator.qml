import QtQuick
import Quickshell
import Quickshell.Networking

Pill {
    id: root

    function deviceOfType(type) {
        const devices = Networking.devices.values
        for (const d of devices) if (d.type === type) return d
        return null
    }
    function connectedNetwork(device) {
        if (!device) return null
        for (const n of device.networks.values) if (n.connected) return n
        return null
    }

    property var wifiDevice: deviceOfType(DeviceType.Wifi)
    property var wiredDevice: deviceOfType(DeviceType.Wired)
    property var wifiNetwork: connectedNetwork(wifiDevice)

    readonly property bool wiredUp: wiredDevice && wiredDevice.hasLink && wiredDevice.connected
    readonly property bool wifiUp: wifiDevice && wifiDevice.connected

    function icon() {
        if (wiredUp) return ""
        if (wifiUp) {
            const s = wifiNetwork ? wifiNetwork.signalStrength : 0
            if (s > 80) return ""
            if (s > 55) return ""
            if (s > 30) return ""
            return ""
        }
        return ""
    }

    // Ink heights (fontTools glyf bbox, units/1000em) -- these glyphs
    // don't share a uniform advance box the way Volume.qml's do, so each
    // state needs its own scale to land on the shared bar icon target.
    function iconInkUnits() {
        if (wiredUp) return 450
        if (wifiUp) return 422
        return 524
    }

    tooltipText: {
        if (wiredUp) return "Ethernet"
        if (wifiUp && wifiNetwork) return wifiNetwork.name + " (" + Math.round(wifiNetwork.signalStrength) + "%)"
        return "Disconnected"
    }

    onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/wlctl-toggle.sh"])

    BarIcon {
        glyph: root.icon()
        pixelSize: Theme.barIconInkHeight * 1000 / root.iconInkUnits()
        color: (root.wiredUp || root.wifiUp) ? Theme.text : Theme.critical
    }
}
