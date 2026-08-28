import QtQuick
import Quickshell
import Quickshell.Hyprland

Pill {
    id: root
    horizontalPadding: 0

    // Bumped on every window lifecycle event so the `windows` list below
    // (which the icon Repeater's identity depends on) always re-evaluates
    // promptly, since a brand-new toplevel's `workspace` property doesn't
    // reliably emit its own change notification the instant Hyprland
    // assigns it.
    property int windowEpoch: 0

    // For a genuinely new window, Quickshell's own `lastIpcObject.class`
    // can stay permanently empty for that toplevel object — not just
    // briefly unset, but never populated for the rest of its lifetime
    // (reproduced with Firefox's IPC-forked --new-window). The openwindow
    // IPC event itself carries the class directly in its payload though
    // ("<address>,<workspace>,<class>,<title>"), so that's cached here and
    // used ahead of the (possibly-broken) lastIpcObject as the source of
    // truth for the icon.
    property var addressClassMap: ({})

    function normalizedAddress(addr) {
        return addr ? addr.toLowerCase().replace(/^0x/, "") : ""
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow") {
                const parts = event.data.split(",")
                if (parts.length >= 3) {
                    const map = Object.assign({}, root.addressClassMap)
                    map[root.normalizedAddress(parts[0])] = parts[2]
                    root.addressClassMap = map
                }
            }
            if (event.name === "openwindow" || event.name === "closewindow"
                || event.name === "movewindow" || event.name === "movewindowv2") {
                root.windowEpoch++
            }
        }
    }

    function classForToplevel(t) {
        const cached = root.addressClassMap[root.normalizedAddress(t.address)]
        if (cached) return cached
        return t.lastIpcObject ? t.lastIpcObject.class : ""
    }

    // Special workspaces sort after normal ones, id-ascending within each group
    readonly property var sortedWorkspaces: {
        const list = Hyprland.workspaces.values.slice()
        list.sort((a, b) => {
            const aSpecial = a.name.startsWith("special:")
            const bSpecial = b.name.startsWith("special:")
            if (aSpecial !== bSpecial) return aSpecial ? 1 : -1
            return a.id - b.id
        })
        return list
    }

    Row {
        spacing: 2

        Repeater {
            model: root.sortedWorkspaces

            delegate: Item {
                id: wsItem
                required property var modelData

                readonly property var windows: {
                    const epoch = root.windowEpoch // forces recompute on every window event
                    const result = []
                    const toplevels = Hyprland.toplevels.values
                    for (const t of toplevels) {
                        if (t.workspace && t.workspace.id === modelData.id) result.push(t)
                    }
                    return result
                }

                width: content.implicitWidth + 12
                height: Theme.barHeight

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.name.startsWith("special:") ? modelData.name.substring(8) : modelData.name) + ":"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: modelData.focused ? Theme.text
                             : modelData.urgent ? Theme.urgent
                             : wsMouse.containsMouse ? Theme.text : Theme.textMuted
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        visible: wsItem.windows.length > 0

                        Repeater {
                            model: wsItem.windows

                            delegate: Image {
                                id: appIcon
                                required property var modelData
                                readonly property string resolved: DesktopIcons.iconPathForClass(root.classForToplevel(modelData))

                                visible: resolved.length > 0
                                source: resolved
                                width: 12
                                height: 12
                                sourceSize: Qt.size(12, 12)
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }

                // Mirrors waybar's `box-shadow: inset 0 -2px #fff` active-workspace underline
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: 2
                    color: Theme.text
                    visible: modelData.focused
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: modelData.activate()
                }
            }
        }
    }
}
