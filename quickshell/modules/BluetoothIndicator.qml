import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth indicator and menu (BluetoothIndicator.qml).
// Hover (with 250ms initial delay, or immediate switch if another menu is already open)
// opens the device panel, staying open while hovered over the popup.
// Laid out like a phone's/GNOME's Bluetooth page: power switch, "Visible to
// nearby devices", My devices (click = connect, gear = details:
// auto-connect, forget), Available devices (searched for on open).
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
            if (root.isMine(a) !== root.isMine(b)) return root.isMine(a) ? -1 : 1
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

    // Opening the page searches by itself, like a phone's Bluetooth
    // settings. Still capped at 30s rather than for as long as it's open:
    // inquiry shares the radio, and connected headphones stutter during it.
    function startScan() {
        if (!root.adapter || !root.adapter.enabled || root.adapter.discovering) return
        root._scanStartedHere = true
        root.scanRemaining = 30
        root.adapter.pairable = true
        root.adapter.discovering = true
    }
    property bool _scanStartedHere: false
    function _syncAutoScan() {
        if (root.popupOpen && root.btEnabled) {
            root.startScan()
        } else if (!root.popupOpen) {
            if (root._scanStartedHere && root.isScanning) root.adapter.discovering = false
            root._scanStartedHere = false
            root.expandedDevice = ""
        }
    }
    onBtEnabledChanged: if (root.btEnabled) root._syncAutoScan()

    // Visible (discoverable): BlueZ turns it off by itself after
    // DiscoverableTimeout (180s here), so the row counts that down.
    readonly property bool visibleOn: !!(root.adapter && root.adapter.discoverable)
    property int visibleRemaining: 0
    onVisibleOnChanged: root.visibleRemaining = root.visibleOn && root.adapter ? root.adapter.discoverableTimeout : 0
    Timer {
        interval: 1000
        repeat: true
        running: root.visibleOn && root.visibleRemaining > 0
        onTriggered: root.visibleRemaining--
    }
    function setVisible(on) {
        if (!root.adapter) return
        // A phone pairing from its side is refused while Pairable is off.
        if (on) root.adapter.pairable = true
        root.adapter.discoverable = on
    }
    function clock(sec) { return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0") }

    // Address of the device whose details are open (one at a time).
    property string expandedDevice: ""

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
    onPopupOpenChanged: { _updateHoverState(); _syncAutoScan() }
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
    readonly property var pairedDevices: root.sortedDevices.filter(d => root.isMine(d))
    readonly property var otherDevices: root.sortedDevices.filter(d => !root.isMine(d)
        && !!d.name && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(d.name))

    // "My devices" = paired or trusted, as GNOME counts them. The GuliKit
    // (Xbox-mode) controller connects as trusted without ever bonding: BlueZ
    // reports it Paired only while connected, so a paired-only list dropped
    // it the moment it disconnected.
    function isMine(d) { return d.paired || d.bonded || d.trusted }
    function deviceGlyph(d) {
        const icon = d.icon || ""
        if (icon.startsWith("audio-headset") || icon.startsWith("audio-headphones")) return "\u{f02cb}"
        if (icon.startsWith("audio")) return "\u{f04c3}"
        if (icon === "input-mouse") return "\u{f037d}"
        if (icon === "input-keyboard") return "\u{f030c}"
        if (icon === "input-gaming") return "\u{f02b4}"
        if (icon === "phone") return "\u{f011c}"
        if (icon === "computer") return "\u{f0322}"
        if (icon === "input-tablet") return "\u{f04f7}"
        if (icon === "video-display") return "\u{f0379}"
        if (icon === "printer") return "\u{f042a}"
        if (icon.startsWith("camera")) return "\u{f0100}"
        return "\u{f00af}"
    }
    function typeName(d) {
        const icon = d.icon || ""
        if (icon.startsWith("audio-headset")) return "Headset"
        if (icon.startsWith("audio-headphones")) return "Headphones"
        if (icon.startsWith("audio")) return "Speaker"
        if (icon === "input-mouse") return "Mouse"
        if (icon === "input-keyboard") return "Keyboard"
        if (icon === "input-gaming") return "Game controller"
        if (icon === "input-tablet") return "Tablet"
        if (icon === "phone") return "Phone"
        if (icon === "computer") return "Computer"
        if (icon === "video-display") return "Display"
        if (icon === "printer") return "Printer"
        if (icon.startsWith("camera")) return "Camera"
        return "Device"
    }
    function statusFor(d) {
        if (d.pairing) return "Pairing…"
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…"
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (d.connected) return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "% battery" : "")
        // Unpaired (found by the search): what it is, so "JBL" vs "JBL" reads.
        if (root.isMine(d)) return "Not connected"
        const t = root.typeName(d)
        return t === "Device" ? "" : t
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
                        onToggled: ShellState.setBluetooth(!root.adapter.enabled)
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

                Column {
                    visible: !root.btEnabled
                    width: parent.width
                    spacing: 4
                    Text {
                        text: root.adapter ? "Bluetooth is off" : "No Bluetooth adapter"
                        color: Theme.text
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        visible: !!root.adapter
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Turn it on to use headphones, mice, keyboards, controllers and phones."
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                // This PC: visible to phones looking for it.
                SettingRow {
                    visible: root.btEnabled
                    width: parent.width
                    title: "Visible to nearby devices"
                    subtitle: !root.adapter ? ""
                        : root.visibleOn ? "As \u201c" + root.adapter.name + "\u201d"
                            + (root.visibleRemaining > 0 ? " · " + root.clock(root.visibleRemaining) + " left" : "")
                        : "Lets a phone find this PC as \u201c" + root.adapter.name + "\u201d"
                    checked: root.visibleOn
                    onToggled: root.setVisible(!root.visibleOn)
                }

                Column {
                    visible: root.btEnabled && root.pairedDevices.length > 0
                    width: parent.width
                    spacing: 2

                    SectionLabel { text: "My devices" }
                    Repeater {
                        model: root.pairedDevices
                        delegate: DeviceEntry {
                            required property var modelData
                            width: content.width
                            device: modelData
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
                            text: "Available devices"
                        }
                        Row {
                            visible: root.isScanning
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Spinner { anchors.verticalCenter: parent.verticalCenter; running: root.isScanning && panel.shown }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Searching"
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                        PromptButton {
                            visible: !root.isScanning
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Search again"
                            onClicked: root.startScan()
                        }
                    }
                    Repeater {
                        model: root.otherDevices
                        delegate: DeviceEntry {
                            required property var modelData
                            width: content.width
                            device: modelData
                        }
                    }
                    Text {
                        visible: root.otherDevices.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 4
                        text: root.isScanning ? "Put the device in pairing mode to see it here" : "No new devices found"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
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
        property bool danger: false
        signal clicked()
        width: pbText.implicitWidth + 20
        height: Theme.controlHeight - 2
        radius: Theme.controlRadius
        color: pb.danger ? Theme.danger
            : pb.primary ? (pbArea.containsMouse ? Theme.accentHover : Theme.accent)
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

    // Title + muted subtitle on the left, a switch on the right; the whole
    // row toggles.
    component SettingRow: Rectangle {
        id: sr
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        signal toggled()
        height: srText.implicitHeight + 16
        radius: Theme.controlRadius
        color: srArea.containsMouse ? Theme.hoverFill : "transparent"
        MouseArea {
            id: srArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sr.toggled()
        }
        Column {
            id: srText
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: srSwitch.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: sr.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: sr.subtitle
                elide: Text.ElideRight
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
        Switch {
            id: srSwitch
            anchors.right: parent.right
            anchors.rightMargin: 10
            checked: sr.checked
            onToggled: sr.toggled()
        }
    }

    // Small rotating arc for "Searching".
    component Spinner: Item {
        id: sp
        property bool running: false
        width: 12
        height: 12
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.track
        }
        Rectangle {
            width: 4
            height: 4
            radius: 2
            x: sp.width / 2 - 2
            y: 0
            color: Theme.accent
        }
        RotationAnimation on rotation {
            running: sp.running
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }

    // Device: icon, name, status (battery when it reports one); a click
    // connects (or pairs, or cancels pairing) -- on a connected one it opens
    // the details instead. Paired devices
    // have a gear for their details -- auto-connect, connect, forget --
    // instead of a bare trash can that one stray click used to fire.
    component DeviceEntry: Column {
        id: entry
        property var device: null
        readonly property bool expanded: !!entry.device && root.isMine(entry.device) && root.expandedDevice === entry.device.address
        readonly property bool busy: !!entry.device && (entry.device.pairing
            || entry.device.state === BluetoothDeviceState.Connecting
            || entry.device.state === BluetoothDeviceState.Disconnecting)
        // Forget asks once more; resets if not confirmed in a few seconds.
        property bool confirmForget: false
        onExpandedChanged: entry.confirmForget = false
        Timer { running: entry.confirmForget; interval: 4000; onTriggered: entry.confirmForget = false }
        spacing: 2

        Rectangle {
            id: row
            readonly property bool hovering: rowArea.containsMouse || gearArea.containsMouse
            width: parent.width
            height: Theme.controlHeight + 14
            radius: Theme.controlRadius
            color: entry.device && entry.device.connected ? Theme.selectedFill
                : row.hovering || entry.expanded ? Theme.hoverFill : "transparent"

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // A connected device's row opens its details rather than
                // disconnecting it -- a stray click used to drop headphones
                // mid-call. Disconnect is in the details.
                onClicked: {
                    if (entry.device.connected) root.expandedDevice = entry.expanded ? "" : entry.device.address
                    else root.activate(entry.device)
                }
            }

            Text {
                id: devGlyph
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                text: entry.device ? root.deviceGlyph(entry.device) : ""
                color: entry.device && entry.device.connected ? Theme.text : Theme.textMuted
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
                    text: entry.device ? (entry.device.name || entry.device.deviceName) : ""
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: !!entry.device && entry.device.connected
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    text: entry.device ? root.statusFor(entry.device) : ""
                    elide: Text.ElideRight
                    color: entry.device && entry.device.connected ? Theme.success : entry.busy ? Theme.accent : Theme.textMuted
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
                    visible: row.hovering || entry.busy
                    rightPadding: 4
                    text: !entry.device ? ""
                        : entry.device.pairing ? "Cancel"
                        : entry.device.connected || entry.busy ? ""
                        : root.isMine(entry.device) ? "Connect" : "Pair"
                    color: Theme.accent
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Rectangle {
                    visible: !!entry.device && root.isMine(entry.device)
                    width: Theme.controlHeight - 4
                    height: Theme.controlHeight - 4
                    radius: Theme.controlRadius
                    color: gearArea.containsMouse ? Theme.hoverFill : entry.expanded ? Theme.controlFill : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0493}" // nf-md-cog
                        color: gearArea.containsMouse || entry.expanded ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                    }
                    MouseArea {
                        id: gearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.expandedDevice = entry.expanded ? "" : entry.device.address
                    }
                }
            }
        }

        // Details
        Column {
            visible: entry.expanded
            width: parent.width
            leftPadding: 10
            rightPadding: 10
            topPadding: 4
            bottomPadding: 6
            spacing: 6

            Text {
                width: parent.width - 20
                elide: Text.ElideRight
                text: !entry.device ? "" : [root.typeName(entry.device), entry.device.address,
                    entry.device.batteryAvailable ? "Battery " + Math.round(entry.device.battery * 100) + "%" : ""]
                    .filter(t => t).join(" · ")
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
            // Trusted = BlueZ lets it connect (back) by itself.
            Item {
                width: parent.width - 20
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Connect automatically"
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Switch {
                    anchors.right: parent.right
                    checked: !!entry.device && entry.device.trusted
                    onToggled: entry.device.trusted = !entry.device.trusted
                }
            }
            Row {
                spacing: 6
                PromptButton {
                    label: !entry.device ? "" : entry.device.connected ? "Disconnect" : "Connect"
                    onClicked: root.activate(entry.device)
                }
                PromptButton {
                    label: entry.confirmForget ? "Forget for sure?" : "Forget"
                    danger: entry.confirmForget
                    onClicked: {
                        if (!entry.confirmForget) { entry.confirmForget = true; return }
                        root.expandedDevice = ""
                        entry.device.forget()
                    }
                }
            }
        }
    }
}
