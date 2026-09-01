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

    Text {
        // Fixed width (same approach as BluetoothIndicator's icon) so the
        // pill doesn't shift the rest of the bar when the profile's glyph
        // changes — different icons have different font-advance widths even
        // at the same pixel size.
        width: Theme.fontSize * 1.6
        horizontalAlignment: Text.AlignHCenter
        text: root.icon()
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        color: root.iconColor()
    }
}
