import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth indicator and menu (BluetoothIndicator.qml).
// Hover (with 250ms initial delay, or immediate switch if another menu is already open)
// opens the device panel, staying open while hovered over the popup.
// Bluetooth scan runs for a maximum of 30 seconds with a visible countdown timer.
Pill {
    id: root
    property string screenName: ""

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btEnabled: root.adapter && root.adapter.enabled
    readonly property var connectedDevices: root.adapter
        ? root.adapter.devices.values.filter(d => d.connected)
        : []
    // Paired devices (the ones actually worth reconnecting to) first, then
    // connected before merely-paired, then alphabetical — so a scan's
    // unpaired results land at the bottom instead of shuffling the list
    // you actually care about.
    readonly property var sortedDevices: root.adapter
        ? root.adapter.devices.values.slice().sort((a, b) => {
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return a.name.localeCompare(b.name)
          })
        : []

    // --- 30-Second Scan Timer ---
    readonly property bool isScanning: Boolean(root.adapter && root.adapter.discovering)
    property int scanRemaining: 30

    onIsScanningChanged: {
        if (root.isScanning) {
            root.scanRemaining = 30
        }
    }

    Timer {
        id: scanCountdownTimer
        interval: 1000
        repeat: true
        running: root.isScanning
        onTriggered: {
            if (root.scanRemaining > 1) {
                root.scanRemaining--
            } else {
                root.scanRemaining = 30
                if (root.adapter) root.adapter.discovering = false
            }
        }
    }

    function toggleScan() {
        if (!root.adapter) return
        if (root.adapter.discovering) {
            root.adapter.discovering = false
            root.scanRemaining = 30
        } else {
            root.scanRemaining = 30
            // BlueZ starts with Pairable off here; a phone pairing from its
            // side is refused unless this is on.
            root.adapter.pairable = true
            root.adapter.discovering = true
        }
    }

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    // QuickSettings.qml embeds a hidden instance of this as a submenu of its
    // own card: it sets a distinct popupId (so it never opens together with
    // a standalone instance on the same screen), anchors the popup to its
    // own pill, and names the popup the header's back arrow returns to.
    property string popupId: "bluetooth"
    property Item popupAnchor: root
    property string backPopupId: ""
    // false inside the Control Center, which closes only on a click outside.
    property bool closeOnLeave: true
    property real popupWidth: 280
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool popupHovered: popupHoverHandler.hovered

    Timer {
        id: openDelayTimer
        interval: 250
        onTriggered: {
            if (root.hovered) {
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            }
        }
    }

    Timer {
        id: closeDelayTimer
        interval: 300
        onTriggered: {
            if (!root.hovered && !root.popupHovered) {
                if (ShellState.activePopup === root.popupId) {
                    ShellState.activePopup = ""
                }
            }
        }
    }

    function _updateHoverState() {
        if (root.hovered) {
            closeDelayTimer.stop()
            if (ShellState.activePopup !== "" && !root.popupOpen) {
                openDelayTimer.stop()
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            } else if (ShellState.activePopup === "" && !openDelayTimer.running) {
                openDelayTimer.start()
            }
        } else if (root.popupHovered) {
            closeDelayTimer.stop()
            openDelayTimer.stop()
        } else {
            openDelayTimer.stop()
            if (root.popupOpen && root.closeOnLeave && !closeDelayTimer.running) {
                closeDelayTimer.start()
            }
        }
    }

    onHoveredChanged: _updateHoverState()
    // An embedded (QuickSettings) instance opens by a click inside the card
    // with no pill of its own to hover, so arm the close check on open too.
    onPopupOpenChanged: _updateHoverState()
    onPopupHoveredChanged: _updateHoverState()

    BarIcon {
        glyph: ""
        // Ink 802/1000em (fontTools glyf bbox) -- scaled to the shared bar
        // icon target (previously a flat Theme.fontSize plus a one-off
        // fixed width to paper over the resulting hitbox misalignment; both
        // are now handled generically by BarIcon.qml).
        pixelSize: Theme.barIconInkHeight * 1000 / 802
        color: !root.btEnabled ? Theme.critical
            : root.connectedDevices.length > 0 ? Theme.accent : Theme.text
    }

    // Paired devices are "My devices"; everything else found by a scan is
    // "Other devices", minus the many that only advertise an address.
    readonly property var pairedDevices: root.sortedDevices.filter(d => d.paired)
    readonly property var otherDevices: root.sortedDevices.filter(d => !d.paired
        && !!d.name && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(d.name))

    function deviceGlyph(d) {
        const icon = d.icon || ""
        if (icon.startsWith("audio-headset") || icon.startsWith("audio-headphones")) return "\u{f02cb}"
        if (icon.startsWith("audio")) return "\u{f04c3}"
        if (icon === "input-mouse") return "\u{f037d}"
        if (icon === "input-keyboard") return "\u{f030c}"
        if (icon === "input-gaming") return "\u{f02b4}"
        if (icon === "phone") return "\u{f011c}"
        if (icon === "computer") return "\u{f0322}"
        return "\u{f00af}"
    }
    function statusFor(d) {
        if (d.pairing) return "Pairing…"
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…"
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (d.connected) return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "% battery" : "")
        return d.paired ? "Not connected" : ""
    }
    // connect() rather than pair() for a new device: pair() alone doesn't
    // bring up a profile afterward, so BlueZ drops the link as unused within
    // a couple of seconds (reproduced live); connect() pairs (through
    // BluetoothAgent for anything that shows or asks for a code) and
    // connects in one go, and the agent marks it trusted so it reconnects.
    function activate(d) {
        if (d.pairing) d.cancelPair()
        else if (d.connected) d.disconnect()
        else d.connect()
    }

    // Set by Bar.qml: the bar's MorphPopup card (see MorphContent.qml).
    property Item popupHost: null
    readonly property Item _popupContent: MorphContent {
        id: panel
        parent: root.popupHost
        anchorItem: root.popupAnchor
        shown: root.popupOpen

        implicitWidth: root.popupWidth
        implicitHeight: bg.implicitHeight

        readonly property var request: BluetoothAgent.request
        readonly property var display: BluetoothAgent.display
        readonly property bool typing: !!panel.request && (panel.request.type === "pin" || panel.request.type === "passkey")

        // PIN entry has no TextInput (a popup never gets keyboard focus): the
        // bar forwards keys here while it's up -- see ShellState.keySink.
        function handleKey(event) {
            if (event.key === Qt.Key_Escape) BluetoothAgent.answer("no")
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (BluetoothAgent.typed.length > 0) BluetoothAgent.answer(BluetoothAgent.typed)
            } else if (event.key === Qt.Key_Backspace) BluetoothAgent.typed = BluetoothAgent.typed.slice(0, -1)
            else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32
                     && (panel.request.type === "pin" || /[0-9]/.test(event.text)))
                BluetoothAgent.typed += event.text
        }
        readonly property bool wantsKeys: panel.shown && panel.typing
        onWantsKeysChanged: {
            if (panel.wantsKeys) {
                ShellState.keySinkScreen = root.screenName
                ShellState.keySink = panel
            } else if (ShellState.keySink === panel) {
                ShellState.keySink = null
            }
        }

        Item {
            id: bg
            implicitWidth: root.popupWidth
            implicitHeight: content.implicitHeight + 2 * Theme.surfacePadding

            HoverHandler {
                id: popupHoverHandler
            }

            Column {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Theme.surfacePadding
                }
                spacing: Theme.sectionSpacing

                // Header
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        BackButton {
                            visible: root.backPopupId !== ""
                            onClicked: ShellState.activePopup = root.backPopupId
                        }
                        HeaderIcon {
                            glyph: "\uf293" // nf-fa-bluetooth
                            color: Theme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Bluetooth"
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }
                    Switch {
                        anchors.right: parent.right
                        visible: !!root.adapter
                        checked: root.btEnabled
                        onToggled: root.adapter.enabled = !root.adapter.enabled
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.separator
                }

                // Pairing prompt from BluetoothAgent
                Rectangle {
                    visible: !!panel.request || !!panel.display
                    width: parent.width
                    height: promptColumn.implicitHeight + 24
                    radius: Theme.controlRadius
                    color: Theme.selectedFill
                    border.color: Theme.accent
                    border.width: 1

                    Column {
                        id: promptColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: {
                                const r = panel.request || panel.display
                                if (!r) return ""
                                switch (r.type) {
                                case "confirm": return "Pair with " + r.name + "?"
                                case "authorize": return "Allow " + r.name + " to connect?"
                                case "pin": return "Enter the PIN for " + r.name
                                case "passkey": return "Enter the passkey shown on " + r.name
                                default: return "Type this code on " + r.name + ", then press Enter there"
                                }
                            }
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                        Text {
                            visible: !!(panel.request ? panel.request.passkey : panel.display)
                            text: panel.request ? (panel.request.passkey || "") : panel.display ? panel.display.passkey : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 10
                            font.letterSpacing: 4
                        }
                        Text {
                            visible: !!panel.request && panel.request.type === "confirm"
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Make sure the same code is shown on the device."
                            color: Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        // Typed PIN/passkey (keys come through the bar).
                        Rectangle {
                            visible: panel.typing
                            width: parent.width
                            height: Theme.controlHeight + 4
                            radius: Theme.controlRadius
                            color: Theme.controlFill
                            border.width: 1
                            border.color: Theme.accent
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: BluetoothAgent.typed.length > 0 ? BluetoothAgent.typed : "Type, then Enter"
                                color: BluetoothAgent.typed.length > 0 ? Theme.text : Theme.textDim
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 6
                            PromptButton {
                                label: panel.display && !panel.request ? "Dismiss" : "Cancel"
                                onClicked: {
                                    if (panel.request) BluetoothAgent.answer("no")
                                    else BluetoothAgent.clearDisplay()
                                }
                            }
                            PromptButton {
                                visible: !!panel.request
                                primary: true
                                label: panel.request && panel.request.type === "authorize" ? "Allow" : "Pair"
                                onClicked: BluetoothAgent.answer(panel.typing ? BluetoothAgent.typed : "yes")
                            }
                        }
                    }
                }

                Text {
                    visible: !root.btEnabled
                    text: root.adapter ? "Bluetooth is off" : "No Bluetooth adapter"
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Column {
                    visible: root.btEnabled && root.pairedDevices.length > 0
                    width: parent.width
                    spacing: 2

                    SectionLabel { text: "My devices" }
                    Repeater {
                        model: root.pairedDevices
                        delegate: DeviceRow {
                            required property var modelData
                            width: content.width
                            device: modelData
                            glyph: root.deviceGlyph(modelData)
                            status: root.statusFor(modelData)
                            onActivated: root.activate(modelData)
                            onForget: modelData.forget()
                        }
                    }
                }

                Column {
                    visible: root.btEnabled
                    width: parent.width
                    spacing: 2

                    Item {
                        width: parent.width
                        height: Theme.controlHeight
                        SectionLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isScanning ? "Searching… (" + root.scanRemaining + "s)" : "Other devices"
                        }
                        PromptButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: root.isScanning ? "Stop" : "Scan"
                            onClicked: root.toggleScan()
                        }
                    }
                    Repeater {
                        model: root.otherDevices
                        delegate: DeviceRow {
                            required property var modelData
                            width: content.width
                            device: modelData
                            glyph: root.deviceGlyph(modelData)
                            status: root.statusFor(modelData)
                            onActivated: root.activate(modelData)
                        }
                    }
                    Text {
                        visible: root.otherDevices.length === 0
                        topPadding: 4
                        text: root.isScanning ? "Looking for devices…" : "Scan to find new devices"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }
        }
    }

    component SectionLabel: Text {
        color: Theme.textMuted
        font.family: Theme.uiFontFamily
        font.pixelSize: Theme.fontSize - 2
        bottomPadding: 2
    }

    component PromptButton: Rectangle {
        id: pb
        property string label: ""
        property bool primary: false
        signal clicked()
        width: pbText.implicitWidth + 20
        height: Theme.controlHeight - 2
        radius: Theme.controlRadius
        color: pb.primary ? (pbArea.containsMouse ? Theme.accentHover : Theme.accent)
            : pbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.label
            color: pb.primary ? Theme.textOnLight : Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: pb.primary
        }
        MouseArea {
            id: pbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    // Device row: type icon, name, status (battery when it reports one);
    // clicking connects/disconnects (or cancels pairing). Paired devices get
    // a forget button on hover.
    component DeviceRow: Rectangle {
        id: row
        property var device: null
        property string glyph: ""
        property string status: ""
        signal activated()
        signal forget()

        readonly property bool busy: !!row.device && (row.device.pairing
            || row.device.state === BluetoothDeviceState.Connecting
            || row.device.state === BluetoothDeviceState.Disconnecting)
        readonly property bool hovering: rowArea.containsMouse || forgetArea.containsMouse

        height: Theme.controlHeight + 14
        radius: Theme.controlRadius
        color: row.device && row.device.connected ? Theme.selectedFill
            : row.hovering ? Theme.hoverFill : "transparent"

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.activated()
        }

        Text {
            id: devGlyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: row.glyph
            color: row.device && row.device.connected ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 5
        }
        Column {
            anchors.left: devGlyph.right
            anchors.leftMargin: 8
            anchors.right: rowActions.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: row.device ? (row.device.name || row.device.deviceName) : ""
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: !!row.device && row.device.connected
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: row.status
                elide: Text.ElideRight
                color: row.device && row.device.connected ? Theme.success : row.busy ? Theme.accent : Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
        Row {
            id: rowActions
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.hovering || row.busy
                rightPadding: 4
                text: !row.device ? ""
                    : row.device.pairing ? "Cancel"
                    : row.device.connected ? "Disconnect"
                    : row.busy ? ""
                    : row.device.paired ? "Connect" : "Pair"
                color: Theme.accent
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
            Rectangle {
                visible: !!row.device && row.device.paired && row.hovering
                width: Theme.controlHeight - 4
                height: Theme.controlHeight - 4
                radius: Theme.controlRadius
                color: forgetArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0a7a}" // nf-md-trash_can_outline
                    color: forgetArea.containsMouse ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    id: forgetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.forget()
                }
            }
        }
    }
}
