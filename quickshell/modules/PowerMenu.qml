import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

// Power menu, opened by the laptop's power key (XF86PowerOff in
// keybindings.lua) or `quickshell ipc call power toggle`. logind would
// otherwise power off on that key by itself (HandlePowerKey=poweroff is
// its default); autostart.lua holds a handle-power-key inhibitor for the
// session so the key reaches Hyprland instead, the way GNOME's own power
// dialog works.
//
// Log Out/Reboot/Shut Down don't hand off to hyprshutdown any more: its
// UI is fixed hyprtoolkit widgets (a bare text list of every client
// *process*, bar and wallpaper included) that no theme can make match
// this shell. The same graceful close happens here instead, in two stages:
//   1. a `countdownFrom`-second countdown listing the open apps. Nothing is
//      touched yet, so Esc/Cancel really undoes it; "now" skips the wait.
//   2. every window gets a normal close request and the card lists what's
//      still open (live, rows fading out); the real logout/reboot/poweroff
//      runs once the list is empty, or on "Don't wait" (hyprshutdown's
//      "Force quit"). Apps asking about unsaved work stay listed until
//      answered -- no timeout here, same as hyprshutdown.
// The first version ran the countdown *alongside* the closing and went on
// as soon as the list emptied: terminals close instantly, so it shut down
// with no chance to cancel. hyprshutdown itself is still the keybinding's
// fallback when quickshell isn't running.
PanelWindow {
    id: menu
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"
    WlrLayershell.layer: WlrLayer.Overlay

    screen: Quickshell.screens[0]
    visible: false
    focusable: true

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    // Always dimmed, unlike the launcher: this is a modal "about to leave
    // the session" screen, not something to glance past.
    color: Theme.backdrop

    // `final` runs once every window is gone. Reboot/poweroff go straight to
    // systemctl rather than exiting Hyprland first (hyprshutdown's order):
    // nothing in hypr/*.lua hooks Hyprland's exit, and quickshell -- a child
    // of Hyprland -- couldn't run anything after that exit anyway.
    readonly property var actions: [
        { id: "lock",     name: "Lock",      glyph: "\u{f033e}", command: ["hyprlock"] },
        { id: "suspend",  name: "Suspend",   glyph: "\u{f04b2}", command: ["systemctl", "suspend"] },
        { id: "logout",   name: "Log Out",   glyph: "\u{f0343}", progress: "Logging out", now: "Log out now",
          final: ["hyprctl", "eval", "hl.dispatch(hl.dsp.exit())"] },
        { id: "reboot",   name: "Reboot",    glyph: "\u{f0709}", progress: "Restarting", now: "Restart now",
          final: ["systemctl", "reboot"], danger: true },
        { id: "shutdown", name: "Shut Down", glyph: "\u{f0425}", progress: "Shutting down", now: "Shut down now",
          final: ["systemctl", "poweroff"], danger: true }
    ]
    property int selectedIndex: 0
    // Set from picking logout/reboot/shutdown until it runs or is cancelled;
    // the card shows the app list instead of the tiles.
    property var closing: null
    // Stage 2 (see header): set when the countdown ends, close requests go
    // out on the next poll (closeSent).
    property bool closeRequested: false
    property bool closeSent: false
    readonly property int countdownFrom: 3
    property int countdown: countdownFrom
    property bool finishing: false

    function activeScreen() {
        const mon = Hyprland.focusedMonitor
        if (mon) {
            for (const s of Quickshell.screens) {
                if (s.name === mon.name) return s
            }
        }
        return Quickshell.screens[0]
    }
    function open() {
        if (menu.closing) return
        menu.screen = menu.activeScreen()
        // Starts on Shut Down: pressing the power key most often means
        // exactly that, so it's one Enter away (still never automatic).
        menu.selectedIndex = menu.actions.length - 1
        menu.visible = true
    }
    function close() {
        // Mid-shutdown only Cancel/"now" leave the screen -- a stray click
        // or power-key press mustn't hide a half-closed session.
        if (menu.closing) return
        menu.visible = false
    }
    function toggle() {
        if (menu.visible) menu.close()
        else menu.open()
    }
    function run(action) {
        if (!action) return
        if (!action.final) {
            menu.close()
            Quickshell.execDetached(action.command)
            return
        }
        if (!menu.visible) {
            menu.screen = menu.activeScreen()
            menu.visible = true
        }
        windowModel.clear()
        menu.closeRequested = false
        menu.closeSent = false
        menu.finishing = false
        menu.countdown = menu.countdownFrom
        menu.closing = action
        clientsProc.running = true
    }
    function cancel() {
        menu.closing = null
        menu.finishing = false
        menu.visible = false
    }
    // Ends stage 1 early or on time; never runs the final command itself.
    function startClosing() {
        if (!menu.closing || menu.closeRequested) return
        menu.closeRequested = true
        if (!clientsProc.running) clientsProc.running = true
    }
    // The "now" button / Enter: skip whichever wait is in progress.
    function advance() {
        if (menu.closeRequested) menu.finish()
        else menu.startClosing()
    }
    function finish() {
        const action = menu.closing
        if (!action || menu.finishing) return
        menu.finishing = true
        // Stays up (and `closing` stays set) until the session actually goes.
        Quickshell.execDetached(action.final)
    }

    IpcHandler {
        target: "power"
        function toggle() { menu.toggle() }
        function open() { menu.open() }
        function close() { menu.close() }
        // The launcher's Power folder routes through here, so both menus
        // close apps the same way.
        function run(id: string) { menu.run(menu.actions.find(a => a.id === id)) }
    }

    // Live window list while closing. A ListModel synced by address (not a
    // plain array) so rows animate out individually as their apps close.
    ListModel { id: windowModel }
    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!menu.closing) return
                let clients = []
                try { clients = JSON.parse(text).filter(c => c.mapped) } catch (e) { return }
                const live = new Set(clients.map(c => c.address))
                for (let i = windowModel.count - 1; i >= 0; i--) {
                    if (!live.has(windowModel.get(i).address)) windowModel.remove(i)
                }
                const shown = new Set()
                for (let i = 0; i < windowModel.count; i++) shown.add(windowModel.get(i).address)
                for (const c of clients) {
                    if (!shown.has(c.address))
                        windowModel.append({ address: c.address, cls: c.class || c.initialClass || "", title: c.title || "" })
                }
                // One close request per window, sent once: an app showing an
                // "unsaved changes?" dialog has answered already, re-asking
                // would just stack dialogs. Windows that appear afterwards
                // (those dialogs) are listed but left alone.
                if (menu.closeRequested && !menu.closeSent) {
                    menu.closeSent = true
                    if (clients.length) {
                        Quickshell.execDetached(["hyprctl", "eval", clients.map(c =>
                            "hl.dispatch(hl.dsp.window.close({ window = " + JSON.stringify("address:" + c.address) + " }))").join("\n")])
                    }
                }
                if (menu.closeSent && !clients.length) menu.finish()
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: menu.closing !== null && !menu.closeRequested
        onTriggered: {
            menu.countdown--
            if (menu.countdown <= 0) menu.startClosing()
        }
    }
    Timer {
        interval: 400
        repeat: true
        running: menu.closing !== null && menu.visible
        onTriggered: if (!clientsProc.running) clientsProc.running = true
    }

    onVisibleChanged: if (menu.visible) keys.forceActiveFocus()

    Item {
        id: keys
        focus: true
        Keys.onPressed: (event) => {
            const n = menu.actions.length
            if (menu.closing) {
                if (event.key === Qt.Key_Escape) menu.cancel()
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) menu.advance()
                else return
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
                menu.selectedIndex = (menu.selectedIndex + n - 1) % n
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
                menu.selectedIndex = (menu.selectedIndex + 1) % n
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                menu.run(menu.actions[menu.selectedIndex])
            else if (event.key === Qt.Key_Escape)
                menu.close()
            else return
            event.accepted = true
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
    }

    // See Launcher.qml's shadow for why it's solid-cards-only.
    RectangularShadow {
        visible: !Theme.glassOn(menu.screen)
        anchors.fill: card
        radius: card.radius
        offset.y: Theme.surfaceShadowOffset
        blur: Theme.surfaceShadowBlur
        color: Theme.surfaceShadow
        opacity: card.opacity
        scale: card.scale
        transformOrigin: card.transformOrigin
    }

    Rectangle {
        id: card
        SurfaceAppear { target: card; shown: menu.visible; origin: Item.Center }
        anchors.centerIn: parent
        width: (menu.closing ? closingContent : content).width + 2 * Theme.surfacePadding
        height: (menu.closing ? closingContent : content).height + 2 * Theme.surfacePadding
        color: Theme.surfaceFor(menu.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        MouseArea { anchors.fill: parent }

        Column {
            id: content
            visible: !menu.closing
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            Row {
                spacing: 8
                HeaderIcon { glyph: "\u{f0425}" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Power"
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

            Row {
                spacing: 8

                Repeater {
                    model: menu.actions

                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool selected: tile.index === menu.selectedIndex
                        width: 92
                        height: 92
                        radius: Theme.controlRadius
                        color: tile.selected ? Theme.hoverFill : Theme.controlFill
                        border.color: tile.selected ? Theme.accent : "transparent"
                        border.width: 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            HeaderIcon {
                                anchors.verticalCenter: undefined
                                anchors.horizontalCenter: parent.horizontalCenter
                                glyph: tile.modelData.glyph
                                inkHeight: 28
                                inkWidth: 30
                                color: tile.modelData.danger ? Theme.critical : tile.selected ? Theme.text : Theme.textMuted
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.name
                                color: Theme.text
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: menu.selectedIndex = tile.index
                            onClicked: menu.run(tile.modelData)
                        }
                    }
                }
            }

            Text {
                text: "←→ move  ❯ select  esc close"
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        Column {
            id: closingContent
            visible: !!menu.closing
            anchors.centerIn: parent
            width: 400
            spacing: Theme.sectionSpacing

            Row {
                spacing: 8
                HeaderIcon { glyph: menu.closing ? menu.closing.glyph : "\u{f0425}" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.closing ? menu.closing.progress + "…" : ""
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                readonly property string apps: windowModel.count + (windowModel.count === 1 ? " open app" : " open apps")
                text: !menu.closing ? ""
                    : !menu.closeRequested
                    ? menu.closing.progress + " in " + menu.countdown + (menu.countdown === 1 ? " second" : " seconds")
                      + (windowModel.count ? ", closing " + apps + " first." : ".") + " Esc to cancel."
                    : windowModel.count
                    ? "Waiting for " + apps + " to close. Apps with unsaved work may ask first."
                    : "All apps closed."
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Rectangle {
                width: parent.width
                height: Math.min(windowList.contentHeight, 6 * 44) + 8
                visible: windowModel.count > 0
                radius: Theme.controlRadius
                color: Theme.controlFill
                clip: true

                ListView {
                    id: windowList
                    anchors.fill: parent
                    anchors.margins: 4
                    model: windowModel
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: Theme.openDuration }
                    }
                    displaced: Transition {
                        NumberAnimation { property: "y"; duration: Theme.openDuration; easing.type: Easing.OutCubic }
                    }

                    delegate: Item {
                        id: winRow
                        required property string cls
                        required property string title
                        readonly property string appName: DesktopIcons.nameForClass(winRow.cls)
                        width: windowList.width
                        height: 44

                        Image {
                            id: winIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            sourceSize: Qt.size(52, 52)
                            fillMode: Image.PreserveAspectFit
                            source: DesktopIcons.iconPathForClass(winRow.cls)
                            asynchronous: true
                        }

                        Column {
                            anchors {
                                left: winIcon.right
                                leftMargin: 10
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: winRow.appName
                                color: Theme.text
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                width: parent.width
                                visible: text.length > 0 && text !== winRow.appName
                                elide: Text.ElideRight
                                text: winRow.title
                                color: Theme.textDim
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Repeater {
                    model: [
                        { label: "Cancel", primary: false },
                        { label: !menu.closing ? "" : menu.closeRequested ? "Don't wait" : menu.closing.now, primary: true }
                    ]

                    Rectangle {
                        id: button
                        required property var modelData
                        width: buttonLabel.implicitWidth + 28
                        height: Theme.controlHeight + 4
                        radius: Theme.controlRadius
                        color: buttonMouse.containsMouse
                            ? (button.modelData.primary ? Theme.selectedFill : Theme.hoverFill)
                            : (button.modelData.primary ? Theme.hoverFill : Theme.controlFill)
                        border.color: button.modelData.primary ? Theme.accent : "transparent"
                        border.width: 1

                        Text {
                            id: buttonLabel
                            anchors.centerIn: parent
                            text: button.modelData.label
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }

                        MouseArea {
                            id: buttonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: button.modelData.primary ? menu.advance() : menu.cancel()
                        }
                    }
                }
            }

        }
    }
}
