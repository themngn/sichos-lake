import QtQuick
import Quickshell

// The Control Center's Hotspot page ("qs-hotspot", the Hotspot tile's
// chevron): on/off, how it runs (sharing the Wi-Fi connection, or on the
// Wi-Fi card instead of it -- see scripts/hotspot.py), the network's name and
// password, and a QR code phones can scan to join. State is Hotspot.qml's.
// The password stays hidden until asked for, here and never on the tile;
// both it and the QR code are hidden again whenever the page reopens.
MorphContent {
    id: page
    property real contentWidth: 360
    signal back()

    implicitWidth: page.contentWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    property bool reveal: false
    property bool qrShown: false
    // Mode the next start uses: sharing when the Wi-Fi allows it, unless
    // picked otherwise here. While running, the mode it's running in.
    property string picked: ""
    readonly property string mode: Hotspot.active ? Hotspot.mode
        : page.picked === "shared" && Hotspot.canShare ? "shared"
        : page.picked === "standalone" ? "standalone"
        : Hotspot.canShare ? "shared" : "standalone"

    onShownChanged: {
        if (!page.shown) return
        page.reveal = false
        page.qrShown = false
        page.picked = ""
        Hotspot.prepare()
    }

    function clientsText(n) { return n === 0 ? "None yet" : n + (n === 1 ? " device" : " devices") }

    Column {
        id: column
        anchors.centerIn: parent
        width: page.contentWidth
        spacing: Theme.sectionSpacing

        Item {
            width: parent.width
            height: 20
            Row {
                spacing: 6
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                BackButton { onClicked: page.back() }
                HeaderIcon {
                    glyph: Hotspot.active ? "\u{f0003}" : "\u{f1511}"
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Hotspot"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
            }
            Switch {
                anchors.right: parent.right
                // Follows the request right away while nmcli works.
                checked: Hotspot.pending === "on" || (Hotspot.active && Hotspot.pending !== "off") || Hotspot.starting
                onToggled: {
                    if (Hotspot.pending === "on" || Hotspot.pending === "off") return
                    if (Hotspot.active || Hotspot.starting) Hotspot.stop()
                    else Hotspot.start(page.mode)
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: Hotspot.error !== "" ? Hotspot.error
                : Hotspot.pending === "on" || Hotspot.starting ? "Starting…"
                : Hotspot.pending === "off" ? "Stopping…"
                : Hotspot.active ? (Hotspot.mode === "shared" ? "Sharing " + Hotspot.wifiName
                    : "On instead of Wi-Fi — devices get internet only if this PC is online another way")
                : "Off"
            color: Hotspot.error !== "" ? Theme.danger : Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        // --- How it runs ---
        Column {
            width: parent.width
            spacing: 6
            SectionLabel {
                text: "Internet"
            }
            Row {
                width: parent.width
                spacing: 6
                PageButton {
                    width: (parent.width - 6) / 2
                    label: "Share Wi-Fi"
                    selected: page.mode === "shared"
                    available: !Hotspot.active && Hotspot.canShare
                    onClicked: page.picked = "shared"
                }
                PageButton {
                    width: (parent.width - 6) / 2
                    label: "Without Wi-Fi"
                    selected: page.mode === "standalone"
                    available: !Hotspot.active
                    onClicked: page.picked = "standalone"
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: Hotspot.active ? "Stop the hotspot to change this"
                    : page.mode === "shared" ? "Wi-Fi stays connected and devices use " + Hotspot.wifiName
                    : (Hotspot.wifiConnected ? (Hotspot.shareProblem ? Hotspot.shareProblem + ": " : "")
                        + "Wi-Fi disconnects while the hotspot runs" : "Devices get no internet unless this PC is online another way")
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        // --- Network ---
        Column {
            width: parent.width
            spacing: 4
            SectionLabel {
                text: "Network"
            }
            InfoRow { label: "Name"; value: Hotspot.ssid || "…" }
            InfoRow {
                label: "Password"
                // Dots, not the length: a fixed count.
                value: Hotspot.password === "" ? "…" : page.reveal ? Hotspot.password : "••••••••••••"
                SmallButton {
                    label: page.reveal ? "Hide" : "Show"
                    onClicked: page.reveal = !page.reveal
                }
                SmallButton {
                    label: "Copy"
                    onClicked: Hotspot.copyPassword()
                }
            }
            InfoRow {
                visible: Hotspot.active
                label: "Connected"
                value: page.clientsText(Hotspot.clients)
            }
        }

        // --- QR code ---
        Column {
            width: parent.width
            spacing: 8
            PageButton {
                width: parent.width
                label: page.qrShown ? "Hide QR code" : "Show QR code"
                selected: page.qrShown
                available: Hotspot.password !== ""
                onClicked: {
                    page.qrShown = !page.qrShown
                    if (page.qrShown && Hotspot.qrRev === 0) Hotspot.makeQr()
                }
            }
            // Black on white with a quiet zone, whatever the theme: what
            // phone cameras read reliably.
            Rectangle {
                visible: page.qrShown
                anchors.horizontalCenter: parent.horizontalCenter
                width: 196
                height: 196
                radius: Theme.controlRadius
                color: "white"
                Image {
                    anchors.centerIn: parent
                    width: 180
                    height: 180
                    visible: Hotspot.qrRev > 0
                    source: Hotspot.qrRev > 0 ? "file://" + Hotspot.qrPath + "?" + Hotspot.qrRev : ""
                    cache: false
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    visible: Hotspot.qrRev === 0
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Hotspot.qrError || "…"
                    color: Theme.textOnLight
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            Text {
                visible: page.qrShown
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Scan with a phone's camera to join " + Hotspot.ssid
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    component PageButton: Rectangle {
        id: pb
        property string label: ""
        property bool selected: false
        property bool available: true
        signal clicked()
        height: Theme.controlHeight
        radius: Theme.controlRadius
        color: pb.selected ? Theme.selectedFill : pbArea.containsMouse && pb.available ? Theme.hoverFill : Theme.controlFill
        border.color: pb.selected ? Theme.accent : Theme.surfaceBorder
        border.width: 1
        opacity: pb.available || pb.selected ? 1 : 0.45
        Text {
            anchors.centerIn: parent
            text: pb.label
            color: pb.selected ? Theme.text : Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        MouseArea {
            id: pbArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: pb.available
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }
    // "Label            value [buttons]"
    component InfoRow: Item {
        id: ir
        property string label: ""
        property string value: ""
        default property alias buttons: irButtons.data
        width: parent ? parent.width : 0
        height: 26
        Text {
            id: irLabel
            width: 90
            anchors.verticalCenter: parent.verticalCenter
            text: ir.label
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            anchors.left: irLabel.right
            anchors.right: irButtons.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: ir.value
            color: Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Row {
            id: irButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
        }
    }
    component SmallButton: Rectangle {
        id: sb
        property string label: ""
        signal clicked()
        width: sbText.implicitWidth + 16
        height: 22
        radius: Theme.controlRadius
        color: sbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
        Text {
            id: sbText
            anchors.centerIn: parent
            text: sb.label
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        MouseArea {
            id: sbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }
}
