import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// The hub: one fixed card hanging from the clock, in three columns --
// notifications (one stack per app, in Messages / Today / Yesterday /
// Earlier), Today (month calendar + weather) and Controls -- with a system
// strip (CPU / RAM / GPU / network, System Update) under the first two.
// Clicking the clock opens it, and
// so does SUPER+N (it opens "quicksettings"). It replaced the bell's
// drawer and the Control Center's own bar icon.
//
// The Controls column is the Control Center itself: Bar.qml hands
// QuickSettings this card's `controlsSlot` as its popupHost, so its main
// page and every sub-page (Wi-Fi, Bluetooth, Sound, VPN...) render in that
// column instead of morphing the whole card. The card's size is the
// tallest of those pages (or the Today column) and stays put while you move
// between them -- only the column's content cross-fades (MorphContent).
// The hub is open while any of those pages is ("quicksettings"/"qs-*"), so
// QuickSettings' own focus grab and popup lock keep working unchanged.
// "hub" is the fallback id for when the Control Center widget is turned off
// in Bar Widgets: then this card has no Controls column and does its own
// click-outside close.
//
// Calendar events: none yet -- SichOS has no calendar source (no
// evolution-data-server/khal here); the grid is ready for event dots.
MorphContent {
    id: hub

    property string screenName: ""
    // The bar's Weather pill: its data (fed by weather.py) and its
    // iconFor()/textFor(), so the hub shows exactly what the pill does.
    property var weather: null
    // The bar window, so a click on the bar (the clock itself) doesn't
    // count as outside for the fallback grab below.
    property var barWindow: null
    // Cap for the card's height (the screen below the bar).
    property real maxHeight: 1000
    // The Control Center's SystemUpdate (QuickSettings.updater), for the
    // system strip's update cell; its page is "qs-update".
    property var updater: null

    readonly property Item controlsSlot: slot
    // QuickSettings' Phone page renders here, over the notifications column
    // (its phoneHost, Bar.qml) -- opened from the phone card.
    readonly property Item phoneSlot: phoneSlotItem
    readonly property bool phoneOpen: ShellState.activePopup === "qs-phone" && ShellState.activePopupScreen === hub.screenName
    readonly property real phoneHeight: Math.max(0, ...Array.from(phoneSlotItem.children).filter(c => !!c).map(c => c.implicitHeight))
    readonly property bool hasControls: slot.children.length > 0

    readonly property bool open: ShellState.activePopupScreen === hub.screenName
        && (ShellState.activePopup === "hub" || ShellState.activePopup === "quicksettings"
            || ShellState.activePopup.startsWith("qs-"))
    shown: hub.open

    function toggle() {
        if (hub.open) {
            ShellState.activePopup = ""
            return
        }
        ShellState.activePopupScreen = hub.screenName
        ShellState.activePopup = hub.hasControls ? "quicksettings" : "hub"
    }

    // Same as the Control Center's content width (QuickSettings.cardWidth),
    // so all three columns are equally wide.
    readonly property int columnWidth: 360
    readonly property int pad: Theme.surfacePadding

    // Widest/tallest Control Center page: the column is sized for all of
    // them at once, so switching pages never resizes the card.
    readonly property real controlsWidth: hub.hasControls
        ? Math.max(0, ...Array.from(slot.children).filter(c => !!c).map(c => c.implicitWidth)) : 0
    readonly property real controlsHeight: hub.hasControls
        ? Math.max(0, ...Array.from(slot.children).filter(c => !!c).map(c => c.implicitHeight)) : 0

    implicitWidth: hub.pad + hub.columnWidth + sep1.width + hub.columnWidth
        + (hub.hasControls ? sep2.width + hub.controlsWidth : hub.pad)
    implicitHeight: Math.min(hub.maxHeight, Math.max(600, hub.controlsHeight,
        today.implicitHeight + 2 * hub.pad + strip.height, hub.phoneHeight + strip.height))

    // --- Fallback close (no Control Center on this bar, see above) ---
    property bool _grabbing: false
    readonly property bool _ownOpen: ShellState.activePopup === "hub" && ShellState.activePopupScreen === hub.screenName
    on_OwnOpenChanged: {
        hub._grabbing = false
        if (hub._ownOpen) {
            grabTimer.restart()
            ShellState.lockPopups(["hub"], "hub", hub.screenName)
        } else if (ShellState.popupLockGroup.length === 1 && ShellState.popupLockGroup[0] === "hub") {
            ShellState.popupLockGroup = []
        }
    }
    Timer {
        id: grabTimer
        interval: 50
        onTriggered: hub._grabbing = hub._ownOpen
    }
    HyprlandFocusGrab {
        windows: [hub.QsWindow.window, hub.barWindow].filter(w => !!w)
        active: hub._grabbing
        onCleared: if (hub._ownOpen) ShellState.activePopup = ""
    }

    // Swallows clicks on the card's empty areas.
    MouseArea { anchors.fill: parent }

    Row {
        anchors.fill: parent

        Item { width: hub.pad; height: 1 }

        // Notifications and Today side by side, the system strip under both.
        Item {
            width: hub.columnWidth * 2 + sep1.width
            height: parent.height

        Row {
            id: leftColumns
            width: parent.width
            height: parent.height - strip.height

        // --- Notifications (and the phone card under them) ---
        Item {
            id: notifColumn
            width: hub.columnWidth
            height: parent.height

            readonly property int count: NotificationHistory.entries.length

            Item {
                id: notifHeader
                visible: !hub.phoneOpen
                y: hub.pad
                width: parent.width
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    SectionLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        bottomPadding: 0
                        text: "Notifications"
                    }
                    Rectangle {
                        visible: notifColumn.count > 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: countText.implicitHeight + 2
                        width: Math.max(height, countText.implicitWidth + 10)
                        radius: height / 2
                        color: Theme.controlFill
                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: "" + notifColumn.count
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                            color: Theme.textMuted
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    TextButton {
                        glyph: ShellState.notificationsMuted ? "\u{f009b}" : "\u{f009a}" // bell_off / bell
                        label: ShellState.notificationsMuted ? "Silenced" : "Silence"
                        active: ShellState.notificationsMuted
                        onClicked: ShellState.setNotificationsMuted(!ShellState.notificationsMuted, 0)
                    }
                    TextButton {
                        visible: notifColumn.count > 0
                        label: "Clear all"
                        onClicked: NotificationHistory.clear()
                    }
                }
            }

            Column {
                visible: notifColumn.count === 0 && !hub.phoneOpen
                anchors.horizontalCenter: parent.horizontalCenter
                y: (phoneCard.y - height) / 2
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f009a}" // nf-md-bell
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 18
                    color: Theme.textDim
                    opacity: 0.6
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                }
            }

            ListView {
                id: notifList
                visible: !hub.phoneOpen
                anchors.top: notifHeader.bottom
                anchors.topMargin: 6
                anchors.bottom: phoneCard.top
                anchors.bottomMargin: 8
                width: parent.width
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: hub.groupedEntries

                delegate: Loader {
                    id: row
                    required property var modelData
                    width: notifList.width
                    sourceComponent: row.modelData.header ? groupHeader : appStack

                    Component {
                        id: groupHeader
                        SectionLabel {
                            width: row.width
                            topPadding: 4
                            bottomPadding: 0
                            text: row.modelData.header
                        }
                    }
                    Component {
                        id: appStack
                        AppStack {
                            width: row.width
                            appKey: row.modelData.app
                            appName: row.modelData.name
                            entries: row.modelData.entries
                            expanded: !!hub.expandedApps[row.modelData.app]
                            onToggleExpanded: hub.setExpanded(row.modelData.app, !hub.expandedApps[row.modelData.app])
                            onActivated: (entry) => {
                                NotificationHistory.activate(entry)
                                ShellState.activePopup = ""
                            }
                        }
                    }
                }
            }
            PhoneCard {
                id: phoneCard
                visible: !hub.phoneOpen
                anchors.bottom: parent.bottom
                anchors.bottomMargin: hub.pad
                width: parent.width
                screenName: hub.screenName
            }
            // The Phone page, in place of the notifications while it's open.
            Item {
                id: phoneSlotItem
                anchors.fill: parent
                clip: true
            }
        }

        Separator { id: sep1 }


        // --- Today: calendar + weather ---
        Item {
            width: hub.columnWidth
            height: parent.height

            Column {
                id: today
                y: hub.pad
                width: parent.width
                spacing: Theme.sectionSpacing + 4

                MonthCalendar { width: parent.width; open: hub.open }

                Rectangle { width: parent.width; height: 1; color: Theme.separator }

                WeatherSection { width: parent.width; weather: hub.weather }
            }
        }

        }

        SystemStrip {
            id: strip
            anchors.bottom: parent.bottom
            width: parent.width
            updater: hub.updater
            screenName: hub.screenName
        }
        }

        Separator { id: sep2; visible: hub.hasControls }

        // --- Controls: QuickSettings' pages land here (see the top) ---
        Item {
            id: slot
            visible: hub.hasControls
            width: hub.controlsWidth
            height: parent.height
            clip: true
        }
    }

    // History as one stack per app -- every notification from the same app
    // together, however many others arrived in between (NotificationHistory
    // itself only folds *consecutive* same app + summary runs). Stacks are
    // ordered by their newest notification, and sit in the section of that
    // newest one: chat apps first ("Messages"), then the rest by day.
    // Entries are kept newest first, so each stack is too.
    readonly property var groupedEntries: {
        void hub.open // re-read "today" whenever the card opens
        const now = new Date()
        const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const startYesterday = startToday - 86400000
        const apps = []
        const byKey = {}
        for (const e of NotificationHistory.entries) {
            const key = hub.appKey(e)
            if (!byKey[key]) {
                byKey[key] = { app: key, name: e.appName || e.desktopEntry || "Notifications", entries: [] }
                apps.push(byKey[key])
            }
            byKey[key].entries.push(e)
        }
        const sections = { "Messages": [], "Today": [], "Yesterday": [], "Earlier": [] }
        for (const a of apps) {
            const newest = a.entries[0]
            if (hub.isMessage(newest)) sections["Messages"].push(a)
            else if (newest.time >= startToday) sections["Today"].push(a)
            else if (newest.time >= startYesterday) sections["Yesterday"].push(a)
            else sections["Earlier"].push(a)
        }
        const out = []
        for (const label of ["Messages", "Today", "Yesterday", "Earlier"]) {
            if (sections[label].length === 0) continue
            out.push({ header: label })
            for (const a of sections[label]) out.push(a)
        }
        return out
    }
    // Same app: by sender name (what the toast shows), else desktop entry.
    function appKey(e) {
        return (e.appName || e.desktopEntry || "").toLowerCase()
    }
    // Stacks opened with "Show all", by appKey; all fold again on close.
    property var expandedApps: ({})
    function setExpanded(key, on) {
        const next = Object.assign({}, hub.expandedApps)
        if (on) next[key] = true
        else delete next[key]
        hub.expandedApps = next
    }
    onOpenChanged: if (!hub.open) hub.expandedApps = ({})
    // A chat app, by name, desktop entry or (phone notifications, see
    // NotificationEntry.phonePackage) Android package.
    function isMessage(e) {
        const s = [e.appName, e.desktopEntry, e.appIcon].filter(x => !!x).join(" ").toLowerCase()
        return /telegram|discord|vesktop|element|signal|whatsapp|slack|beeper|viber|messag|teams|matrix|fractal|nheko|thunderbird-chat|skype|zulip|mattermost/.test(s)
    }

    // --- Pieces ---

    // The paired phone (sichlink), above the notifications' bottom edge: a
    // small phone with its own wallpaper, its name, lock / battery state and
    // what's running (mirror, drive, display), and the actions -- Mirror,
    // Files, then Unlock while locked or Display. The card (or its chevron)
    // opens the Phone page in this column. Not paired / no daemon: its state
    // and a way to the page.
    component PhoneCard: Rectangle {
        id: pc
        property string screenName: ""
        // Connected, else the paired one we last knew (name, wallpaper).
        readonly property var d: Sichlink.phone || (Sichlink.devices || []).find(x => x.trusted) || null
        readonly property bool online: !!(pc.d && pc.d.connected)
        readonly property bool mirroring: PhoneMirrorState.open && !PhoneMirrorState.collapsed
        readonly property string wallpaper: Sichlink.wallpaperUrl(pc.d)
        readonly property real ratio: pc.d && pc.d.screen_width > 0 ? pc.d.screen_height / pc.d.screen_width : 2.1
        function openPage() {
            ShellState.activePopupScreen = pc.screenName
            ShellState.activePopup = "qs-phone"
        }
        readonly property string statusLine: !pc.d ? Sichlink.stateText
            : !pc.online ? "Offline"
            : [Sichlink.lockText(pc.d), Sichlink.batteryText(pc.d)].filter(t => t !== "").join(" · ")
        readonly property string activityLine: !pc.online ? (pc.d ? "Last seen paired" : "")
            : [PhoneMirrorState.loading ? "Mirror connecting…" : PhoneMirrorState.open ? (PhoneMirrorState.collapsed ? "Mirror hidden" : "Mirroring") : "",
               Sichlink.driveMounted ? "Files at ~/Phone" : "",
               Sichlink.displayOn ? "Extra display" : ""].filter(t => t !== "").join(" · ")
        readonly property var actions: !pc.d ? [{ label: "Set up", action: () => pc.openPage() }]
            : [{ label: PhoneMirrorState.toggleLabel, selected: pc.mirroring, available: PhoneMirrorState.open || pc.online,
                 action: () => PhoneMirrorState.toggle(pc.screenName) },
               { label: Sichlink.driveBusy ? "Mounting…" : "Files", selected: Sichlink.driveMounted,
                 available: !Sichlink.driveBusy && (Sichlink.driveMounted || pc.online),
                 action: () => {
                     if (!Sichlink.driveMounted) { Sichlink.setDrive(true); return }
                     ShellState.activePopup = ""
                     Sichlink.openDrive()
                 } },
               pc.online && pc.d.locked ? { label: "Unlock", action: () => Sichlink.wake(pc.d.id) }
                 : { label: Sichlink.displayStarting ? "Starting…" : "Display", selected: Sichlink.displayOn, available: pc.online,
                     action: () => Sichlink.setDisplay(!Sichlink.displayOn) }]

        height: 104
        radius: Theme.controlRadius
        color: pcArea.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Theme.controlFill
        border.color: pc.mirroring ? Theme.accent : Theme.surfaceBorder
        border.width: 1

        MouseArea {
            id: pcArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pc.openPage()
        }

        // A small phone: the image at the phone's own screen ratio, the
        // border standing in for the bezel (like the Phone page's card).
        ClippingRectangle {
            id: pcPhone
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round((parent.height - 20) / pc.ratio)
            height: parent.height - 20
            radius: 8
            color: Theme.surfaceRaised
            border.width: 2
            border.color: Theme.surfaceRaised
            Image {
                id: pcWall
                anchors.fill: parent
                visible: pc.wallpaper !== ""
                source: pc.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.height: 168
                opacity: pc.online ? 1 : 0.45
            }
            Text {
                visible: pc.wallpaper === ""
                anchors.centerIn: parent
                text: "\u{f011c}" // nf-md-cellphone
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 5
                color: pc.online ? Theme.text : Theme.textMuted
            }
        }
        // Online dot (outside the clipped phone).
        Rectangle {
            visible: pc.online
            x: pcPhone.x + pcPhone.width - 7
            y: pcPhone.y - 3
            width: 10
            height: 10
            radius: 5
            color: Theme.success
            border.color: Theme.surface
            border.width: 2
        }

        Column {
            anchors.left: pcPhone.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.topMargin: 10
            spacing: 2
            Item {
                width: parent.width
                height: pcName.implicitHeight
                Text {
                    id: pcName
                    width: parent.width - 20
                    elide: Text.ElideRight
                    text: pc.d ? pc.d.name : "Phone"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0142}" // nf-md-chevron_right
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    color: pcArea.containsMouse ? Theme.text : Theme.textMuted
                }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: pc.statusLine
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textMuted
            }
            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                text: pc.activityLine
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
                color: pc.mirroring ? Theme.accentHover : Theme.textDim
            }
        }
        Row {
            anchors.left: pcPhone.right
            anchors.leftMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            spacing: 4
            Repeater {
                model: pc.actions
                delegate: SmallButton {
                    required property var modelData
                    label: modelData.label
                    selected: !!modelData.selected
                    available: modelData.available !== false
                    onClicked: modelData.action()
                }
            }
        }
    }

    component SmallButton: Rectangle {
        id: sb
        property string label: ""
        property bool selected: false
        // Dimmed and inert when false (phone offline).
        property bool available: true
        signal clicked()
        opacity: sb.available ? 1 : 0.4
        width: sbText.implicitWidth + 16
        height: Theme.controlHeight - 2
        radius: Theme.controlRadius
        color: sb.selected ? Theme.selectedFill : sbArea.containsMouse ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.08)
        Text {
            id: sbText
            anchors.centerIn: parent
            text: sb.label
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
            color: sb.selected ? Theme.text : Theme.textMuted
        }
        MouseArea {
            id: sbArea
            anchors.fill: parent
            enabled: sb.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }

    // Under the notifications and Today columns: CPU / RAM / GPU / network
    // with their recent history (SystemStats, which polls only while the hub
    // is open), then System Update's state. A stat opens btop (floated like
    // SUPER+B); the update cell opens the System Update page in Controls.
    // This replaced the Control Center's System and Updates tiles.
    component SystemStrip: Item {
        id: ss
        property var updater: null
        property string screenName: ""
        // Cells as tall as the Controls footer's two pill rows (28 + gap +
        // 28) and padded like it, so the strip and the footer line up.
        readonly property real cellHeight: 28 * 2 + Theme.sectionSpacing
        height: 1 + Theme.surfacePadding + ss.cellHeight + Theme.surfacePadding

        function pct(v) { return Math.round(Math.max(0, v) * 100) + "%" }
        function btop() {
            ShellState.activePopup = ""
            Quickshell.execDetached(["kitty", "--class", "btop", "-e", "btop"])
        }
        readonly property var u: ss.updater
        readonly property string updateTitle: !ss.u ? "Updates"
            : ss.u.updating ? "Updating…"
            : ss.u.rebootNeeded ? "Restart needed"
            : ss.u.count === null ? (ss.u.checking ? "Checking…" : "Unknown")
            : ss.u.count === 0 ? "Up to date"
            : ss.u.count + (ss.u.count === 1 ? " update" : " updates")
        readonly property string updateSub: !ss.u ? ""
            : [ss.u.dnfCount ? ss.u.dnfCount + " dnf" : "", ss.u.flatpakCount ? ss.u.flatpakCount + " flatpak" : ""]
                .filter(t => t).join(" · ") || (ss.u.rebootNeeded ? "To finish the update" : "System")
        readonly property var cells: [
            { label: "CPU", value: ss.pct(SystemStats.cpu),
              extra: SystemStats.temp > 0 ? Math.round(SystemStats.temp) + "°C" : "", history: SystemStats.cpuHistory, max: 1 },
            { label: "RAM", value: SystemStats.ramUsedGb.toFixed(1) + " / " + Math.round(SystemStats.ramTotalGb) + " GB",
              extra: SystemStats.diskTotalGb > 0 ? "disk " + Math.round(SystemStats.diskUsedGb / SystemStats.diskTotalGb * 100) + "%" : "",
              history: SystemStats.ramHistory, max: 1 },
            { label: "GPU", value: ss.pct(SystemStats.gpu),
              extra: SystemStats.gpuTemp > 0 ? Math.round(SystemStats.gpuTemp) + "°C" : "", history: SystemStats.gpuHistory, max: 1,
              hide: SystemStats.gpu < 0 },
            { label: "Network", value: "↓" + SystemStats.rateText(SystemStats.netRx),
              extra: "↑" + SystemStats.rateText(SystemStats.netTx), history: SystemStats.netRxHistory, max: 0 }
        ].filter(c => !c.hide)

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        Row {
            id: cellRow
            y: 1 + Theme.surfacePadding
            width: parent.width
            height: ss.cellHeight
            spacing: 6
            readonly property real cellWidth: (width - spacing * ss.cells.length) / (ss.cells.length + 1)

            // Keyed by index, not the array: `cells` is rebuilt on every
            // sample, and as a model that recreated every cell each time --
            // the graphs blinked through a blank canvas.
            Repeater {
                model: ss.cells.length
                delegate: Rectangle {
                    id: cell
                    required property int index
                    readonly property var modelData: ss.cells[cell.index] || ({})
                    width: cellRow.cellWidth
                    height: cellRow.height
                    radius: Theme.controlRadius
                    color: cellArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                    Text {
                        id: cellLabel
                        x: 8
                        y: 7
                        text: (cell.modelData.label || "").toUpperCase()
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                        font.letterSpacing: 1
                        color: Theme.textDim
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.baseline: cellLabel.baseline
                        text: cell.modelData.extra
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: Theme.textDim
                    }
                    Text {
                        x: 8
                        y: 21
                        width: parent.width - 16
                        elide: Text.ElideRight
                        text: cell.modelData.value
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                        color: Theme.text
                    }
                    MiniGraph {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: 26
                        history: cell.modelData.history
                        maxValue: cell.modelData.max
                        opacity: 0.8
                    }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ss.btop()
                    }
                }
            }

            // System Update
            Rectangle {
                visible: !!ss.u
                width: cellRow.cellWidth
                height: cellRow.height
                radius: Theme.controlRadius
                color: updArea.containsMouse ? Theme.hoverFill
                    : ss.u && (ss.u.count > 0 || ss.u.rebootNeeded) ? Theme.selectedFill : Theme.controlFill
                Text {
                    id: updGlyph
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f06b0}" // nf-md-update
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                    color: Theme.textMuted
                    opacity: ss.u && (ss.u.updating || ss.u.checking) ? 0.5 : 1
                }
                Column {
                    anchors.left: updGlyph.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: ss.updateTitle
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                        color: Theme.text
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: ss.updateSub
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 4
                        color: Theme.textDim
                    }
                }
                MouseArea {
                    id: updArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ShellState.activePopupScreen = ss.screenName
                        ShellState.activePopup = "qs-update"
                    }
                }
            }
        }
    }

    // One app's notifications. A single one is just its card; more get a
    // header (name, count, Show all / Show less, clear this app's) and,
    // folded, only the newest card with the rest peeking out beneath it.
    component AppStack: Column {
        id: stack
        property string appKey: ""
        property string appName: ""
        property var entries: []
        property bool expanded: false
        signal toggleExpanded()
        signal activated(var entry)
        readonly property bool multi: stack.entries.length > 1
        spacing: 6

        Item {
            visible: stack.multi
            width: parent.width
            height: 18
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stack.appName
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: true
                    color: Theme.textMuted
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: stackCount.implicitHeight + 2
                    width: Math.max(height, stackCount.implicitWidth + 10)
                    radius: height / 2
                    color: Theme.controlFill
                    Text {
                        id: stackCount
                        anchors.centerIn: parent
                        text: "" + stack.entries.length
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                        color: Theme.textMuted
                    }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                TextButton {
                    label: stack.expanded ? "Show less" : "Show all"
                    onClicked: stack.toggleExpanded()
                }
                TextButton {
                    glyph: "\u{f0156}" // nf-md-close
                    onClicked: NotificationHistory.removeMany(stack.entries.map(e => e.id))
                }
            }
        }

        // Folded: the newest card, one sliver under it per hidden card (up
        // to two). Card fills are translucent, so a sliver must not run
        // under the card above it -- it would show through. Each one is
        // clipped to the strip below that card; the rounded rectangle
        // inside reaches up past the clip, so only its bottom edge and
        // corners are drawn.
        Item {
            id: folded
            visible: !stack.expanded || !stack.multi
            readonly property int sliverCount: stack.multi ? Math.min(2, stack.entries.length - 1) : 0
            readonly property int sliverHeight: 8
            width: parent.width
            height: newestCard.height + folded.sliverCount * folded.sliverHeight
            Repeater {
                model: folded.sliverCount
                delegate: Item {
                    required property int index
                    readonly property int inset: 10 * (index + 1)
                    x: inset
                    y: newestCard.height + index * folded.sliverHeight
                    width: folded.width - 2 * inset
                    height: folded.sliverHeight
                    clip: true
                    Rectangle {
                        y: -Theme.controlRadius
                        width: parent.width
                        height: parent.height + Theme.controlRadius
                        radius: Theme.controlRadius
                        color: sliverMouse.containsMouse ? Theme.hoverFill
                            : Qt.rgba(1, 1, 1, index === 0 ? 0.05 : 0.035)
                        border.color: Theme.surfaceBorder
                        border.width: Theme.surfaceBorderWidth
                    }
                }
            }
            // The slivers are the hidden cards: clicking them unfolds.
            MouseArea {
                id: sliverMouse
                visible: folded.sliverCount > 0
                y: newestCard.height
                width: parent.width
                height: parent.height - newestCard.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: stack.toggleExpanded()
            }
            NotificationEntry {
                id: newestCard
                width: parent.width
                entry: stack.entries.length > 0 ? stack.entries[0] : ({})
                onActivated: stack.activated(newestCard.entry)
            }
        }

        // Unfolded: every card.
        Repeater {
            model: stack.expanded && stack.multi ? stack.entries : []
            delegate: NotificationEntry {
                required property var modelData
                width: stack.width
                entry: modelData
                onActivated: stack.activated(modelData)
            }
        }
    }

    component Separator: Item {
        width: 2 * Theme.surfacePadding + 1
        height: parent ? parent.height : 0
        Rectangle {
            x: Theme.surfacePadding
            y: Theme.surfacePadding
            width: 1
            height: parent.height - 2 * Theme.surfacePadding
            color: Theme.separator
        }
    }

    // Small text button in a column header ("Clear all", "Silence").
    component TextButton: Item {
        id: tb
        property string label: ""
        property string glyph: ""
        property bool active: false
        signal clicked()
        implicitWidth: tbRow.implicitWidth
        implicitHeight: tbRow.implicitHeight
        Row {
            id: tbRow
            spacing: 4
            Text {
                visible: tb.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: tb.glyph
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                color: tbLabel.color
            }
            Text {
                id: tbLabel
                text: tb.label
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
                color: tbArea.containsMouse ? Theme.text : tb.active ? Theme.accentHover : Theme.textMuted
            }
        }
        MouseArea {
            id: tbArea
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }

    // Month grid, Monday first, always six rows (so its height never
    // changes from month to month). The month name returns to today.
    component MonthCalendar: Column {
        id: cal
        spacing: 6

        property date today: new Date()
        property date viewDate: new Date()
        // Bound to the hub's `open`: back to the current month on every open.
        property bool open: false
        onOpenChanged: {
            if (!cal.open) return
            cal.today = new Date()
            cal.viewDate = new Date()
        }
        function shift(delta) {
            cal.viewDate = new Date(cal.viewDate.getFullYear(), cal.viewDate.getMonth() + delta, 1)
        }
        readonly property bool isCurrentMonth: cal.viewDate.getFullYear() === cal.today.getFullYear()
            && cal.viewDate.getMonth() === cal.today.getMonth()
        // 42 cells: {day, inMonth, weekend, isToday}
        readonly property var cells: {
            const y = cal.viewDate.getFullYear(), m = cal.viewDate.getMonth()
            const lead = (new Date(y, m, 1).getDay() + 6) % 7
            const out = []
            for (let i = 0; i < 42; i++) {
                const d = new Date(y, m, 1 - lead + i)
                out.push({
                    day: d.getDate(),
                    inMonth: d.getMonth() === m,
                    weekend: i % 7 >= 5,
                    isToday: d.getFullYear() === cal.today.getFullYear() && d.getMonth() === cal.today.getMonth()
                        && d.getDate() === cal.today.getDate()
                })
            }
            return out
        }

        Item {
            width: parent.width
            height: 30
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                    id: monthName
                    text: Qt.locale().standaloneMonthName(cal.viewDate.getMonth())
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize + 9
                    font.weight: Font.DemiBold
                    color: monthArea.containsMouse && !cal.isCurrentMonth ? Theme.accentHover : Theme.text
                    MouseArea {
                        id: monthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: cal.isCurrentMonth ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: { cal.today = new Date(); cal.viewDate = new Date() }
                    }
                }
                Text {
                    anchors.baseline: monthName.baseline
                    text: cal.viewDate.getFullYear()
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: [{ glyph: "\u{f0141}", delta: -1 }, { glyph: "\u{f0142}", delta: 1 }] // chevron_left / _right
                    delegate: Rectangle {
                        id: navButton
                        required property var modelData
                        width: 26
                        height: 26
                        radius: Theme.controlRadius
                        color: navArea.containsMouse ? Theme.hoverFill : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: navButton.modelData.glyph
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                            color: Theme.textMuted
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cal.shift(navButton.modelData.delta)
                        }
                    }
                }
            }
        }

        Grid {
            columns: 7
            rowSpacing: 2
            readonly property real cellWidth: Math.floor(cal.width / 7)

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                delegate: Text {
                    required property string modelData
                    width: parent.cellWidth
                    height: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                    color: Theme.textDim
                }
            }
            Repeater {
                model: cal.cells
                delegate: Item {
                    id: dayCell
                    required property var modelData
                    width: parent.cellWidth
                    height: 32
                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: 28
                        radius: Theme.controlRadius
                        color: dayCell.modelData.isToday ? Theme.accent
                            : dayArea.containsMouse ? Theme.controlFill : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.modelData.day
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: dayCell.modelData.isToday
                        color: dayCell.modelData.isToday ? Theme.text
                            : !dayCell.modelData.inMonth ? Qt.rgba(1, 1, 1, 0.22)
                            : dayCell.modelData.weekend ? Theme.textMuted : Theme.text
                    }
                    MouseArea {
                        id: dayArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }
    }

    // Now / the next hours / the next days, from the bar's Weather pill.
    component WeatherSection: Column {
        id: ws
        property var weather: null
        // The weather glyphs are wide: the Mono Nerd Font squeezes them into
        // one cell (about half size, however big the font); the proportional
        // one draws them full width.
        readonly property string iconFont: "JetBrainsMono Nerd Font"
        readonly property bool ready: !!ws.weather && ws.weather.haveData
        spacing: 14

        Text {
            visible: !ws.ready
            text: "Weather unavailable"
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.textDim
        }

        // Now
        Row {
            visible: ws.ready
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ws.ready ? ws.weather.iconFor(ws.weather.code, ws.weather.isDay) : ""
                font.family: ws.iconFont
                font.pixelSize: Theme.fontSize + 25
                color: Theme.textMuted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ws.ready ? Math.round(ws.weather.tempC) + "°" : ""
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize + 21
                font.weight: Font.Light
                color: Theme.text
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: ws.ready ? [ws.weather.textFor(ws.weather.code), ws.weather.city].filter(x => !!x).join(" · ") : ""
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    readonly property var t: ws.ready ? ws.weather.today : null
                    text: {
                        if (!ws.ready) return ""
                        const parts = []
                        if (ws.weather.feelsLikeC !== null) parts.push("Feels " + Math.round(ws.weather.feelsLikeC) + "°")
                        if (t) parts.push("H " + Math.round(t.tempMax) + "° L " + Math.round(t.tempMin) + "°")
                        return parts.join(" · ")
                    }
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.textDim
                }
                Text {
                    text: {
                        if (!ws.ready) return ""
                        const parts = []
                        if (ws.weather.windKph !== null) parts.push("Wind " + Math.round(ws.weather.windKph) + " km/h")
                        if (ws.weather.humidity !== null) parts.push("Humidity " + Math.round(ws.weather.humidity) + "%")
                        return parts.join(" · ")
                    }
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.textDim
                }
            }
        }

        // The next eight hours
        Row {
            visible: ws.ready && ws.weather.hourly.length > 0
            width: parent.width
            Repeater {
                model: ws.ready ? ws.weather.hourly.slice(0, 8) : []
                delegate: Column {
                    id: hourCell
                    required property var modelData
                    width: ws.width / 8
                    spacing: 4
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (hourCell.modelData.hour || "").slice(0, 2)
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: Theme.textDim
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ws.weather.iconFor(hourCell.modelData.code, hourCell.modelData.isDay)
                        font.family: ws.iconFont
                        font.pixelSize: Theme.fontSize + 10
                        color: Theme.textMuted
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(hourCell.modelData.tempC) + "°"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                        color: Theme.text
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Rain chance only once it's worth noticing.
                        text: hourCell.modelData.precipProb >= 20 ? hourCell.modelData.precipProb + "%" : " "
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 4
                        color: Theme.accentHover
                    }
                }
            }
        }

        // The next five days, range bars on one shared scale (like the
        // Weather popup's week), a dot for now on today's.
        Column {
            visible: ws.ready && ws.weather.daily.length > 0
            width: parent.width
            spacing: 2
            Repeater {
                model: ws.ready ? ws.weather.daily.slice(0, 5) : []
                delegate: Item {
                    id: dayRow
                    required property var modelData
                    required property int index
                    readonly property real lo: ws.weather.weekMin
                    readonly property real span: Math.max(1, ws.weather.weekMax - ws.weather.weekMin)
                    width: ws.width
                    height: 30
                    Text {
                        id: dayName
                        width: 46
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (dayRow.index === 0) return "Today"
                            const p = (dayRow.modelData.date || "").split("-")
                            return Qt.formatDate(new Date(+p[0], +p[1] - 1, +p[2]), "ddd")
                        }
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.text
                    }
                    Text {
                        id: dayIcon
                        anchors.left: dayName.right
                        width: 36
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: ws.weather.iconFor(dayRow.modelData.code, true)
                        font.family: ws.iconFont
                        font.pixelSize: Theme.fontSize + 7
                        color: Theme.textMuted
                    }
                    Text {
                        id: dayLo
                        anchors.left: dayIcon.right
                        width: 34
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(dayRow.modelData.tempMin) + "°"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textDim
                    }
                    Text {
                        id: dayHi
                        anchors.right: parent.right
                        width: 32
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(dayRow.modelData.tempMax) + "°"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.text
                    }
                    Rectangle {
                        id: rangeTrack
                        anchors.left: dayLo.right
                        anchors.leftMargin: 10
                        anchors.right: dayHi.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5
                        radius: height / 2
                        color: Theme.track
                        Rectangle {
                            x: rangeTrack.width * (dayRow.modelData.tempMin - dayRow.lo) / dayRow.span
                            width: Math.max(height, rangeTrack.width * (dayRow.modelData.tempMax - dayRow.modelData.tempMin) / dayRow.span)
                            height: parent.height
                            radius: height / 2
                            color: Theme.accentHover
                        }
                        Rectangle {
                            visible: dayRow.index === 0 && ws.weather.tempC !== null
                            width: 9
                            height: 9
                            radius: 4.5
                            anchors.verticalCenter: parent.verticalCenter
                            x: rangeTrack.width * Math.max(0, Math.min(1, (ws.weather.tempC - dayRow.lo) / dayRow.span)) - width / 2
                            color: Theme.text
                            border.color: Theme.surface
                            border.width: 2
                        }
                    }
                }
            }
        }
    }
}
