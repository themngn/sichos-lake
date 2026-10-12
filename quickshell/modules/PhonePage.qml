import QtQuick
import Quickshell

// Phone page of the Control Center (QuickSettings.qml, popupId "qs-phone"):
// everything about the phone in one place -- the sichlink daemon's switch
// (header), the paired phone as a card (state chips; mirror, wake, connect),
// the mirror's own settings (phone audio, saved PIN, dock side), and other
// phones to pair or unpair. State comes from the Sichlink and
// PhoneMirrorState singletons; nothing here is stored.
MorphContent {
    id: page
    property real contentWidth: 360
    property string screenName: ""
    signal back()

    implicitWidth: page.contentWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    readonly property var phone: Sichlink.phone

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

        // No paired phone to show: why, and the mirror still works over USB.
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
        PageButton {
            visible: !page.phone
            width: parent.width
            accent: !PhoneMirrorState.open
            label: PhoneMirrorState.toggleLabel
            onClicked: PhoneMirrorState.toggle(page.screenName)
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
            readonly property bool mirrorable: !!card.d.adb_serial

            Column {
                id: cardCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                // Icon, name, state line; Unpair tucked away on the right.
                Item {
                    width: parent.width
                    height: Math.max(phoneIcon.height, nameCol.implicitHeight)

                    HeaderIcon {
                        id: phoneIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "\u{f011c}"  // nf-md-cellphone
                        inkHeight: 30
                        color: card.mirrorable ? Theme.accent : card.online ? Theme.text : Theme.textMuted
                    }
                    Column {
                        id: nameCol
                        anchors.left: phoneIcon.right
                        anchors.leftMargin: 12
                        anchors.right: unpairLink.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            text: card.d.name || ""
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: PhoneMirrorState.loading ? "Starting the mirror…"
                                : PhoneMirrorState.open ? (PhoneMirrorState.collapsed ? "Mirror hidden" : "Mirroring")
                                : Sichlink.adbText(card.d)
                            elide: Text.ElideRight
                            color: card.mirrorable || PhoneMirrorState.open ? Theme.success : Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    Text {
                        id: unpairLink
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
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

                // State at a glance. Bluetooth only while the app holds its
                // link to this PC (what Extend Unlock, the optional "always
                // unlocked near this PC" mode, counts on).
                Flow {
                    visible: card.online
                    width: parent.width
                    spacing: 6
                    Chip {
                        label: card.mirrorable ? "Wireless adb" : "No adb"
                        good: card.mirrorable
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

                // Actions: the main one (mirror, or connect while adb isn't
                // there yet), then wake and close as they apply.
                Row {
                    width: parent.width
                    spacing: 6
                    readonly property bool needsConnect: card.online && !card.mirrorable && !PhoneMirrorState.open
                    readonly property bool canWake: card.online && (card.d.screen_on === false || card.d.locked === true)
                    readonly property int buttons: 1 + (canWake ? 1 : 0) + (PhoneMirrorState.open ? 1 : 0)
                    readonly property real secondaryWidth: 80

                    PageButton {
                        width: parent.width - (parent.buttons - 1) * (parent.secondaryWidth + parent.spacing)
                        accent: true
                        label: parent.needsConnect
                            ? (Sichlink.connectingId === card.d.id ? "Connecting…" : "Connect")
                            : PhoneMirrorState.toggleLabel
                        onClicked: parent.needsConnect ? Sichlink.connect(card.d.id) : PhoneMirrorState.toggle(page.screenName)
                    }
                    PageButton {
                        visible: parent.canWake
                        width: parent.secondaryWidth
                        label: "Wake"
                        onClicked: Sichlink.wake(card.d.id)
                    }
                    PageButton {
                        visible: PhoneMirrorState.open
                        width: parent.secondaryWidth
                        label: "Close"
                        onClicked: PhoneMirrorState.close()
                    }
                }
            }
        }

        // The mirror's own settings.
        Column {
            visible: !!page.phone || PhoneMirrorState.open
            width: parent.width
            spacing: 2

            SectionLabel { text: "Mirror" }

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
                label: "Unlock with saved PIN"
                caption: PhoneMirrorState.pinSaved ? "The phone stays locked when you pick it up"
                    : "Tick “Remember on this PC” on the mirror's PIN card"
                PageButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: PhoneMirrorState.pinSaved
                    label: "Forget"
                    onClicked: PhoneMirrorState.forgetPin()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !PhoneMirrorState.pinSaved
                    text: "Not saved"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            SettingRow {
                label: "Dock side"
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: ["left", "right"]
                        PageButton {
                            required property string modelData
                            width: 56
                            accent: PhoneMirrorState.side === modelData
                            label: modelData === "left" ? "Left" : "Right"
                            onClicked: if (!accent) PhoneMirrorState.toggleSide()
                        }
                    }
                }
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
        height: Math.max(Theme.controlHeight, srText.implicitHeight + 8)

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

    component PageButton: Rectangle {
        id: pb
        property string label: ""
        property bool accent: false
        signal clicked()
        width: pbLabel.implicitWidth + 20
        height: Theme.controlHeight - 4
        radius: Theme.controlRadius
        color: pb.accent ? (pbArea.containsMouse ? Theme.accentHover : Theme.accent)
            : pbArea.containsMouse ? Theme.hoverFill : Theme.surfaceRaised
        Text {
            id: pbLabel
            anchors.centerIn: parent
            text: pb.label
            color: pb.accent ? Theme.textOnLight : Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
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
