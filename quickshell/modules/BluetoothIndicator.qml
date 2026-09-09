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
            root.adapter.discovering = true
        }
    }

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "bluetooth"
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
            if (root.popupOpen && !closeDelayTimer.running) {
                closeDelayTimer.start()
            }
        }
    }

    onHoveredChanged: _updateHoverState()
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

    PopupWindow {
        id: panel
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        visible: root.popupOpen

        implicitWidth: 280
        implicitHeight: bg.implicitHeight

        Rectangle {
            id: bg
            implicitWidth: 280
            implicitHeight: content.implicitHeight + 24
            color: "#1c1c1c"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 6

            HoverHandler {
                id: popupHoverHandler
            }

            Column {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            color: Theme.accent
                        }
                        Text {
                            text: "Bluetooth"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.btEnabled ? "On" : "Off"
                        color: root.btEnabled ? Theme.success : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Text {
                    visible: !root.btEnabled
                    text: "Turn on Bluetooth to see devices"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Item {
                    visible: root.btEnabled
                    width: parent.width
                    height: scanLabel.implicitHeight

                    Text {
                        id: scanLabel
                        text: root.isScanning ? "Scanning… (" + root.scanRemaining + "s)" : "Devices"
                        color: root.isScanning ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.isScanning ? "Stop" : "Scan"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleScan()
                        }
                    }
                }

                Column {
                    visible: root.btEnabled
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.sortedDevices

                        delegate: Item {
                            id: deviceRow
                            required property var modelData
                            width: content.width
                            height: 26

                            Text {
                                id: deviceName
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    right: deviceStatus.left
                                    rightMargin: 8
                                }
                                text: deviceRow.modelData.name || deviceRow.modelData.deviceName
                                color: deviceRow.modelData.connected ? Theme.accent : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                elide: Text.ElideRight
                            }

                            Text {
                                id: deviceStatus
                                anchors {
                                    right: forgetGlyph.visible ? forgetGlyph.left : parent.right
                                    rightMargin: forgetGlyph.visible ? 8 : 0
                                    verticalCenter: parent.verticalCenter
                                }
                                text: deviceRow.modelData.pairing ? "Pairing…"
                                    : deviceRow.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…"
                                    : deviceRow.modelData.connected ? "Connected"
                                    : deviceRow.modelData.paired ? "Connect"
                                    : "Connect"
                                color: deviceRow.modelData.connected ? Theme.success : Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    // connect() for anything not already
                                    // connected — never pair() on its own.
                                    // pair() alone doesn't bring up the HID
                                    // profile afterward, so BlueZ tears the
                                    // link back down as unused within a
                                    // couple seconds (reproduced live: pair
                                    // holds ~2s then drops every time;
                                    // connect() handles pairing *and* the
                                    // profile connect together and holds).
                                    onClicked: {
                                        const d = deviceRow.modelData
                                        if (d.connected) d.disconnect()
                                        else d.connect()
                                    }
                                }
                            }

                            Text {
                                id: forgetGlyph
                                visible: deviceRow.modelData.paired
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                text: ""
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: deviceRow.modelData.forget()
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.sortedDevices.length === 0
                        text: root.isScanning ? "Searching… (" + root.scanRemaining + "s)" : "No devices found — try Scan"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }
        }
    }
}
