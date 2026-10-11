import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Shared shell for the clipboard (ClipboardPicker.qml) and emoji
// (EmojiPicker.qml) pickers: the launcher's card, title and search field,
// with each picker's own list as the body. Kept out of Launcher.qml on
// purpose -- these are one-shot "pick a thing and get out" windows with
// nothing to browse. They replaced fuzzel --dmenu pickers, which could only
// approximate the Theme tokens, couldn't draw Fedora's COLRv1 Noto Color
// Emoji (fcft skips it -- every emoji was a box), and showed clipboard
// images as "[[ binary data ]]" lines.
PanelWindow {
    id: win
    // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
    WlrLayershell.namespace: "sichos-glass"

    default property alias body: bodyArea.data
    property alias footer: footerArea.data
    property string title: ""
    property string placeholder: ""
    property int cardWidth: 600
    property int cardHeight: 640
    property string query: ""
    readonly property Item searchInput: input

    // Every key the search field gets goes here first; a picker sets
    // event.accepted to take it (navigation), otherwise Escape closes,
    // Return/Enter emits accepted() and the rest is typing.
    signal keyPressed(var event)
    signal accepted()
    signal opened()

    screen: Quickshell.screens[0]
    visible: false
    focusable: true

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Same "only dim over windows" rule as Launcher.qml.
    readonly property var hyprMonitor: {
        const list = Hyprland.monitors.values
        for (const m of list) if (m.name === win.screen.name) return m
        return null
    }
    property int windowEpoch: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow"
                || event.name === "movewindow" || event.name === "movewindowv2")
                win.windowEpoch++
        }
    }
    readonly property bool activeWorkspaceHasWindows: {
        const epoch = win.windowEpoch
        if (!win.hyprMonitor || !win.hyprMonitor.activeWorkspace) return false
        const wsId = win.hyprMonitor.activeWorkspace.id
        return Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === wsId)
    }
    color: win.activeWorkspaceHasWindows ? Theme.backdrop : "transparent"

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
        win.screen = win.activeScreen()
        input.text = ""
        win.query = ""
        win.visible = true
        win.opened()
    }
    function close() {
        win.visible = false
    }
    function toggle() {
        if (win.visible) win.close()
        else win.open()
    }

    onVisibleChanged: if (win.visible) input.forceActiveFocus()

    MouseArea {
        anchors.fill: parent
        onClicked: win.close()
    }

    // See Launcher.qml's shadow for why it's solid-cards-only.
    RectangularShadow {
        visible: !Theme.glassOn(win.screen)
        anchors.fill: box
        radius: box.radius
        offset.y: Theme.surfaceShadowOffset
        blur: Theme.surfaceShadowBlur
        color: Theme.surfaceShadow
        opacity: box.opacity
        scale: box.scale
        transformOrigin: box.transformOrigin
    }

    Rectangle {
        id: box
        SurfaceAppear { target: box; shown: win.visible; origin: Item.Center }
        width: win.cardWidth
        height: win.cardHeight
        anchors.centerIn: parent
        color: Theme.surfaceFor(win.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.surfacePadding
            spacing: Theme.sectionSpacing

            Text {
                id: titleText
                width: parent.width
                height: 25
                verticalAlignment: Text.AlignVCenter
                text: win.title
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Rectangle {
                id: searchBox
                width: parent.width
                height: 40
                radius: Theme.controlRadius
                color: Theme.controlFill
                border.color: Theme.accent
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

                Text {
                    visible: input.text.length === 0
                    anchors.left: input.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.placeholder
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize + 3
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

                    onTextChanged: win.query = text
                    Keys.onPressed: (event) => {
                        win.keyPressed(event)
                        if (event.accepted) return
                        if (event.key === Qt.Key_Escape) {
                            win.close()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.accepted()
                            event.accepted = true
                        }
                    }
                }
            }

            Item {
                id: bodyArea
                width: parent.width
                height: parent.height - titleText.height - searchBox.height - footerArea.height - 3 * parent.spacing
            }

            Item {
                id: footerArea
                width: parent.width
                height: 20
            }
        }
    }
}
