import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// HDR popup panel for HdrToggle.qml: an On/Off switch (mirrors SunsetPopup's
// mode row) plus a checkbox per currently connected monitor, so HDR can be
// limited to the displays that actually render it well instead of hitting
// every screen. Hover-driven with persistent hover, same as
// SunsetPopup/IdlePopup.
PopupWindow {
    id: popup

    required property Item anchorItem

    readonly property bool popupHovered: popupHoverHandler.hovered

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

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

    onVisibleChanged: if (visible) capabilityProc.running = true

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

    Rectangle {
        id: bg
        SurfaceAppear { target: bg; shown: popup.visible }
        implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
        implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding
        color: Theme.surfaceFor(popup.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            // Menu Title Header
            Item {
                width: 240
                height: 20

                PinButton {
                    toggleId: "hdr"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "󰍹"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        color: HdrSettings.active ? Theme.accent : Theme.textDim
                    }
                    Text {
                        text: "HDR"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            // Mode switch
            Row {
                width: 240
                spacing: 6

                Repeater {
                    model: [
                        { on: true, label: "On" },
                        { on: false, label: "Off" }
                    ]
                    delegate: Rectangle {
                        id: modeButton
                        required property var modelData
                        readonly property bool isActive: HdrSettings.active === modeButton.modelData.on
                        width: 117
                        height: Theme.controlHeight
                        radius: Theme.controlRadius
                        color: modeButton.isActive ? Theme.selectedFill : modeArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                        border.color: modeButton.isActive ? Theme.accent : Theme.surfaceBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modeButton.modelData.label
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: modeButton.isActive ? Theme.text : Theme.textMuted
                        }

                        MouseArea {
                            id: modeArea
                            hoverEnabled: true
                            anchors.fill: parent
                            onClicked: HdrSettings.setActive(modeButton.modelData.on)
                        }
                    }
                }
            }

            Rectangle {
                width: 240
                height: 1
                color: Theme.separator
            }

            Text {
                text: "Use HDR on"
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            Column {
                width: 240
                spacing: 6
                opacity: HdrSettings.active ? 1 : 0.5

                Repeater {
                    model: Hyprland.monitors.values
                    delegate: MonitorCheckbox {
                        required property var modelData
                        label: modelData.name + (modelData.description ? " — " + modelData.description : "")
                        // Only a confirmed `false` greys it out -- `undefined`
                        // (capability check hasn't returned yet) or `null`
                        // (EDID unreadable/no CTA-861 block) both mean
                        // "can't tell", not "unsupported".
                        capable: popup.hdrCapability[modelData.name] !== false
                        checked: HdrSettings.isSelected(modelData.name)
                        onToggled: HdrSettings.toggleMonitor(modelData.name)
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

    component MonitorCheckbox: Item {
        id: checkbox
        property string label: ""
        property bool checked: false
        // Still clickable even when false -- greyed out is a hint, not a
        // hard block, so a monitor already selected before it went (or was
        // discovered to be) HDR-incapable can still be unchecked.
        property bool capable: true
        signal toggled()

        width: 240
        height: checkText.implicitHeight
        opacity: checkbox.capable ? 1 : 0.4

        Text {
            id: checkText
            width: parent.width
            elide: Text.ElideRight
            text: (checkbox.checked ? "󰄲  " : "󰄱  ") + checkbox.label + (checkbox.capable ? "" : " (no HDR support)")
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
            color: checkArea.containsMouse ? Theme.text : Theme.textMuted
        }
        MouseArea {
            id: checkArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: checkbox.toggled()
        }
    }
}
