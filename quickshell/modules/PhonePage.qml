import QtQuick
import Quickshell
import Quickshell.Widgets

// Phone page of the Control Center (QuickSettings.qml, popupId "qs-phone"):
// everything about the phone in one place -- the sichlink daemon's switch
// (header), the paired phone as a card (its wallpaper, battery, state chips),
// the mirror as its own section
// (start, show/hide, stop,
// phone audio, saved PIN -- settable here --, dock side), display mode (the
// phone as an extra monitor, sichlink's `display`), and other phones to
// pair or unpair. The Phone tile opens this page. State comes from the
// Sichlink and PhoneMirrorState singletons; the PIN goes to the keyring.
MorphContent {
    id: page
    property real contentWidth: 360
    property string screenName: ""
    signal back()

    implicitWidth: page.contentWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    readonly property var phone: Sichlink.phone
    // Width shared by the PIN buttons and the dock-side switch so the two
    // rows' controls line up edge to edge.
    readonly property real sideControlWidth: 164

    // PIN entry. Like WifiMenu's password: a popup never gets keyboard
    // focus, so while the field is open this page is ShellState.keySink and
    // the bar forwards keys to handleKey(). Digits only (the phone's PIN pad).
    property bool pinEditing: false
    property string pin: ""
    function editPin() { page.pin = ""; page.pinEditing = true }
    function cancelPin() { page.pin = ""; page.pinEditing = false }
    function savePin() {
        if (page.pin.length < 4) return
        PhoneMirrorState.storePin(page.pin)
        page.cancelPin()
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) page.cancelPin()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) page.savePin()
        else if (event.key === Qt.Key_Backspace) page.pin = page.pin.slice(0, -1)
        else if (/^[0-9]$/.test(event.text) && page.pin.length < 16) page.pin += event.text
    }
    readonly property bool wantsKeys: page.shown && page.pinEditing
    onWantsKeysChanged: {
        if (page.wantsKeys) {
            ShellState.keySinkScreen = page.screenName
            ShellState.keySink = page
        } else if (ShellState.keySink === page) {
            ShellState.keySink = null
        }
    }
    onShownChanged: if (!page.shown) page.cancelPin()

    Column {
        id: column
        anchors.centerIn: parent
        width: page.contentWidth
        spacing: Theme.sectionSpacing

        // Header: back, title, and the daemon's on/off switch.
        Item {
            width: parent.width
            height: 20

            Row {
                spacing: 6
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                BackButton { onClicked: page.back() }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Phone"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: Sichlink.installed
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Phone Link"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    // Follows the request right away while systemctl works.
                    checked: Sichlink.busy ? Sichlink._wantOn : Sichlink.running
                    onToggled: Sichlink.setEnabled(!checked)
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        // No paired phone to show: why (the mirror below still works over USB).
        Text {
            visible: !page.phone
            width: parent.width
            wrapMode: Text.WordWrap
            text: !Sichlink.installed ? "Phone Link isn't installed (see ~/Work/sichlink). The mirror works over USB."
                : Sichlink.busy ? Sichlink.stateText
                : !Sichlink.running ? "Phone Link is off. The mirror works over USB."
                : Sichlink.devices.length === 0 ? "Searching… Open the sichlink app on the phone, on the same Wi-Fi."
                : "Pair a phone below."
            color: Theme.textDim
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        // The paired phone.
        Rectangle {
            id: card
            visible: !!page.phone
            width: parent.width
            height: cardCol.implicitHeight + 24
            radius: Theme.controlRadius
            color: Theme.controlFill

            readonly property var d: page.phone || ({})
            readonly property bool online: !!card.d.connected
            readonly property bool mirrorable: Sichlink.canMirror(card.d)

            Column {
                id: cardCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                // Wallpaper (the phone's own, sent by the app) or an
                // icon; name, connection line; Unpair tucked away on the right.
                Item {
                    width: parent.width
                    height: Math.max(thumb.height, nameCol.implicitHeight)

                    ClippingRectangle {
                        id: thumb
                        readonly property string url: Sichlink.wallpaperUrl(card.d)
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // A small phone: the image area has the phone's
                        // own screen ratio (sent with the wallpaper), the
                        // border standing in for the bezel (the content
                        // is clipped inside it).
                        readonly property real ratio: card.d.screen_width > 0 ? card.d.screen_height / card.d.screen_width : 2.2
                        width: thumb.url ? 64 : phoneIcon.width
                        height: thumb.url ? Math.round((64 - 2 * border.width) * thumb.ratio) + 2 * border.width : phoneIcon.height
                        radius: 12
                        color: "transparent"
                        border.width: thumb.url ? 3 : 0
                        border.color: Theme.surfaceRaised
                        // The stored image is wider than the screen; the
                        // middle slice is roughly what the home screen shows.
                        Image {
                            anchors.fill: parent
                            visible: thumb.url !== ""
                            source: thumb.url
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.height: 272
                            opacity: card.online ? 1 : 0.5
                        }
                        HeaderIcon {
                            id: phoneIcon
                            visible: thumb.url === ""
                            glyph: "\u{f011c}"  // nf-md-cellphone
                            inkHeight: 30
                            color: card.mirrorable ? Theme.accent : card.online ? Theme.text : Theme.textMuted
                        }
                    }
                    Column {
                        id: nameCol
                        anchors.left: thumb.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        // Only the name stops short of Unpair.
                        Text {
                            width: parent.width - unpairLink.width - 8
                            text: card.d.name || ""
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: Sichlink.adbText(card.d)
                            elide: Text.ElideRight
                            color: card.mirrorable ? Theme.success : Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        // Battery: glyph by level (bolt while charging).
                        Row {
                            visible: card.online && Sichlink.batteryText(card.d) !== ""
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Sichlink.batteryGlyph(card.d)
                                color: card.d.charging ? Theme.success
                                    : card.d.battery <= 15 ? Theme.danger : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Sichlink.batteryText(card.d)
                                color: Theme.text
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                        // State at a glance. Bluetooth only while the app holds its
                        // link to this PC (what Extend Unlock, the optional "always
                        // unlocked near this PC" mode, counts on).
                        Flow {
                            visible: card.online
                            width: parent.width
                            spacing: 6
                            topPadding: 4
                            // adb only exists while the mirror/display uses it.
                            Chip {
                                visible: !!card.d.adb_serial || !card.mirrorable
                                label: card.d.adb_serial ? "Wireless adb" : "No adb"
                                good: !!card.d.adb_serial
                            }
                            Chip {
                                visible: label !== ""
                                label: Sichlink.lockText(card.d)
                                good: card.d.locked === false
                            }
                            Chip {
                                visible: card.d.bt_link === true
                                label: "Bluetooth"
                                good: true
                            }
                        }
                    }
                    Text {
                        id: unpairLink
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: "Unpair"
                        color: unpairArea.containsMouse ? Theme.danger : Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                        MouseArea {
                            id: unpairArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Sichlink.unpair(card.d.id)
                        }
                    }
                }
            }
        }

        // The mirror: open/show/hide and close, then its settings. Always
        // there -- it works over USB without Phone Link.
        Column {
            width: parent.width
            spacing: 2

            SectionLabel {
                text: "Mirror" + (PhoneMirrorState.loading ? " · Starting…"
                    : !PhoneMirrorState.open ? ""
                    : PhoneMirrorState.collapsed ? " · Hidden" : " · On screen")
            }

            // One explicit action per button: Start mirror while it's off;
            // once it runs, Show/Hide (the window slides off-screen, the
            // session stays) and Stop (ends it -- restarting takes a few
            // seconds, and a phone it unlocked locks again).
            Row {
                width: parent.width
                spacing: 6
                bottomPadding: 6

                BigButton {
                    visible: !PhoneMirrorState.open
                    width: parent.width
                    accent: true
                    busy: PhoneMirrorState.loading
                    glyph: "\u{f0118}" // nf-md-cast
                    label: PhoneMirrorState.loading ? "Starting…" : "Start mirror"
                    onClicked: PhoneMirrorState.start(page.screenName)
                }
                BigButton {
                    visible: PhoneMirrorState.open
                    width: (parent.width - parent.spacing) / 2
                    glyph: PhoneMirrorState.collapsed ? "\u{f0208}" : "\u{f0209}" // nf-md-eye / eye_off
                    label: PhoneMirrorState.collapsed ? "Show" : "Hide"
                    onClicked: PhoneMirrorState.collapsed ? PhoneMirrorState.expand() : PhoneMirrorState.collapse()
                }
                BigButton {
                    visible: PhoneMirrorState.open
                    width: (parent.width - parent.spacing) / 2
                    glyph: "\u{f04db}" // nf-md-stop
                    label: "Stop"
                    onClicked: PhoneMirrorState.close()
                }
            }
            Text {
                visible: !PhoneMirrorState.open && !!page.phone && !card.mirrorable
                bottomPadding: 6
                text: Sichlink.adbText(card.d) + " · or plug it in"
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
            SettingRow {
                visible: PhoneMirrorState.open
                label: "Phone audio on this PC"
                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: PhoneMirrorState.audio
                    onToggled: PhoneMirrorState.setAudio(!checked)
                }
            }
            SettingRow {
                label: PhoneMirrorState.pinSaved ? "PIN saved" : "No PIN saved"
                minHeight: Theme.controlHeight + 10
                PageButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !page.pinEditing
                    large: true
                    // Alone ("Set PIN") it spans the whole width.
                    width: PhoneMirrorState.pinSaved ? (page.sideControlWidth - parent.spacing) / 2 : page.sideControlWidth
                    label: PhoneMirrorState.pinSaved ? "Change" : "Set PIN"
                    accent: !PhoneMirrorState.pinSaved
                    onClicked: page.editPin()
                }
                PageButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: PhoneMirrorState.pinSaved && !page.pinEditing
                    large: true
                    width: (page.sideControlWidth - parent.spacing) / 2
                    label: "Forget"
                    onClicked: PhoneMirrorState.forgetPin()
                }
            }
            // PIN field (see handleKey): dots, caret, Save / Cancel.
            Row {
                visible: page.pinEditing
                width: parent.width
                spacing: 6
                bottomPadding: 4

                Rectangle {
                    width: parent.width - saveBtn.width - cancelBtn.width - 2 * parent.spacing
                    height: Theme.controlHeight + 4
                    radius: Theme.controlRadius
                    color: Theme.controlFill
                    border.width: 1
                    border.color: Theme.accent

                    Text {
                        id: pinText
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.pin.length === 0 ? "Type the phone's PIN" : "•".repeat(page.pin.length)
                        color: page.pin.length === 0 ? Theme.textDim : Theme.text
                        elide: Text.ElideLeft
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    // Caret, since there's no real TextInput.
                    Rectangle {
                        x: pinText.x + (page.pin.length === 0 ? 0 : Math.min(pinText.contentWidth, pinText.width)) + 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Theme.fontSize + 2
                        color: Theme.text
                        SequentialAnimation on opacity {
                            running: page.pinEditing
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                }
                PageButton {
                    id: saveBtn
                    anchors.verticalCenter: parent.verticalCenter
                    large: true
                    accent: true
                    opacity: page.pin.length >= 4 ? 1 : 0.5
                    label: "Save"
                    onClicked: page.savePin()
                }
                PageButton {
                    id: cancelBtn
                    anchors.verticalCenter: parent.verticalCenter
                    large: true
                    label: "Cancel"
                    onClicked: page.cancelPin()
                }
            }
            SettingRow {
                label: "Dock side"
                minHeight: Theme.controlHeight + 10
                Segmented {
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }]
                    current: PhoneMirrorState.side
                    onPicked: (value) => { if (value !== PhoneMirrorState.side) PhoneMirrorState.toggleSide() }
                }
            }
        }

        // Display mode: the phone as an extra monitor (Sichlink.setDisplay).
        // Needs the daemon and wireless adb (sichlink connects it for display
        // mode and keeps it while that runs), unlike the mirror.
        Column {
            visible: !!page.phone && Sichlink.running
            width: parent.width
            spacing: 2

            SectionLabel {
                text: "Display" + (Sichlink.displayOn ? " · On"
                    : Sichlink.displayStarting ? " · Starting…" : "")
            }
            BigButton {
                width: parent.width
                accent: !Sichlink.displayOn
                busy: Sichlink.displayStarting && !Sichlink.displayOn
                opacity: card.mirrorable || Sichlink.displayOn ? 1 : 0.5
                glyph: Sichlink.displayOn || Sichlink.displayStarting ? "\u{f04db}" : "\u{f0379}" // nf-md-stop / monitor
                label: Sichlink.displayOn ? "Stop display"
                    : Sichlink.displayStarting ? "Cancel"
                    : "Use as display"
                onClicked: {
                    if (Sichlink.displayOn || Sichlink.displayStarting) Sichlink.setDisplay(false)
                    else if (card.mirrorable) Sichlink.setDisplay(true)
                }
            }
            Text {
                readonly property string hint: Sichlink.displayError ? Sichlink.displayError
                    : !card.mirrorable && !Sichlink.displayOn ? Sichlink.adbText(card.d)
                    : Sichlink.displayStarting && !Sichlink.displayOn && card.d.locked ? "Unlock the phone to show the display"
                    : Sichlink.displayOn ? "Touch works as a mouse: tap, drag, long press = right click, two fingers = scroll. Back on the phone ends it."
                    : ""
                visible: hint !== ""
                width: parent.width
                topPadding: 4
                wrapMode: Text.WordWrap
                text: hint
                color: Sichlink.displayError ? Theme.danger : Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        // Drive: the phone's storage as a folder (Sichlink.setDrive). Over
        // sichlink's own connection, not adb -- so it only needs the phone
        // connected, locked or not.
        Column {
            visible: !!page.phone && Sichlink.running
            width: parent.width
            spacing: 2

            SectionLabel {
                text: "Drive" + (Sichlink.driveBusy ? (Sichlink.drivePath ? " · Unmounting…" : " · Mounting…")
                    : Sichlink.driveMounted ? " · Mounted"
                    : Sichlink.drivePath ? " · Waiting for the phone" : "")
            }
            Row {
                width: parent.width
                spacing: 6

                BigButton {
                    visible: !Sichlink.drivePath
                    width: parent.width
                    accent: true
                    busy: Sichlink.driveBusy
                    opacity: card.online || Sichlink.driveBusy ? 1 : 0.5
                    glyph: "\u{f02ca}" // nf-md-harddisk
                    label: Sichlink.driveBusy ? "Mounting…" : "Mount as drive"
                    onClicked: if (card.online) Sichlink.setDrive(true)
                }
                BigButton {
                    visible: !!Sichlink.drivePath
                    width: (parent.width - parent.spacing) / 2
                    opacity: Sichlink.driveMounted ? 1 : 0.5
                    glyph: "\u{f024b}" // nf-md-folder
                    label: "Open"
                    onClicked: Sichlink.openDrive()
                }
                BigButton {
                    visible: !!Sichlink.drivePath
                    width: (parent.width - parent.spacing) / 2
                    busy: Sichlink.driveBusy
                    glyph: "\u{f01ea}" // nf-md-eject
                    label: "Unmount"
                    onClicked: Sichlink.setDrive(false)
                }
            }
            Text {
                readonly property string hint: Sichlink.driveError ? Sichlink.driveError
                    : Sichlink.driveMounted ? Sichlink.drivePath.replace(/^\/home\/[^\/]+/, "~")
                    : Sichlink.drivePath ? (card.d.mount_error || "Mounts again when the phone is back")
                    : !card.online ? "The phone is offline"
                    : "The phone's storage as a folder (~/Phone), even with it locked"
                width: parent.width
                topPadding: 4
                wrapMode: Text.WordWrap
                text: hint
                color: Sichlink.driveError ? Theme.danger : Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        // Phones to pair, other paired ones.
        Column {
            visible: Sichlink.others.length > 0
            width: parent.width
            spacing: 2

            SectionLabel { text: page.phone ? "Other phones" : "Phones" }

            Repeater {
                model: Sichlink.others

                delegate: Column {
                    id: entry
                    required property var modelData
                    readonly property var d: entry.modelData
                    readonly property bool pairing: Sichlink.pairingId === entry.d.id
                    width: column.width

                    SettingRow {
                        label: entry.d.name
                        caption: entry.d.trusted ? (entry.d.connected ? "Paired" : "Paired, offline") : "Not paired"
                        PageButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.d.connected && !entry.d.trusted && !entry.pairing
                            label: "Pair"
                            accent: true
                            onClicked: Sichlink.pair(entry.d.id)
                        }
                        PageButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.d.trusted
                            label: "Unpair"
                            onClicked: Sichlink.unpair(entry.d.id)
                        }
                    }

                    // Pairing in progress: the code to compare with the phone's.
                    Row {
                        visible: entry.pairing
                        leftPadding: 10
                        spacing: 12
                        bottomPadding: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Sichlink.pairCode !== ""
                            text: Sichlink.pairCode.slice(0, 3) + " " + Sichlink.pairCode.slice(3)
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 8
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Sichlink.pairCode ? "Accept on the phone\nif it shows this code"
                                : Sichlink.pairError ? Sichlink.pairError : "Asking the phone…"
                            color: Sichlink.pairError && !Sichlink.pairCode ? Theme.danger : Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
            }
        }

        Text {
            visible: Sichlink.running && Sichlink.status.name !== ""
            text: "This PC: " + Sichlink.status.name + " · " + Sichlink.status.id
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
        }
    }

    component SectionLabel: Text {
        bottomPadding: 4
        color: Theme.textMuted
        font.family: Theme.uiFontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    // A label (and optional caption) on the left, controls on the right.
    component SettingRow: Item {
        id: sr
        property string label: ""
        property string caption: ""
        default property alias controls: controlRow.data
        width: column.width
        // Rows with large controls raise this (the control Row is anchored
        // to the row's height, so it can't size the row itself).
        property real minHeight: Theme.controlHeight
        height: Math.max(sr.minHeight, srText.implicitHeight + 8)

        Column {
            id: srText
            anchors.left: parent.left
            anchors.right: controlRow.left
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
            }
            Text {
                visible: sr.caption !== ""
                width: parent.width
                text: sr.caption
                elide: Text.ElideRight
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
        Row {
            id: controlRow
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 6
        }
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool good: false
        width: chipRow.implicitWidth + 16
        height: 22
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: Theme.separator
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: chip.good ? Theme.success : Theme.textMuted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // Segmented control: one track, equal segments, the selection a pill
    // that slides to the picked one.
    component Segmented: Rectangle {
        id: seg
        property var options: []  // [{value, label}]
        property string current: ""
        signal picked(string value)
        readonly property int index: seg.options.findIndex(o => o.value === seg.current)
        width: page.sideControlWidth
        readonly property real segWidth: (seg.width - 4) / Math.max(1, seg.options.length)
        height: Theme.controlHeight + 4
        radius: Theme.controlRadius
        color: Theme.controlFill

        Rectangle {
            visible: seg.index >= 0
            x: 2 + Math.max(0, seg.index) * seg.segWidth
            y: 2
            width: seg.segWidth
            height: parent.height - 4
            radius: Theme.controlRadius - 2
            color: Theme.accent
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        Row {
            x: 2
            Repeater {
                model: seg.options
                Item {
                    required property var modelData
                    required property int index
                    width: seg.segWidth
                    height: seg.height
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: index === seg.index ? Theme.textOnLight
                            : segArea.containsMouse ? Theme.text : Theme.textMuted
                        Behavior on color { ColorAnimation { duration: 180 } }
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: index === seg.index
                    }
                    MouseArea {
                        id: segArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: index === seg.index ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: seg.picked(modelData.value)
                    }
                }
            }
        }
    }

    // Full-size action button: glyph + label, centered.
    component BigButton: Rectangle {
        id: bb
        property string label: ""
        property string glyph: ""
        property bool accent: false
        property bool busy: false
        signal clicked()
        height: Theme.controlHeight + 8
        radius: Theme.controlRadius
        opacity: bb.busy ? 0.6 : 1
        color: bb.accent ? (bbArea.containsMouse ? Theme.accentHover : Theme.accent)
            : bbArea.containsMouse ? Theme.hoverFill : Theme.surfaceRaised
        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: bb.glyph !== ""
                text: bb.glyph
                color: bb.accent ? Theme.textOnLight : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 3
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: bb.label
                color: bb.accent ? Theme.textOnLight : Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
        }
        MouseArea {
            id: bbArea
            anchors.fill: parent
            enabled: !bb.busy
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bb.clicked()
        }
    }

    component PageButton: Rectangle {
        id: pb
        property string label: ""
        property bool accent: false
        // Main controls of a row (PIN, dock side's neighbours): taller, wider,
        // body-size text.
        property bool large: false
        signal clicked()
        width: pbLabel.implicitWidth + (pb.large ? 32 : 20)
        height: pb.large ? Theme.controlHeight + 4 : Theme.controlHeight - 4
        radius: Theme.controlRadius
        color: pb.accent ? (pbArea.containsMouse ? Theme.accentHover : Theme.accent)
            : pbArea.containsMouse ? Theme.hoverFill : Theme.surfaceRaised
        Text {
            id: pbLabel
            anchors.centerIn: parent
            text: pb.label
            color: pb.accent ? Theme.textOnLight : Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: pb.large ? Theme.fontSize - 1 : Theme.fontSize - 2
            font.bold: pb.accent
        }
        MouseArea {
            id: pbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }
}
