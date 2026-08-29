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

    // Hyprland reloads its config live on save already (see install.sh) —
    // this is for forcing it manually. Quickshell has no equivalent "reload
    // config" IPC call, so "reload" for it means killing and respawning the
    // process, same as the SUPER+CTRL+SHIFT+R keybinding in keybindings.lua.
    readonly property var reloadItems: [
        { type: "reload", id: "hyprland", name: "Reload Hyprland", danger: false },
        { type: "reload", id: "quickshell", name: "Reload Quickshell", danger: false }
    ]

    readonly property var appItems: AppIndex.apps
        .filter(a => !HiddenApps.isHidden(a.name))
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal }))

    readonly property var hiddenItems: AppIndex.apps
        .filter(a => HiddenApps.isHidden(a.name))
        .map(a => ({ type: "app", name: a.name, exec: a.exec, icon: a.icon, terminal: a.terminal }))

    // Deliberately a curated allowlist, not every installed app — autostart
    // only makes sense for apps with a real "start minimized/to tray" flag
    // (checked against each app's own --help/docs; see autostart-launch.py).
    // Spotify/Bitwarden/Proton Pass were considered and left out: none of
    // them has a working CLI flag for it on Linux (Spotify dropped tray
    // support entirely; the other two only expose it as a GUI setting).
    readonly property var autostartCandidates: ["Telegram", "Element", "Vesktop", "Discord", "Steam"]

    readonly property var autostartItems: launcher.appItems
        .filter(a => launcher.autostartCandidates.includes(a.name))
        .map(a => ({ type: "autostart-app", name: a.name, exec: a.exec, icon: a.icon,
                     terminal: a.terminal, active: AutostartApps.isEnabled(a.name) }))

    readonly property var appMenuItems: {
        if (!launcher.contextApp) return []
        const hidden = HiddenApps.isHidden(launcher.contextApp.name)
        return [
            { type: "action", id: "launch", name: "Launch" },
            { type: "action", id: hidden ? "unhide" : "hide", name: hidden ? "Unhide" : "Hide" }
        ]
    }

    // Icons are Nerd Font glyphs (Font Awesome set), not .desktop icons —
    // these aren't real installed apps, so there's nothing for
    // Quickshell.iconPath to resolve.
    readonly property var rootItems: [
        { type: "folder", id: "apps", name: "Apps", icon: "" },
        { type: "folder", id: "toggles", name: "Toggles", icon: "" },
        { type: "folder", id: "power", name: "Power", icon: "" },
        { type: "folder", id: "hidden", name: "Hidden", icon: "" },
        { type: "folder", id: "autostart", name: "Autostart", icon: "" },
        { type: "folder", id: "reload", name: "Reload", icon: "" },
        { type: "info", id: "info", name: "Info", icon: "" }
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
        if (launcher.mode === "autostart") return launcher.autostartItems
        if (launcher.mode === "reload") return launcher.reloadItems
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
        : launcher.mode === "autostart" ? "Autostart"
        : launcher.mode === "reload" ? "Reload"
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
        if (item.type === "autostart-app") {
            AutostartApps.toggle(item.name)
            return
        }
        if (item.type === "info") {
            launcher.close()
            // --hold: fastfetch prints once and exits immediately, which
            // would otherwise close the window right away. --class +
            // window_rules.lua's float-center-info rule float/center/size
            // it the same way wlctl's window is (see NetworkIndicator.qml).
            Quickshell.execDetached(["kitty", "--hold", "--class", "sichos-info", "-e", "fastfetch"])
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
        if (item.type === "reload") {
            launcher.close()
            const commands = {
                // A plain hyprctl subcommand, not hl.dsp.exec_cmd/dispatch —
                // see window_rules.lua's Firefox PiP rule notes on why
                // dispatcher args need Lua-shaped syntax on this build;
                // `hyprctl reload` itself isn't a dispatcher call at all.
                hyprland: ["hyprctl", "reload"],
                // Same command as keybindings.lua's SUPER+CTRL+SHIFT+R.
                quickshell: ["sh", "-c", "pkill quickshell; quickshell & disown"]
            }
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

    onVisibleChanged: if (launcher.visible) {
        input.forceActiveFocus()
        AppIndex.refresh()
    }

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
        border.width: 4
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
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                    MouseArea { anchors.fill: parent; onClicked: launcher.goBack() }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "[ " + launcher.title + " ]"
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

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "❯"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                }

                TextInput {
                    id: input
                    anchors.left: prompt.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
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
                height: parent.height - 115
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
                    // "toggle" (idle/wifi/bluetooth) and "autostart-app" both
                    // render as an On/Off pill instead of the ">" submenu arrow.
                    readonly property bool isToggleLike: row.modelData.type === "toggle" || row.modelData.type === "autostart-app"
                    width: list.width
                    height: 40
                    radius: 0
                    color: row.index === launcher.selectedIndex ? Qt.rgba(0.757, 0.008, 0.980, 0.16) : "transparent"

                    Rectangle {
                        visible: row.index === launcher.selectedIndex
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: Theme.accent
                    }

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 8
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            text: row.index === launcher.selectedIndex ? "❯" : ""
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                        }

                        Image {
                            readonly property bool hasRealIcon: row.modelData.type === "app" || row.modelData.type === "autostart-app"
                            visible: hasRealIcon
                            anchors.verticalCenter: parent.verticalCenter
                            source: hasRealIcon && row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            width: 25
                            height: 25
                            sourceSize: Qt.size(25, 25)
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            visible: row.modelData.type !== "app" && row.modelData.type !== "autostart-app" && !!row.modelData.icon
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            horizontalAlignment: Text.AlignHCenter
                            text: row.modelData.icon || ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 16
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
                        visible: !row.isToggleLike && row.modelData.type !== "action"
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: ">"
                        color: row.index === launcher.selectedIndex ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                    }

                    Rectangle {
                        visible: row.isToggleLike
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: 50
                        height: 22
                        radius: 0
                        color: row.isToggleLike && row.modelData.active ? Theme.success : Qt.rgba(1, 1, 1, 0.1)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: row.isToggleLike && row.modelData.active ? "On" : "Off"
                            color: row.isToggleLike && row.modelData.active ? "#1c1c1c" : Theme.textMuted
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

            Text {
                width: parent.width
                height: 20
                text: "↑↓ move  ❯ select  esc back"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
