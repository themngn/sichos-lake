import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// HDR popup panel for HdrToggle.qml: an on/off switch in the header plus a
// switch row per currently connected monitor, so HDR can be
// limited to the displays that actually render it well instead of hitting
// every screen. Hover-driven with persistent hover, same as
// SunsetPopup/IdlePopup.
MorphContent {
    id: popup
    // Set when the Control Center embeds this as one of its pages: the
    // header's back button returns there.
    property string backPopupId: ""
    // Wider when embedded, to match the Control Center card.
    property real contentWidth: Theme.togglePopupWidth


    readonly property bool popupHovered: popupHoverHandler.hovered


    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    // name -> true|false|null ("can't tell" -- an unreadable/absent EDID,
    // treated the same as capable so an unknown display isn't greyed out
    // just because we couldn't check it). hyprctl/wlr-randr expose no
    // "supports HDR" field on this Hyprland (0.56.2, confirmed live) --
    // hdr-capable.py reads each connector's EDID directly for a CTA-861
    // HDR Static Metadata Data Block instead, which needs no live monitor
    // change to find out (unlike actually requesting cm="hdr" and seeing
    // whether colorManagementPreset comes back "hdr" or falls back to
    // "srgb" -- confirmed live that DP-1 here does exactly that fallback).
    property var hdrCapability: ({})

    onShownChanged: if (shown) capabilityProc.running = true

    Process {
        id: capabilityProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/hdr-capable.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    popup.hdrCapability = JSON.parse(text)
                } catch (e) { /* leave the previous (or empty) map in place */ }
            }
        }
    }

    Item {
        id: bg
        anchors.fill: parent

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            PageHeader {
                width: popup.contentWidth
                title: "HDR"
                showBack: popup.backPopupId !== ""
                onBack: ShellState.activePopup = popup.backPopupId
                Switch {
                    checked: HdrSettings.active
                    onToggled: HdrSettings.setActive(!HdrSettings.active)
                }
            }

            SectionLabel {
                text: "Use HDR on"
            }

            Column {
                width: popup.contentWidth
                spacing: 6

                Repeater {
                    model: Hyprland.monitors.values
                    delegate: PageRow {
                        id: monRow
                        required property var modelData
                        // Only a confirmed `false` counts as unsupported --
                        // `undefined` (capability check hasn't returned yet)
                        // or `null` (EDID unreadable/no CTA-861 block) both
                        // mean "can't tell".
                        readonly property bool capable: popup.hdrCapability[modelData.name] !== false
                        readonly property bool laptop: /^(eDP|LVDS|DSI)/.test(modelData.name)
                        width: popup.contentWidth
                        compact: true
                        glyph: monRow.laptop ? "\u{f0322}" : "\u{f0e51}"
                        active: HdrSettings.isSelected(modelData.name) && HdrSettings.active
                        // EDID make is the legal entity ("Lenovo Group
                        // Limited") -- trimmed to the brand, as on the
                        // Display page.
                        readonly property var ipc: modelData.lastIpcObject || {}
                        title: monRow.laptop ? "Built-in Display"
                            : monRow.ipc.model ? ((monRow.ipc.make || "").replace(
                                /\s*\b(Group Limited|North America|Corporation|Co\.,? Ltd\.?|Inc\.?|Technology|Electronics|Company)\b\s*/gi, " ").trim()
                                + " " + monRow.ipc.model).trim()
                            : (modelData.description || modelData.name)
                        subtitle: modelData.name + (monRow.capable ? "" : " · no HDR support")
                        // Greyed as a hint, not a block: a monitor selected
                        // before it went (or was found to be) incapable can
                        // still be switched off.
                        opacity: monRow.capable ? 1 : 0.45
                        onClicked: HdrSettings.toggleMonitor(modelData.name)
                        Switch {
                            checked: HdrSettings.isSelected(monRow.modelData.name)
                            onToggled: HdrSettings.toggleMonitor(monRow.modelData.name)
                        }
                    }
                }

                Text {
                    visible: Hyprland.monitors.values.length === 0
                    text: "No monitors detected"
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }
}
