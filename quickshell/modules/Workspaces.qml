import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Pill {
    id: root
    horizontalPadding: 0

    // Cosmetic-only placeholder pills for the dynamic workspace pool
    // (hypr/workspaces.lua, workspaces.md) so pool workspace ids are
    // always visible even before anything's been put on them, without
    // Hyprland's own workspace_rule persistent=true -- that actively
    // broke the pool (see the comment in workspaces.lua where that block
    // used to be) because it made Hyprland force-reassign persistent
    // workspaces onto whichever monitor has focus on every monitor
    // connect. This file is written by workspaces.lua and is otherwise
    // unused -- Lua stays the sole source of truth for anything that
    // actually dispatches or binds.
    FileView {
        id: poolSizeFile
        path: Quickshell.env("HOME") + "/.local/state/sichos/pool-size"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property int poolSize: {
        const n = parseInt(poolSizeFile.text())
        return Number.isFinite(n) && n > 0 ? n : 6
    }

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
        const liveIds = new Set(list.map(w => w.id))
        // Placeholder pills for pool ids Hyprland hasn't materialized (an
        // empty/unsummoned pool workspace doesn't exist as a live object --
        // see workspaces.lua). Plain JS objects, not real HyprlandWorkspace
        // instances, so they have no .activate() -- the click handler below
        // falls back to Hyprland.dispatch() for those.
        for (let i = 1; i <= root.poolSize; i++) {
            if (!liveIds.has(i))
                list.push({ id: i, name: String(i), focused: false, urgent: false, placeholder: true })
        }
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



                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: modelData.placeholder ? Hyprland.dispatch("workspace " + modelData.id) : modelData.activate()
                }
            }
        }
    }
}
