import QtQuick
import Quickshell.Services.UPower

Pill {
    id: root
    property var dev: UPower.displayDevice
    visible: dev && dev.isPresent

    readonly property bool charging: dev && dev.state === UPowerDeviceState.Charging
    readonly property bool critical: dev && dev.percentage < 0.10 && !charging

    tooltipText: dev ? Math.round(dev.percentage * 100) + "%" + (charging ? " (charging)" : "") : ""

    // Discharging glyphs, one per 10% bucket (nf-md-battery_10 .. _90);
    // 100% uses the plain nf-md-battery (full) glyph instead of a _100 that
    // doesn't exist.
    readonly property var dischargeIcons: ({
        10: "󰁺", 20: "󰁻", 30: "󰁼", 40: "󰁽", 50: "󰁾",
        60: "󰁿", 70: "󰂀", 80: "󰂁", 90: "󰂂"
    })
    readonly property string fullIcon: "󰁹"
    readonly property string alertIcon: "󰂃" // nf-md-battery_alert, near-empty

    // Charging glyphs, one per 10% bucket -- MDI's codepoints for these
    // aren't contiguous (10/50/70 live in a different block than the rest),
    // so this has to be a lookup table rather than icon()'s old arithmetic
    // offset into a small array.
    readonly property var chargingIcons: ({
        10: "󰢜", 20: "󰂆", 30: "󰂇", 40: "󰂈", 50: "󰢝",
        60: "󰂉", 70: "󰢞", 80: "󰂊", 90: "󰂋", 100: "󰂅"
    })
    readonly property string fullyChargedIcon: "󰂄" // nf-md-battery_charging, plugged in and topped off

    function icon() {
        if (!dev) return ""
        if (dev.state === UPowerDeviceState.FullyCharged) return root.fullyChargedIcon
        const bucket = Math.max(10, Math.min(100, Math.round(dev.percentage * 100 / 10) * 10))
        // Some devices report Charging (not FullyCharged) right at 100% --
        // e.g. trickle-charging to stay topped off -- so treat that as the
        // same "plugged in, done" icon rather than the animated-100% one.
        if (dev.state === UPowerDeviceState.Charging) return bucket === 100 ? root.fullyChargedIcon : root.chargingIcons[bucket]
        if (root.critical) return root.alertIcon
        return bucket === 100 ? root.fullIcon : root.dischargeIcons[bucket]
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
            glyph: root.icon()
            // Two different ink ratios, not one -- checked against the actual
            // rendered font (JetBrainsMono Nerd Font *Mono*, not the
            // Regular/Propo build fontTools normally shows): the Mono build
            // squeezes any glyph wider than its monospace cell down to fit,
            // and nf-md-battery_charging_10.._100 are ~1.75x wider (bolt
            // glyph beside the battery body) than every other icon used
            // here, so Mono shrinks just those to 570/1000em ink height
            // instead of the usual 928/1000em -- confirmed via fontTools
            // glyf bbox on JetBrainsMonoNerdFontMono-Regular.ttf specifically.
            // nf-md-battery_charging (fullyChargedIcon, no bolt, same width
            // as the plain icons) is unaffected and uses the normal ratio.
            pixelSize: Theme.barIconInkHeight * 1000 / (root.charging ? 570 : 928)
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
