import QtQuick
import Quickshell.Services.UPower

Pill {
    id: root

    function profileName() {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance: return "Performance"
        case PowerProfile.PowerSaver: return "Power Saver"
        default: return "Balanced"
        }
    }
    tooltipText: "Power profile: " + root.profileName()

    function cycle() {
        if (PowerProfiles.profile === PowerProfile.Performance) PowerProfiles.profile = PowerProfile.PowerSaver
        else if (PowerProfiles.profile === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced
        else PowerProfiles.profile = PowerProfile.Performance
    }
    onClicked: root.cycle()

    function icon() {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance: return ""
        case PowerProfile.PowerSaver: return "󰌪"
        default: return ""
        }
    }
    function iconColor() {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance: return Theme.perfPerformance
        case PowerProfile.PowerSaver: return Theme.perfPowerSaver
        default: return Theme.perfBalanced
        }
    }
    // Ink heights (fontTools glyf bbox, units/1000em): Performance 802,
    // Power Saver 572, Balanced 482 -- scaled individually so all three
    // states render at the same visual height instead of drifting with
    // the flat pixelSize this used before.
    function iconInkUnits() {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance: return 802
        case PowerProfile.PowerSaver: return 572
        default: return 482
        }
    }

    BarIcon {
        glyph: root.icon()
        pixelSize: Theme.barIconInkHeight * 1000 / root.iconInkUnits()
        color: root.iconColor()
    }
}
