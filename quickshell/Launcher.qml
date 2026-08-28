import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth

// Walker-style launcher: one search box, one list, and the root level is
// a plain directory listing — "Apps", "Toggles" and "Power" are all
// folder entries, apps included, rather than apps being flattened in
// alongside the other two.
PanelWindow {
    id: launcher

    screen: Quickshell.screens[0]
    visible: false
    focusable: true
    color: Qt.rgba(0, 0, 0, 0.35)

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    property string mode: "root" // "root" | "apps" | "toggles" | "power" | "hidden" | "appmenu"
    property string query: ""
    property int selectedIndex: 0
    // Which folder to return to when backing out of the app submenu.
    property string returnMode: "apps"
    // The app the submenu (Launch/Hide/Unhide) is currently open for.
    property var contextApp: null

    readonly property var toggleItems: {
        const items = [
            { type: "toggle", id: "idle", name: "Idle Inhibitor", active: ShellState.idleActive },
            { type: "toggle", id: "wifi", name: "Wi-Fi", active: Networking.wifiEnabled }
        ]
        if (Bluetooth.defaultAdapter)
            items.push({ type: "toggle", id: "bluetooth", name: "Bluetooth", active: Bluetooth.defaultAdapter.enabled })
        return items
    }

    readonly property var powerItems: [
        { type: "power", id: "logout", name: "Logout", danger: false },
        { type: "power", id: "suspend", name: "Suspend", danger: false },
        { type: "power", id: "reboot", name: "Reboot", danger: true },
        { type: "power", id: "shutdown", name: "Shutdown", danger: true }
    ]

    readonly property var appItems: AppIndex.apps
        .filter(a => !HiddenApps.isHidden(a.name))
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal }))

    readonly property var hiddenItems: AppIndex.apps
        .filter(a => HiddenApps.isHidden(a.name))
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal }))

    readonly property var appMenuItems: {
        if (!launcher.contextApp) return []
        const hidden = HiddenApps.isHidden(launcher.contextApp.name)
        return [
            { type: "action", id: "launch", name: "Launch" },
            { type: "action", id: hidden ? "unhide" : "hide", name: hidden ? "Unhide" : "Hide" }
        ]
    }

    readonly property var rootItems: [
        { type: "folder", id: "apps", name: "Apps" },
        { type: "folder", id: "toggles", name: "Toggles" },
        { type: "folder", id: "power", name: "Power" },
        { type: "folder", id: "hidden", name: "Hidden" }
    ]

    // Everything selectable, flattened — search always looks through
    // apps + toggles + power actions at once regardless of which folder
    // you're browsing. Hidden apps are deliberately left out: they're
    // only reachable through the Hidden folder.
    readonly property var allItems: launcher.appItems.concat(launcher.toggleItems).concat(launcher.powerItems)

    readonly property var currentItems: {
        if (launcher.mode === "apps") return launcher.appItems
        if (launcher.mode === "toggles") return launcher.toggleItems
        if (launcher.mode === "power") return launcher.powerItems
        if (launcher.mode === "hidden") return launcher.hiddenItems
        if (launcher.mode === "appmenu") return launcher.appMenuItems
        return launcher.rootItems
    }

    readonly property var filtered: {
        const q = launcher.query.toLowerCase()
        if (!q) return launcher.currentItems
        if (launcher.mode === "appmenu") return launcher.currentItems
        return launcher.allItems.filter(i => i.name.toLowerCase().includes(q))
    }

    readonly property string title: launcher.mode === "appmenu" ? launcher.contextApp.name
        : launcher.query.length > 0 ? "Search"
        : launcher.mode === "apps" ? "Apps"
        : launcher.mode === "toggles" ? "Toggles"
        : launcher.mode === "power" ? "Power"
        : launcher.mode === "hidden" ? "Hidden"
        : "Menu"

    // SUPER+Q: straight into Apps.
    function openApps() {
        launcher.mode = "apps"
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.visible = true
    }
    // SUPER+SHIFT+Q: the full root menu (Apps / Toggles / Power folders).
    function openFull() {
        launcher.mode = "root"
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.visible = true
    }
    function close() {
        launcher.visible = false
    }
    function toggleApps() {
        if (launcher.visible) launcher.close()
        else launcher.openApps()
    }
    function toggleFull() {
        if (launcher.visible) launcher.close()
        else launcher.openFull()
    }
    function goBack() {
        if (launcher.mode === "appmenu") {
            launcher.mode = launcher.returnMode
            launcher.query = ""
            launcher.selectedIndex = 0
        } else if (launcher.mode !== "root") {
            launcher.mode = "root"
            launcher.query = ""
            launcher.selectedIndex = 0
        } else {
            launcher.close()
        }
    }

    function launchApp(app) {
        if (app.terminal) Quickshell.execDetached(["kitty", "-e", "sh", "-c", app.exec])
        else Quickshell.execDetached(["sh", "-c", app.exec])
        launcher.close()
    }

    // Enter/Return/click: the item's primary action — launches an app
    // directly, same as before.
    function activate(item) {
        if (!item) return
        if (item.type === "folder") {
            launcher.mode = item.id
            launcher.query = ""
            launcher.selectedIndex = 0
            return
        }
        if (item.type === "app") {
            launcher.launchApp(item)
            return
        }
        if (item.type === "toggle") {
            if (item.id === "idle") ShellState.idleActive = !ShellState.idleActive
            else if (item.id === "wifi") Networking.wifiEnabled = !Networking.wifiEnabled
            else if (item.id === "bluetooth") Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
            return
        }
        if (item.type === "power") {
            const commands = {
                logout: ["sh", "-c", "hyprctl dispatch exit"],
                suspend: ["systemctl", "suspend"],
                reboot: ["systemctl", "reboot"],
                shutdown: ["systemctl", "poweroff"]
            }
            launcher.close()
            Quickshell.execDetached(commands[item.id])
            return
        }
        if (item.type === "action") {
            if (item.id === "launch") {
                launcher.launchApp(launcher.contextApp)
            } else if (item.id === "hide") {
                HiddenApps.hide(launcher.contextApp.name)
                launcher.mode = launcher.returnMode
                launcher.query = ""
                launcher.selectedIndex = 0
            } else if (item.id === "unhide") {
                HiddenApps.unhide(launcher.contextApp.name)
                launcher.mode = launcher.returnMode
                launcher.query = ""
                launcher.selectedIndex = 0
            }
        }
    }

    // Right arrow: "enter" the item. Folders/toggles/power actions behave
    // the same as activate(); an app opens its Launch/Hide submenu instead
    // of launching straight away.
    function enter(item) {
        if (!item) return
        if (item.type === "app") {
            launcher.contextApp = item
            launcher.returnMode = launcher.mode
            launcher.mode = "appmenu"
            launcher.query = ""
            launcher.selectedIndex = 0
            return
        }
        launcher.activate(item)
    }

    IpcHandler {
        target: "launcher"
        function toggleApps() { launcher.toggleApps() }
        function toggleFull() { launcher.toggleFull() }
        function openApps() { launcher.openApps() }
        function openFull() { launcher.openFull() }
        function close() { launcher.close() }
    }

    onVisibleChanged: if (launcher.visible) input.forceActiveFocus()

    MouseArea {
        anchors.fill: parent
        onClicked: launcher.close()
    }

    Rectangle {
        id: box
        width: 600
        height: 525
        anchors.centerIn: parent
        color: Theme.background
        border.color: Theme.accent
        border.width: 1
        radius: 0

        // Swallows clicks so they don't fall through to the outer
        // click-to-close MouseArea.
        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10

            Row {
                width: parent.width
                height: 25
                spacing: 6

                Text {
                    visible: launcher.mode !== "root"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "<"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                    MouseArea { anchors.fill: parent; onClicked: launcher.goBack() }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: launcher.title
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 0
                color: Qt.rgba(0, 0, 0, 0.4)
                border.color: Qt.rgba(0.757, 0.008, 0.980, 0.5)
                border.width: 1

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                    text: launcher.query

                    onTextChanged: {
                        launcher.query = text
                        launcher.selectedIndex = 0
                    }
                    // Left/Right double as back/select, but only at the
                    // text cursor's boundary so moving the cursor while
                    // typing a query still works normally.
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Backspace && input.text.length === 0) {
                            launcher.goBack()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left && input.cursorPosition === 0) {
                            launcher.goBack()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Right && input.cursorPosition === input.text.length) {
                            launcher.enter(launcher.filtered[launcher.selectedIndex])
                            event.accepted = true
                        }
                    }
                    Keys.onEscapePressed: launcher.close()
                    Keys.onDownPressed: {
                        launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 1)
                        list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                    }
                    Keys.onUpPressed: {
                        launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1)
                        list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                    }
                    Keys.onReturnPressed: launcher.activate(launcher.filtered[launcher.selectedIndex])
                    Keys.onEnterPressed: launcher.activate(launcher.filtered[launcher.selectedIndex])
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 85
                clip: true
                model: launcher.filtered

                // Row-level MouseAreas below only handle press/hover/click,
                // so an unhandled wheel bubbles up to here instead of
                // falling through to the default Flickable content-drag —
                // scrolling moves the selection, same as the arrow keys.
                WheelHandler {
                    onWheel: (event) => {
                        if (event.angleDelta.y < 0) launcher.selectedIndex = Math.min(launcher.filtered.length - 1, launcher.selectedIndex + 1)
                        else launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1)
                        list.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
                    }
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 40
                    radius: 0
                    color: row.index === launcher.selectedIndex ? Qt.rgba(0.757, 0.008, 0.980, 0.25) : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 8
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Image {
                            visible: row.modelData.type === "app"
                            anchors.verticalCenter: parent.verticalCenter
                            source: row.modelData.type === "app" && row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            width: 25
                            height: 25
                            sourceSize: Qt.size(25, 25)
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.name
                            color: row.modelData.type === "power" && row.modelData.danger ? Theme.critical : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                        }
                    }

                    Text {
                        visible: row.modelData.type !== "toggle" && row.modelData.type !== "action"
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: ">"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                    }

                    Rectangle {
                        visible: row.modelData.type === "toggle"
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: 50
                        height: 22
                        radius: 0
                        color: row.modelData.type === "toggle" && row.modelData.active ? Theme.success : Qt.rgba(1, 1, 1, 0.1)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.type === "toggle" && row.modelData.active ? "On" : "Off"
                            color: row.modelData.type === "toggle" && row.modelData.active ? "#1c1c1c" : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.selectedIndex = row.index
                        onClicked: launcher.activate(row.modelData)
                    }
                }
            }
        }
    }
}
