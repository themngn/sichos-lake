import QtQuick
import Quickshell.Services.UPower

Pill {
    id: root
    property var dev: UPower.displayDevice
    visible: dev && dev.isPresent

    readonly property bool charging: dev && dev.state === UPowerDeviceState.Charging
    readonly property bool critical: dev && dev.percentage <= 0.15 && !charging

    tooltipText: dev ? Math.round(dev.percentage * 100) + "%" + (charging ? " (charging)" : "") : ""

    function icon() {
        if (!dev) return ""
        const icons = ["", "", "", "", ""]
        const idx = Math.max(0, Math.min(icons.length - 1, Math.floor(dev.percentage * 100 / 20)))
        return icons[idx]
    }

    Row {
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.dev ? Math.round(root.dev.percentage * 100) : 0) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: root.charging ? Theme.success : root.critical ? Theme.critical : Theme.text
        }

        BarIcon {
            id: batteryIcon
            glyph: root.charging ? "" : root.icon()
            // Font Awesome battery glyphs ink 334/1000em (fontTools glyf
            // bbox) -- scaled up to the shared bar icon target.
            pixelSize: Theme.barIconInkHeight * 1000 / 334
            color: root.charging ? Theme.success : root.critical ? Theme.critical : Theme.text

            property real blinkOpacity: 1
            opacity: root.critical ? blinkOpacity : 1

            // Mirrors waybar's @keyframes blink alternating the critical battery color
            SequentialAnimation on blinkOpacity {
                running: root.critical
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.25; duration: 500 }
                NumberAnimation { from: 0.25; to: 1; duration: 500 }
            }
        }
    }
}
