import QtQuick
import Quickshell
import Quickshell.Hyprland

// Right-click menu for a workspace pill in Workspaces.qml: move it to another
// monitor, or swap it with what another monitor is showing. The actual moves
// live in hypr/workspaces.lua (SichosWorkspaces.*), reached via `hyprctl eval`
// -- `hyprctl dispatch` doesn't work on this Lua-config build, and keeping the
// dispatch logic in Lua keeps it next to the pool rules it has to respect.
// Click-driven rather than hover-driven like the bar's other popups, so it
// uses a focus grab: clicking anywhere else (or Esc) closes it. Also closes
// once the mouse has left it for a moment, same as the hover popups -- a
// focus grab that fails to take (see grabDelay below) would otherwise leave
// the menu up with no way to dismiss it short of picking an option.
PopupWindow {
    id: menu

    // Set by Workspaces.qml when opening; null = closed.
    property var workspace: null
    property Item anchorItem: null
    // Pool size, from Workspaces.qml (same pool-size file it already reads).
    property int poolSize: 6

    visible: workspace !== null && anchorItem !== null && options.length > 0
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4
    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    // Every row as wide as the longest label (measured off-layout below), so
    // the hover highlights line up instead of each row sizing to its own text.
    readonly property real rowWidth: Math.max(200, labelMeasure.implicitWidth + Theme.fontSize + 24)

    function close() {
        menu.workspace = null
    }

    function monitorLabel(m) {
        // The built-in panel's EDID model is a bare hex product code
        // (e.g. "0x41A0") -- meaningless as a label.
        if (m.name.startsWith("eDP")) return "Built-in (" + m.name + ")"
        const model = m.lastIpcObject && m.lastIpcObject.model
        return model && !/^0x[0-9a-f]+$/i.test(model) ? model + " (" + m.name + ")" : m.name
    }

    // Mirrors workspaces.lua's isPoolWorkspace(): a pool id that doesn't
    // exist, or exists but is hidden and empty, other than `exceptId`.
    function hasSparePoolWorkspace(exceptId) {
        const live = Hyprland.workspaces.values
        for (let i = 1; i <= menu.poolSize; i++) {
            if (i === exceptId) continue
            const ws = live.find(w => w.id === i)
            if (!ws) return true
            if (!ws.active && ws.toplevels.values.length === 0) return true
        }
        return false
    }

    // Only options that can actually happen right now (the Lua side re-checks
    // the same conditions anyway):
    //  - Move: any real (non-placeholder, non-special) workspace, to any other
    //    monitor -- but if it's the one on screen, its monitor needs a spare
    //    pool workspace to show instead (workspaces.lua refuses otherwise).
    //  - Swap: only the workspace on screen, since Hyprland swaps each
    //    monitor's active workspace.
    readonly property var options: {
        const ws = menu.workspace
        if (!ws || ws.placeholder || ws.name.startsWith("special:") || !ws.monitor) return []
        const others = Hyprland.monitors.values.filter(m => m.name !== ws.monitor.name)
        const opts = []
        if (!ws.active || menu.hasSparePoolWorkspace(ws.id)) {
            for (const m of others)
                opts.push({ kind: "move", monitor: m.name, label: "Move to " + menu.monitorLabel(m) })
        }
        if (ws.active) {
            for (const m of others) {
                const other = m.activeWorkspace ? " — " + m.activeWorkspace.name : ""
                opts.push({ kind: "swap", monitor: m.name, label: "Swap with " + menu.monitorLabel(m) + other })
            }
        }
        return opts
    }

    function run(option) {
        const fn = option.kind === "move" ? "moveToMonitor" : "swapWithMonitor"
        Quickshell.execDetached(["hyprctl", "eval",
            "SichosWorkspaces." + fn + "(" + menu.workspace.id + ", " + JSON.stringify(option.monitor) + ")"])
        menu.close()
    }

    // Activated a tick after the menu shows rather than bound straight to
    // `visible`: the grab is requested in the same instant the window is
    // asked to map, and a grab on a not-yet-mapped surface can be dropped
    // without an error. Bound straight to `visible`, the menu was observed
    // to never close on an outside click -- this was the likely cause.
    property bool grabbing: false
    onVisibleChanged: {
        menu.grabbing = false
        if (menu.visible) grabDelay.restart()
    }
    Timer {
        id: grabDelay
        interval: 50
        onTriggered: menu.grabbing = menu.visible
    }
    HyprlandFocusGrab {
        windows: [menu]
        active: menu.grabbing
        onCleared: menu.close()
    }

    // Hover fallback: closes after the mouse has been off the menu for a
    // bit. The first, longer interval covers moving from the right-clicked
    // pill down into the menu; once the menu has been entered, leaving it
    // closes it quickly like the other bar popups.
    property bool wasHovered: false
    onWorkspaceChanged: menu.wasHovered = false
    Timer {
        id: leaveTimer
        interval: menu.wasHovered ? 400 : 1500
        running: menu.visible && !menuHover.hovered
        onTriggered: menu.close()
    }

    Squircle {
        id: bg
        SurfaceAppear { target: bg; shown: menu.visible }
        implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
        implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding
        color: Theme.surfaceFor(menu.screen)
        borderColor: Theme.surfaceBorder
        borderWidth: Theme.surfaceBorderWidth
        radius: Theme.surfaceSquircleRadius

        focus: true
        Keys.onEscapePressed: menu.close()

        HoverHandler {
            id: menuHover
            onHoveredChanged: if (hovered) menu.wasHovered = true
        }

        // Invisible copy of the row labels, only to measure the widest one.
        Column {
            id: labelMeasure
            opacity: 0
            Repeater {
                model: menu.options
                delegate: Text {
                    required property var modelData
                    text: modelData.label
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 4

            Row {
                spacing: 6
                bottomPadding: 4
                HeaderIcon {
                    glyph: "󰍹"
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.workspace ? "Workspace " + menu.workspace.name : ""
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
            }

            Repeater {
                model: menu.options

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    // Separator-free grouping: a small gap before the first
                    // swap option when move options precede it.
                    readonly property bool groupStart: index > 0 && modelData.kind !== menu.options[index - 1].kind

                    width: menu.rowWidth
                    height: Theme.controlHeight
                    radius: Theme.controlRadius
                    color: rowArea.containsMouse ? Theme.hoverFill : "transparent"

                    Rectangle {
                        visible: row.groupStart
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 2
                        width: parent.width
                        height: 1
                        color: Theme.separator
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            id: rowIcon
                            anchors.verticalCenter: parent.verticalCenter
                            // nf-fa-arrow_right / nf-fa-exchange
                            text: row.modelData.kind === "move" ? "" : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: rowArea.containsMouse ? Theme.accent : Theme.textMuted
                        }
                        Text {
                            id: rowLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.text
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: menu.run(row.modelData)
                    }
                }
            }
        }
    }
}
