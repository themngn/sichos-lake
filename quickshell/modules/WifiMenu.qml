import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wi-Fi page of the Control Center (QuickSettings.qml, popupId "qs-wifi"):
// power switch, the scanned network list (connected, then saved, then by
// signal), connect/disconnect/forget, a password row for a secured
// network that isn't saved yet, and -- a saved network's chevron, or a tap on
// the connected one -- a details view in the same card: a "join this
// network" QR code and the password (both hidden until asked for), security,
// signal, address, connect/forget (scripts/wifi-share.py reads the secret).
// Below the list: Hotspot (switch + its page, "qs-hotspot") and DNS
// (Default / Mullvad Base, DnsSettings). Scans only while shown.
//
// The password field isn't a TextInput: a popup surface never gets keyboard
// focus, so while it's open this item is ShellState.keySink and the bar
// forwards keys to handleKey() (see Bar.qml).
MorphContent {
    id: menu
    property real contentWidth: 360
    property string screenName: ""
    signal back()

    implicitWidth: menu.contentWidth + 2 * Theme.surfacePadding
    implicitHeight: (menu.detail ? detailColumn.implicitHeight
        : column.implicitHeight + Theme.sectionSpacing + bottomColumn.implicitHeight) + 2 * Theme.surfacePadding
    // At least as tall as where it's shown (the hub's Controls column), so
    // bottomColumn sits at the column's bottom edge. Only `height`: the hub
    // sizes itself from implicitHeight, so this doesn't feed back into it.
    height: parent ? Math.max(implicitHeight, parent.height) : implicitHeight

    readonly property var device: {
        for (const d of Networking.devices.values) if (d.type === DeviceType.Wifi) return d
        return null
    }
    readonly property bool wifiOn: Networking.wifiEnabled

    // One entry per SSID (the same name shows up once per access point/band),
    // hidden networks (empty name) left out.
    readonly property var networks: {
        if (!menu.device) return []
        const byName = {}
        for (const n of menu.device.networks.values) {
            if (!n.name) continue
            const cur = byName[n.name]
            if (!cur || n.connected || (!cur.connected && n.signalStrength > cur.signalStrength)) byName[n.name] = n
        }
        return Object.values(byName).sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.known !== b.known) return a.known ? -1 : 1
            return b.signalStrength - a.signalStrength
        })
    }

    Binding {
        target: menu.device
        property: "scannerEnabled"
        value: true
        when: menu.shown && !!menu.device
    }

    // Password entry: the network it's for, what's typed, and an error line
    // after a failed attempt.
    property var passwordFor: null
    property string password: ""
    property bool showPassword: false
    property string error: ""

    function askPassword(n, err) {
        menu.passwordFor = n
        menu.password = ""
        menu.error = err || ""
    }
    function cancelPassword() {
        menu.passwordFor = null
        menu.password = ""
        menu.error = ""
    }
    function submitPassword() {
        if (!menu.passwordFor || menu.password.length === 0) return
        menu.passwordFor.connectWithPsk(menu.password)
        menu.cancelPassword()
    }
    function activate(n) {
        if (n.connected) return
        if (n.known || n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe) n.connect()
        else menu.askPassword(n, "")
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) menu.cancelPassword()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) menu.submitPassword()
        else if (event.key === Qt.Key_Backspace) menu.password = menu.password.slice(0, -1)
        else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32) menu.password += event.text
    }
    readonly property bool wantsKeys: menu.shown && menu.passwordFor !== null
    onWantsKeysChanged: {
        if (menu.wantsKeys) {
            ShellState.keySinkScreen = menu.screenName
            ShellState.keySink = menu
        } else if (ShellState.keySink === menu) {
            ShellState.keySink = null
        }
    }
    onShownChanged: if (!menu.shown) { menu.cancelPassword(); menu.closeDetail() }

    // Details view: one network. Its password is fetched when the view opens
    // and dropped when it closes; shown as dots until asked for.
    property var detail: null
    property string detailPassword: ""
    property string detailError: ""
    property bool detailReveal: false
    property bool detailQr: false
    property int detailQrRev: 0
    property bool copied: false
    readonly property string _shareScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/wifi-share.py"
    // $XDG_RUNTIME_DIR: tmpfs, gone at logout -- the code holds the password.
    readonly property string detailQrPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-wifi-qr.png"
    function openDetail(n) {
        menu.cancelPassword()
        menu.closeDetail()
        menu.detail = n
        if (!n.known) return
        detailPw.command = [menu._shareScript, "password", n.name]
        detailPw.running = true
    }
    // Made the first time it's shown.
    function toggleQr() {
        menu.detailQr = !menu.detailQr
        if (!menu.detailQr || menu.detailQrRev > 0 || detailQrProc.running) return
        detailQrProc.command = [menu._shareScript, "qr", menu.detail.name, menu.detailQrPath]
        detailQrProc.running = true
    }
    function closeDetail() {
        menu.detail = null
        menu.detailPassword = ""
        menu.detailError = ""
        menu.detailReveal = false
        menu.detailQr = false
        menu.detailQrRev = 0
        menu.copied = false
    }
    // A forgotten (or out of range) network drops out of the list: back to it.
    onNetworksChanged: if (menu.detail && !menu.networks.includes(menu.detail)) menu.closeDetail()
    function securityText(n) {
        switch (n.security) {
        case WifiSecurityType.Open: return "Open"
        case WifiSecurityType.Owe: return "Open, encrypted"
        case WifiSecurityType.Sae: return "WPA3"
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3 Enterprise"
        case WifiSecurityType.Wpa2Psk: return "WPA2"
        case WifiSecurityType.WpaPsk: return "WPA"
        case WifiSecurityType.Wpa2Eap: case WifiSecurityType.WpaEap: return "Enterprise"
        case WifiSecurityType.StaticWep: case WifiSecurityType.DynamicWep: return "WEP"
        }
        return "Unknown"
    }
    Process {
        id: detailPw
        stdout: StdioCollector { id: detailPwOut }
        stderr: StdioCollector { id: detailPwErr }
        onExited: (code) => {
            if (!menu.detail) return
            if (code === 0) menu.detailPassword = detailPwOut.text.replace(/\n$/, "")
            else menu.detailError = detailPwErr.text.trim() || "Couldn't read the password"
        }
    }
    Process {
        id: detailQrProc
        stderr: StdioCollector { id: detailQrErr }
        onExited: (code) => {
            if (!menu.detail) return
            if (code === 0) menu.detailQrRev++
            else if (menu.detailError === "") menu.detailError = detailQrErr.text.trim() || "Couldn't make the QR code"
        }
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: menu.copied = false }
    // Through wl-copy's stdin, not its argv (visible in the process list).
    Process {
        id: copyProc
        command: ["wl-copy"]
        stdinEnabled: true
        onStarted: { copyProc.write(menu.detailPassword); copyProc.stdinEnabled = false }
    }
    function copyPassword() {
        if (menu.detailPassword === "") return
        copyProc.stdinEnabled = true
        copyProc.running = true
        menu.copied = true
        copiedTimer.restart()
    }

    // signalStrength is 0..1 (logged live: 0.84 for a full-bars network).
    function signalGlyph(n) {
        const s = n.signalStrength * 100
        const lock = n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
        // nf-md-wifi_strength_1..4 (and _lock variants)
        if (s > 75) return lock ? "\u{f0929}" : "\u{f0928}"
        if (s > 50) return lock ? "\u{f0926}" : "\u{f0925}"
        if (s > 25) return lock ? "\u{f0923}" : "\u{f0922}"
        return lock ? "\u{f0920}" : "\u{f091f}"
    }
    function statusText(n) {
        if (n.state === ConnectionState.Connecting) return "Connecting…"
        if (n.state === ConnectionState.Disconnecting) return "Disconnecting…"
        if (n.connected) return "Connected"
        if (n.known) return "Saved"
        return ""
    }

    Column {
        id: column
        visible: !menu.detail
        anchors.top: parent.top
        anchors.topMargin: Theme.surfacePadding
        anchors.horizontalCenter: parent.horizontalCenter
        width: menu.contentWidth
        spacing: Theme.sectionSpacing

        Item {
            width: parent.width
            height: 20

            Row {
                spacing: 6
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                BackButton { onClicked: menu.back() }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
            }
            Switch {
                anchors.right: parent.right
                checked: menu.wifiOn
                onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        Text {
            visible: !menu.device || !menu.wifiOn
            text: !menu.device ? "No Wi-Fi adapter" : "Wi-Fi is off"
            color: Theme.textDim
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        SectionLabel {
            visible: !!menu.device && menu.wifiOn
            text: menu.networks.length === 0 ? "Searching…" : "Networks"
        }

        // Scrolls past ~8 rows so a busy neighbourhood doesn't make the card
        // taller than the screen.
        Flickable {
            id: list
            visible: !!menu.device && menu.wifiOn && menu.networks.length > 0
            width: parent.width
            height: Math.min(listColumn.implicitHeight, 8 * (Theme.controlHeight + 10) + 7 * 2)
            contentHeight: listColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listColumn
                width: list.width
                spacing: 2

                Repeater {
                    model: menu.networks

                    delegate: Column {
                        id: entry
                        required property var modelData
                        readonly property bool asking: menu.passwordFor === entry.modelData
                        width: listColumn.width
                        spacing: 4

                        // A wrong/missing password comes back as a failed
                        // connection: ask (again) right here.
                        Connections {
                            target: entry.modelData
                            function onConnectionFailed(reason) {
                                if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout
                                    || reason === ConnectionFailReason.WifiClientFailed)
                                    menu.askPassword(entry.modelData, "Couldn't connect — check the password")
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: Theme.controlHeight + 10
                            radius: Theme.controlRadius
                            color: entry.modelData.connected ? Theme.selectedFill
                                : rowArea.containsMouse || entry.asking ? Theme.hoverFill : "transparent"

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: entry.asking ? menu.cancelPassword()
                                    : entry.modelData.connected ? menu.openDetail(entry.modelData)
                                    : menu.activate(entry.modelData)
                            }

                            Text {
                                id: sig
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                text: menu.signalGlyph(entry.modelData)
                                color: entry.modelData.connected ? Theme.text : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 9
                            }
                            Column {
                                anchors.left: sig.right
                                anchors.leftMargin: 8
                                anchors.right: actions.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    width: parent.width
                                    text: entry.modelData.name
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    font.bold: entry.modelData.connected
                                }
                                Text {
                                    visible: text !== ""
                                    width: parent.width
                                    text: menu.statusText(entry.modelData)
                                    color: entry.modelData.connected ? Theme.success : Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                            Row {
                                id: actions
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Rectangle {
                                    visible: entry.modelData.connected
                                    width: discLabel.implicitWidth + 16
                                    height: Theme.controlHeight - 4
                                    radius: Theme.controlRadius
                                    color: discArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                                    Text {
                                        id: discLabel
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        color: Theme.text
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                    MouseArea {
                                        id: discArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: entry.modelData.disconnect()
                                    }
                                }
                                // Saved networks: their details (share,
                                // forget) -- the Control Center tiles' chevron.
                                Rectangle {
                                    visible: entry.modelData.known
                                    width: 26
                                    height: Theme.controlHeight - 4
                                    radius: Theme.controlRadius
                                    color: moreArea.containsMouse ? Theme.hoverFill : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u{f054}" // nf-fa-chevron_right
                                        color: moreArea.containsMouse ? Theme.text : Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    MouseArea {
                                        id: moreArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: menu.openDetail(entry.modelData)
                                    }
                                }
                            }
                        }

                        // Password row
                        Column {
                            visible: entry.asking
                            width: parent.width
                            spacing: 6

                            Row {
                                spacing: 6
                                Rectangle {
                                    width: entry.width - connectButton.width - 6
                                    height: Theme.controlHeight + 4
                                    radius: Theme.controlRadius
                                    color: Theme.controlFill
                                    border.width: 1
                                    border.color: Theme.accent

                                    Text {
                                        id: pwText
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.right: eye.left
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menu.password.length === 0 ? "Password"
                                            : menu.showPassword ? menu.password : "•".repeat(menu.password.length)
                                        color: menu.password.length === 0 ? Theme.textDim : Theme.text
                                        elide: Text.ElideLeft
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                    }
                                    // Caret, since there's no real TextInput.
                                    Rectangle {
                                        x: pwText.x + (menu.password.length === 0 ? 0 : Math.min(pwText.contentWidth, pwText.width)) + 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 1
                                        height: Theme.fontSize + 2
                                        color: Theme.text
                                        SequentialAnimation on opacity {
                                            running: entry.asking
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0; duration: 500 }
                                            NumberAnimation { to: 1; duration: 500 }
                                        }
                                    }
                                    Text {
                                        id: eye
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menu.showPassword ? "\u{f06d0}" : "\u{f0208}" // eye_off / eye
                                        color: eyeArea.containsMouse ? Theme.text : Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize + 1
                                        MouseArea {
                                            id: eyeArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: menu.showPassword = !menu.showPassword
                                        }
                                    }
                                }
                                Rectangle {
                                    id: connectButton
                                    width: connectLabel.implicitWidth + 20
                                    height: Theme.controlHeight + 4
                                    radius: Theme.controlRadius
                                    color: connectArea.containsMouse ? Theme.accentHover : Theme.accent
                                    opacity: menu.password.length > 0 ? 1 : 0.5
                                    Text {
                                        id: connectLabel
                                        anchors.centerIn: parent
                                        text: "Connect"
                                        color: Theme.textOnLight
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                        font.bold: true
                                    }
                                    MouseArea {
                                        id: connectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: menu.submitPassword()
                                    }
                                }
                            }
                            Text {
                                visible: menu.error !== ""
                                text: menu.error
                                color: Theme.danger
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }
                }
            }
        }
    }

    // Everything but the network list, at the bottom of the page: the page
    // is as tall as its column in the hub (see `height` above), so these
    // stay put at the bottom edge however many networks are around.
    Column {
        id: bottomColumn
        visible: !menu.detail
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.surfacePadding
        anchors.horizontalCenter: parent.horizontalCenter
        width: menu.contentWidth
        spacing: Theme.sectionSpacing

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        // Hotspot and DNS live here (they used to be Control Center tiles):
        // both are about this Wi-Fi connection.
        SettingRow {
            glyph: Hotspot.active ? "\u{f0003}" : "\u{f1511}" // access_point_network / _off
            label: "Hotspot"
            // Never the password: this is on screen for anyone to read (its
            // page has Copy password).
            status: Hotspot.pending === "off" ? "Stopping…" : Hotspot.busy ? "Starting…"
                : Hotspot.active ? (Hotspot.clients > 0 ? Hotspot.ssid + " · " + Hotspot.clients + (Hotspot.clients === 1 ? " device" : " devices") : Hotspot.ssid)
                : Hotspot.armed ? "Switch again: turns Wi-Fi off"
                : Hotspot.error || (Hotspot.canShare ? "Off · would share " + Hotspot.wifiName : "Off")
            Row {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Switch {
                    checked: Hotspot.active || Hotspot.starting
                    opacity: Hotspot.busy ? 0.5 : 1
                    onToggled: Hotspot.toggle()
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: Theme.controlRadius
                    color: hotspotMore.containsMouse ? Theme.hoverFill : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0142}" // nf-md-chevron_right
                        color: hotspotMore.containsMouse ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                    }
                    MouseArea {
                        id: hotspotMore
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.activePopupScreen = menu.screenName
                            ShellState.activePopup = "qs-hotspot"
                        }
                    }
                }
            }
        }
        SettingRow {
            glyph: "\u{f0b8c}"
            label: "DNS"
            status: DnsSettings.busy ? "Switching…" : DnsSettings.error || DnsSettings.desc
            Row {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: DnsSettings.presets
                    delegate: Rectangle {
                        id: dnsButton
                        required property var modelData
                        readonly property bool selected: DnsSettings.current === dnsButton.modelData.id
                        width: dnsLabel.implicitWidth + 16
                        height: Theme.controlHeight - 2
                        radius: Theme.controlRadius
                        color: dnsButton.selected ? Theme.selectedFill : dnsArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                        opacity: DnsSettings.busy ? 0.5 : 1
                        Text {
                            id: dnsLabel
                            anchors.centerIn: parent
                            text: dnsButton.modelData.label
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                            color: dnsButton.selected ? Theme.text : Theme.textMuted
                        }
                        MouseArea {
                            id: dnsArea
                            anchors.fill: parent
                            enabled: !DnsSettings.busy
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DnsSettings.set(dnsButton.modelData.id)
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        Rectangle {
            width: parent.width
            height: Theme.controlHeight + 8
            radius: Theme.controlRadius
            color: settingsArea.containsMouse ? Theme.hoverFill : "transparent"
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Network settings"
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f03cc}" // nf-md-open_in_new
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
            MouseArea {
                id: settingsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    ShellState.activePopup = ""
                    Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/wlctl-toggle.sh"])
                }
            }
        }
    }

    // --- Details: one saved network ---
    Column {
        id: detailColumn
        visible: !!menu.detail
        anchors.top: parent.top
        anchors.topMargin: Theme.surfacePadding
        anchors.horizontalCenter: parent.horizontalCenter
        width: menu.contentWidth
        spacing: Theme.sectionSpacing
        readonly property var n: menu.detail
        readonly property bool secured: !!n && n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe

        Item {
            width: parent.width
            height: 20
            Row {
                spacing: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                BackButton { id: detailBack; onClicked: menu.closeDetail() }
                Text {
                    width: parent.width - detailBack.width - 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: detailColumn.n ? detailColumn.n.name : ""
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        Column {
            width: parent.width
            spacing: 2
            DetailRow {
                visible: detailColumn.secured
                label: "Password"
                // Dots, not the length: a fixed count.
                value: menu.detailPassword === "" ? (menu.detailError || "…")
                    : menu.detailReveal ? menu.detailPassword : "••••••••••••"
                IconButton {
                    glyph: menu.detailReveal ? "\u{f0209}" : "\u{f0208}" // nf-md-eye_off / eye
                    onClicked: menu.detailReveal = !menu.detailReveal
                }
                IconButton {
                    glyph: menu.copied ? "\u{f012c}" : "\u{f018f}" // nf-md-check / content_copy
                    onClicked: menu.copyPassword()
                }
            }
            DetailRow { label: "Security"; value: detailColumn.n ? menu.securityText(detailColumn.n) : "" }
            DetailRow {
                label: "Signal"
                value: !detailColumn.n ? "" : Math.round(detailColumn.n.signalStrength * 100) + "%"
                    + (detailColumn.n.connected && NetInfo.wifiBand ? " · " + NetInfo.wifiBand : "")
            }
            DetailRow {
                visible: !!detailColumn.n && detailColumn.n.connected && NetInfo.ipv4 !== ""
                label: "IP address"
                value: NetInfo.ipv4
            }
        }

        // QR code to join, on request: black on white with a quiet zone,
        // whatever the theme -- what phone cameras read reliably.
        Column {
            width: parent.width
            spacing: 8
            DetailButton {
                width: parent.width
                label: menu.detailQr ? "Hide QR code" : "Show QR code"
                onClicked: menu.toggleQr()
            }
            Rectangle {
                visible: menu.detailQr
                anchors.horizontalCenter: parent.horizontalCenter
                width: 196
                height: 196
                radius: Theme.controlRadius
                color: "white"
                Image {
                    anchors.centerIn: parent
                    width: 180
                    height: 180
                    visible: menu.detailQrRev > 0
                    source: menu.detailQrRev > 0 ? "file://" + menu.detailQrPath + "?" + menu.detailQrRev : ""
                    cache: false
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    visible: menu.detailQrRev === 0
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: menu.detailError || "…"
                    color: Theme.textOnLight
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            Text {
                visible: menu.detailQr
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Scan with a phone's camera to join"
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        Row {
            width: parent.width
            spacing: 6
            DetailButton {
                width: (parent.width - 6) / 2
                label: !detailColumn.n ? "" : detailColumn.n.connected ? "Disconnect" : "Connect"
                onClicked: {
                    const n = detailColumn.n
                    if (n.connected) n.disconnect()
                    else n.connect()
                }
            }
            DetailButton {
                width: (parent.width - 6) / 2
                label: "Forget network"
                danger: true
                onClicked: { const n = detailColumn.n; menu.closeDetail(); n.forget() }
            }
        }
    }

    // "Label        value [buttons]"
    component DetailRow: Item {
        id: dr
        property string label: ""
        property string value: ""
        default property alias buttons: drButtons.data
        width: parent ? parent.width : 0
        height: 28
        Text {
            id: drLabel
            width: 96
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: dr.label
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            anchors.left: drLabel.right
            anchors.right: drButtons.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: dr.value
            color: Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Row {
            id: drButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
        }
    }
    component IconButton: Rectangle {
        id: ib
        property string glyph: ""
        signal clicked()
        width: 28
        height: 24
        radius: Theme.controlRadius
        color: ibArea.containsMouse ? Theme.hoverFill : "transparent"
        Text {
            anchors.centerIn: parent
            text: ib.glyph
            color: ibArea.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
        }
        MouseArea {
            id: ibArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }
    component DetailButton: Rectangle {
        id: db
        property string label: ""
        property bool danger: false
        signal clicked()
        height: Theme.controlHeight
        radius: Theme.controlRadius
        color: dbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
        Text {
            anchors.centerIn: parent
            text: db.label
            color: db.danger && dbArea.containsMouse ? Theme.danger : Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        MouseArea {
            id: dbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: db.clicked()
        }
    }

    // One setting under the network list: icon, name, a status line, and its
    // controls (children) on the right.
    component SettingRow: Item {
        id: sr
        property string glyph: ""
        property string label: ""
        property string status: ""
        default property alias controls: srControls.data
        width: parent ? parent.width : 0
        height: 40

        Text {
            id: srGlyph
            x: 4
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: sr.glyph
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 4
        }
        Column {
            anchors.left: srGlyph.right
            anchors.leftMargin: 10
            anchors.right: srControls.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: sr.label
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: sr.status
                elide: Text.ElideRight
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
        Item {
            id: srControls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: parent.height
        }
    }
}
