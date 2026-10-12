import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
// Qualified: UPower's own PowerProfile enum would otherwise shadow this
// directory's PowerProfile.qml widget.
import Quickshell.Services.UPower as UP

// Control Center: one bar pill (network + battery icons) standing in for the
// Network, Bluetooth, Volume, Backlight, Power Profile, Battery, Display and
// Phone Mirror widgets, with a hover card holding all of them plus the
// toggle row's switches (Night Light, Silence, Mic, Stay Awake, Game Focus,
// HDR, Opaque -- the row next to the clock stays too; both drive the same
// ShellState/HdrSettings/GameFocus state), a media player and sliders.
//
// The bar icons are the standalone widgets themselves, `interactive: false`
// so their own MouseAreas (tooltips, clicks) stay out of the way and this
// pill's MouseArea gets all input -- no second copy of their icon/ink-size
// logic. Submenus morph the same MorphPopup card: Bluetooth and Display are
// hidden instances of BluetoothIndicator/DisplaySettings with their own
// popupIds (their header's back arrow returns here); Sound (output/input
// devices, mic level) is this file's own second page, `qs-audio`.
Pill {
    id: root
    property string screenName: ""
    // Set by Bar.qml: the bar's MorphPopup card (see MorphContent.qml).
    property Item popupHost: null

    readonly property real cardWidth: 360

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var battery: UP.UPower.displayDevice

    readonly property var audioNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var sinks: root.audioNodes.filter(n => n.isSink)
    readonly property var sources: root.audioNodes.filter(n => !n.isSink)

    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => !!n)
    }

    // Every MPRIS player with something loaded, playing ones first (then
    // Spotify, NowPlayingState's) -- one card each, up to three.
    readonly property var players: Mpris.players.values
        .filter(p => p.isPlaying || !!p.trackTitle)
        .sort((a, b) => {
            if (a.isPlaying !== b.isPlaying) return a.isPlaying ? -1 : 1
            return (b === NowPlayingState.spotify) - (a === NowPlayingState.spotify)
        })
        .slice(0, 3)
    // Only ever a local file:// cover: a remote https art URL loaded by an
    // Image in every bar's card is the crash NowPlayingState.artPath exists
    // to avoid. Spotify's gets downloaded there; browsers already hand out
    // file:// URLs; anything else shows the music glyph instead.
    function artFor(p) {
        if (!p) return ""
        if (p === NowPlayingState.spotify) return NowPlayingState.artPath
        return (p.trackArtUrl || "").startsWith("file://") ? p.trackArtUrl : ""
    }

    // --- Bar icons: network and battery; everything else lives in the card ---
    NetworkIndicator { id: net; interactive: false; horizontalPadding: 0 }
    // Not a bar icon -- just the Bluetooth submenu (and connected-device
    // state for the card's tile).
    BluetoothIndicator {
        id: bt
        visible: false
        screenName: root.screenName
        popupHost: root.popupHost
        popupId: "qs-bluetooth"
        closeOnLeave: false
        // Same width as this card, so the submenu doesn't shrink under the cursor.
        popupWidth: root.cardWidth + 2 * Theme.surfacePadding
        popupAnchor: root
        backPopupId: root.popupId
    }
    // Hidden: no bar icon, kept for the pill's scroll-to-change-volume and
    // the card slider's glyph.
    Volume { id: vol; visible: false }
    Battery { interactive: false; horizontalPadding: 0 }
    DisplaySettings {
        id: disp
        visible: false
        screenName: root.screenName
        popupHost: root.popupHost
        popupId: "qs-display"
        closeOnLeave: false
        popupContentWidth: root.cardWidth
        popupAnchor: root
        backPopupId: root.popupId
    }
    // The Update tile's state and its "qs-update" page (same embedding as
    // Bluetooth/Display above). Its own pending-update poll runs here too.
    SystemUpdate {
        id: upd
        visible: false
        screenName: root.screenName
        popupHost: root.popupHost
        popupId: "qs-update"
        popupWidth: root.cardWidth + 2 * Theme.surfacePadding
        closeOnLeave: false
        popupAnchor: root
        backPopupId: root.popupId
    }

    onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
        } else if (!root.popupOpen) {
            // Open only; closing is a click outside (see the focus grab).
            root.openPopup(root.popupId)
        }
    }
    onWheel: (event) => vol.wheel(event)

    function openPopup(id) {
        ShellState.activePopup = id
        ShellState.activePopupScreen = root.screenName
    }

    // --- Opens on click only (hover just outlines the pill, below) and
    // closes only on a click outside: unlike a glance-and-go popup, this
    // card gets worked in, and drifting off its edge shouldn't throw it
    // away. ---
    readonly property string popupId: "quicksettings"
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool audioOpen: ShellState.activePopup === "qs-audio" && ShellState.activePopupScreen === root.screenName

    // macOS-menu-bar-style hover highlight: the only sign this pill is
    // clickable now that hovering doesn't open anything. Hidden while the
    // card is open. Assigned to a property with an explicit parent, not
    // declared as a child -- Pill's default property would lay it out in
    // the icon Row.
    readonly property Item _highlight: Rectangle {
        parent: root
        z: -1
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        radius: Theme.barItemRadius
        color: Theme.barItemHover
        opacity: root.hovered && !root.anyOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
    }

    // Any page of this card, including the embedded Bluetooth/Display ones.
    readonly property bool anyOpen: ShellState.activePopupScreen === root.screenName
        && root.pageIds.includes(ShellState.activePopup)

    // Click-outside close. Activated a tick after opening, not bound
    // straight to anyOpen -- see WorkspaceMenu.qml: bound directly, the grab
    // can silently fail to take. The bar is whitelisted so clicking the pill
    // (or the bar around it) doesn't count as outside.
    property bool grabbing: false
    readonly property bool typing: ShellState.keySink !== null && ShellState.keySinkScreen === root.screenName
    readonly property var pageIds: ["quicksettings", "qs-audio", "qs-wifi", "qs-bluetooth", "qs-display",
        "qs-update", "qs-hdr", "qs-sunset", "qs-idle", "qs-gamefocus", "qs-phone"]
    onAnyOpenChanged: {
        root.grabbing = false
        if (root.anyOpen) grabTimer.restart()
        // While open, no other bar popup may take over (see
        // ShellState.popupLockGroup). Released only once no screen's card
        // is open -- moving it to another screen flips two instances'
        // anyOpen in either order.
        if (root.anyOpen) ShellState.lockPopups(root.pageIds, ShellState.activePopup, root.screenName)
        else if (!root.pageIds.includes(ShellState.activePopup)) ShellState.popupLockGroup = []
    }
    Timer {
        id: grabTimer
        interval: 50
        onTriggered: root.grabbing = root.anyOpen
    }
    HyprlandFocusGrab {
        windows: [root.QsWindow.window, root.popupHost ? root.popupHost.QsWindow.window : null].filter(w => !!w)
        // Off while a field in one of its pages (PIN, Wi-Fi password) has the
        // keyboard: the bar taking exclusive keyboard focus (ShellState.keySink)
        // makes Hyprland clear the grab, and onCleared closed the whole card
        // the moment the field opened. Re-armed when the field lets go.
        active: root.grabbing && !root.typing
        onCleared: if (root.anyOpen && !root.typing) ShellState.activePopup = ""
    }

    function nodeName(n) {
        return n ? (n.description || n.nickname || n.name || "") : ""
    }

    // --- Main page ---
    readonly property Item _popupContent: MorphContent {
        id: panel
        parent: root.popupHost
        anchorItem: root
        shown: root.popupOpen


        implicitWidth: root.cardWidth + 2 * Theme.surfacePadding
        implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

        // Same sysfs node Backlight.qml/BacklightOSD.qml read.
        readonly property bool hasBacklight: blMax.text().length > 0
        readonly property real backlight: panel.hasBacklight && blBrightness.text().length > 0
            ? Number(blBrightness.text()) / Number(blMax.text()) : 0
        FileView {
            id: blBrightness
            path: "/sys/class/backlight/amdgpu_bl1/brightness"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
        }
        FileView {
            id: blMax
            path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
            printErrors: false
        }
        // A drag fires far more position changes than brightnessctl calls
        // are worth; only the latest value per tick gets written.
        property int pendingBacklight: -1
        Timer {
            id: backlightTimer
            interval: 40
            onTriggered: {
                if (panel.pendingBacklight < 0) return
                Quickshell.execDetached(["brightnessctl", "-n2", "set", panel.pendingBacklight + "%"])
                panel.pendingBacklight = -1
            }
        }
        function setBacklight(v) {
            panel.pendingBacklight = Math.round(Math.max(0.01, Math.min(1, v)) * 100)
            if (!backlightTimer.running) backlightTimer.start()
        }

        function batteryText() {
            const d = root.battery
            if (!d || !d.isPresent) return ""
            const pct = Math.round(d.percentage * 100) + "%"
            if (d.state === UP.UPowerDeviceState.FullyCharged) return pct + " · full"
            const secs = d.state === UP.UPowerDeviceState.Charging ? d.timeToFull : d.timeToEmpty
            if (!(secs > 0)) return pct + (d.state === UP.UPowerDeviceState.Charging ? " · charging" : "")
            const h = Math.floor(secs / 3600)
            const m = Math.round((secs % 3600) / 60)
            const t = (h > 0 ? h + "h " : "") + m + "m"
            return pct + " · " + t + (d.state === UP.UPowerDeviceState.Charging ? " to full" : " left")
        }

        readonly property string wifiSubtitle: !net.wifiDevice ? (net.wiredUp ? "Ethernet" : "No adapter")
            : !Networking.wifiEnabled ? "Off"
            : net.wifiUp && net.wifiNetwork ? net.wifiNetwork.name
            : net.wiredUp ? "Ethernet" : "Not connected"
        readonly property string btSubtitle: !root.adapter ? "No adapter"
            : !root.adapter.enabled ? "Off"
            : bt.connectedDevices.length > 0 ? bt.connectedDevices.map(d => d.name || d.deviceName).join(", ")
            : "On"

        readonly property bool micMuted: !!(root.source && root.source.audio && root.source.audio.muted)

        // Android-style edit mode (pencil in the header): drag tiles to
        // reorder, drag an edge/corner to resize, remove, add spare ones.
        // Layout lives in ControlCenterTiles.
        property bool editing: false
        onShownChanged: if (!panel.shown) panel.editing = false

        readonly property bool airplane: !Networking.wifiEnabled && !(root.adapter && root.adapter.enabled)

        function onOff(b) { return b ? "On" : "Off" }

        // Everything a tile shows, by id. `more` is the page its chevron
        // (wide) or long-press/right-click (small) opens, "" for none.
        function tileInfo(id) {
            switch (id) {
            case "wifi": return {
                glyph: Networking.wifiEnabled || !net.wifiDevice ? (net.wiredUp && !net.wifiUp ? "\u{f0200}" : "\u{f05a9}") : "\u{f05aa}",
                label: net.wifiDevice ? "Wi-Fi" : "Network", sub: panel.wifiSubtitle,
                active: net.wifiDevice ? Networking.wifiEnabled : net.wiredUp, more: net.wifiDevice ? "qs-wifi" : "" }
            case "bluetooth": return {
                glyph: root.adapter && root.adapter.enabled ? "\u{f00af}" : "\u{f00b2}",
                label: "Bluetooth", sub: panel.btSubtitle,
                active: !!(root.adapter && root.adapter.enabled), more: root.adapter ? "qs-bluetooth" : "" }
            case "airplane": return {
                glyph: "\u{f001d}", label: "Airplane", sub: panel.onOff(panel.airplane), active: panel.airplane, more: "" }
            case "nightlight": return {
                glyph: "\u{f0594}", label: "Night Light",
                sub: ShellState.sunsetWarm ? ShellState.sunsetKelvin + "K" : "Off", active: ShellState.sunsetWarm, more: "qs-sunset" }
            case "silence": return {
                glyph: ShellState.notificationsMuted ? "\u{f009b}" : "\u{f009a}", label: "Silence",
                sub: ShellState.notificationsMuted ? "Notifications muted" : "Off", active: ShellState.notificationsMuted, more: "" }
            case "micmute": return {
                glyph: panel.micMuted ? "\u{f036d}" : "\u{f036c}", label: "Mic Mute",
                sub: panel.micMuted ? "Muted" : "Live", active: panel.micMuted, more: "qs-audio" }
            case "awake": return {
                glyph: "\u{f0176}", label: "Stay Awake", sub: panel.onOff(ShellState.idleActive), active: ShellState.idleActive, more: "qs-idle" }
            case "gamefocus": return {
                glyph: "\u{f02b4}", label: "Game Focus",
                sub: GameFocus.enabled ? (GameFocus.dimming ? "Dimming" : "Armed") : "Off", active: GameFocus.enabled, more: "qs-gamefocus" }
            case "hdr": return {
                glyph: "\u{f0d7d}", label: "HDR", sub: panel.onOff(HdrSettings.active), active: HdrSettings.active, more: "qs-hdr" }
            case "opaque": return {
                glyph: "", label: "Opaque",
                sub: ShellState.transparencyOpaque ? "Solid" : Math.round(BarSettings.terminalOpacity * 100) + "%",
                active: ShellState.transparencyOpaque, more: "" }
            // The phone: mirror state while it's open, otherwise what the
            // sichlink daemon knows, plus the battery (PhonePage.qml has the rest).
            case "phone": return {
                glyph: "\u{f011c}", label: Sichlink.phone ? Sichlink.phone.name : "Phone",
                sub: [PhoneMirrorState.loading ? "Connecting…"
                    : PhoneMirrorState.open ? (PhoneMirrorState.collapsed ? "Mirror hidden" : "Mirroring")
                    : Sichlink.stateText,
                    Sichlink.phone && Sichlink.phone.connected ? Sichlink.batteryText(Sichlink.phone) : ""
                    ].filter(t => t !== "").join(" · "),
                active: PhoneMirrorState.open && !PhoneMirrorState.collapsed,
                busy: PhoneMirrorState.loading || Sichlink.busy, more: "qs-phone" }
            case "powerprofile": {
                const p = UP.PowerProfiles.profile
                return {
                    glyph: p === UP.PowerProfile.Performance ? "" : p === UP.PowerProfile.PowerSaver ? "\u{f032a}" : "",
                    label: "Power", sub: p === UP.PowerProfile.Performance ? "Performance" : p === UP.PowerProfile.PowerSaver ? "Saver" : "Balanced",
                    active: p !== UP.PowerProfile.Balanced, more: "" }
            }
            case "sound": return {
                glyph: vol.icon(), label: "Sound", sub: root.nodeName(root.sink),
                active: !!(root.sink && root.sink.audio && !root.sink.audio.muted), more: "qs-audio" }
            case "display": return {
                glyph: "\u{f0e51}", label: "Display",
                sub: Quickshell.screens.length + (Quickshell.screens.length === 1 ? " display" : " displays"),
                active: false, more: "qs-display" }
            case "update": return {
                glyph: "\u{f06b0}", label: "Updates",
                sub: upd.updating ? "Updating…" : upd.checking && upd.count === null ? "Checking…"
                    : upd.count === null ? "Unknown" : upd.count === 0 ? "Up to date"
                    : upd.count + (upd.count === 1 ? " update" : " updates"),
                active: !!upd.count, busy: upd.updating || upd.checking, more: "qs-update" }
            case "vpn": return {
                glyph: "\u{f0565}", label: "Proton VPN",
                sub: VpnStatus.busy ? "Disconnecting…" : VpnStatus.connected ? VpnStatus.server : "Off",
                active: VpnStatus.connected, busy: VpnStatus.busy, more: "" }
            case "stats": return {
                glyph: "\u{f035b}", label: "System",
                sub: "CPU " + Math.round(SystemStats.cpu * 100) + "% · RAM " + Math.round(SystemStats.ram * 100) + "%"
                    + (SystemStats.temp > 0 ? " · " + Math.round(SystemStats.temp) + "°C" : ""),
                active: false, more: "" }
            }
            return { glyph: "", label: id, sub: "", active: false, more: "" }
        }

        function tileToggle(id) {
            switch (id) {
            case "wifi": if (net.wifiDevice) Networking.wifiEnabled = !Networking.wifiEnabled; break
            case "bluetooth": if (root.adapter) root.adapter.enabled = !root.adapter.enabled; break
            case "airplane": {
                const on = !panel.airplane
                Networking.wifiEnabled = !on
                if (root.adapter) root.adapter.enabled = !on
                break
            }
            case "nightlight": ShellState.forceSunsetWarm(!ShellState.sunsetWarm); break
            case "silence": ShellState.setNotificationsMuted(!ShellState.notificationsMuted, 0); break
            case "micmute": if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted; break
            case "awake": ShellState.idleActive = !ShellState.idleActive; break
            case "gamefocus": GameFocus.enabled = !GameFocus.enabled; break
            case "hdr": HdrSettings.toggleActive(); break
            case "opaque": ShellState.setTransparencyOpaque(!ShellState.transparencyOpaque); break
            // Opens the Phone page (connect, mirror and its settings, PIN).
            case "phone": root.openPopup("qs-phone"); break
            case "powerprofile": {
                const p = UP.PowerProfiles.profile
                UP.PowerProfiles.profile = p === UP.PowerProfile.PowerSaver ? UP.PowerProfile.Balanced
                    : p === UP.PowerProfile.Balanced ? UP.PowerProfile.Performance : UP.PowerProfile.PowerSaver
                break
            }
            case "sound": if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted; break
            case "display": root.openPopup("qs-display"); break
            case "update": root.openPopup("qs-update"); break
            case "vpn": VpnStatus.toggle(); break
            // btop, floated/centered like SUPER+B (window_rules.lua).
            case "stats": Quickshell.execDetached(["kitty", "--class", "btop", "-e", "btop"]); break
            }
        }

        // Grid: 4 columns of tileUnit x tileHeight cells.
        readonly property real tileSpacing: 10
        readonly property real tileUnit: (root.cardWidth - 3 * panel.tileSpacing) / 4
        readonly property real tileHeight: 64

        // Extra controls a tile at least 2 columns wide shows: under its top
        // row when 2 rows tall, beside/under its label when 1 row (sliders
        // and buttons only -- the text ones need the second row). null =
        // none for that tile.
        function extraFor(id, tall) {
            if (!tall && ["bluetooth", "wifi"].includes(id)) return null
            switch (id) {
            case "sound": return extraVolume
            case "micmute": return extraMic
            case "nightlight": return extraWarmth
            case "opaque": return extraOpacity
            case "gamefocus": return extraDim
            case "powerprofile": return extraProfiles
            case "bluetooth": return extraBtDevices
            case "wifi": return extraWifi
            case "phone": return tall ? extraPhone : null
            case "display": return panel.hasBacklight ? extraBrightness : null
            case "update": return extraUpdate
            case "vpn": return extraVpn
            case "stats": return extraStats
            }
            return null
        }
        Component {
            id: extraUpdate
            Row {
                spacing: 4
                TileButton {
                    width: (parent.width - 4) / 2
                    label: upd.checking ? "Checking…" : "Check"
                    onClicked: upd.checkNow()
                }
                TileButton {
                    width: (parent.width - 4) / 2
                    selected: !!upd.count && !upd.updating
                    label: upd.updating ? "Updating…" : "Update all"
                    onClicked: upd.runUpdate()
                }
            }
        }
        Component {
            id: extraVpn
            Row {
                spacing: 4
                TileButton {
                    width: (parent.width - 4) / 2
                    selected: VpnStatus.connected
                    label: VpnStatus.connected ? "Disconnect" : "Connect"
                    onClicked: VpnStatus.toggle()
                }
                TileButton {
                    width: (parent.width - 4) / 2
                    label: "Open app"
                    onClicked: {
                        ShellState.activePopup = ""
                        VpnStatus.openApp()
                    }
                }
            }
        }
        // 1 row: the three numbers. 2 rows: CPU and RAM graphs too.
        Component {
            id: extraStats
            Item {
                id: statsBox
                readonly property bool compact: statsBox.height < 34
                Row {
                    visible: statsBox.compact
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Repeater {
                        model: [
                            "CPU " + Math.round(SystemStats.cpu * 100) + "%",
                            "RAM " + SystemStats.ramUsedGb.toFixed(1) + "G",
                            SystemStats.temp > 0 ? Math.round(SystemStats.temp) + "°C" : ""
                        ]
                        delegate: Text {
                            required property string modelData
                            visible: modelData !== ""
                            text: modelData
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
                Row {
                    visible: !statsBox.compact
                    anchors.fill: parent
                    spacing: 10
                    Repeater {
                        model: [
                            { label: "CPU", value: SystemStats.cpu, history: SystemStats.cpuHistory },
                            { label: "RAM", value: SystemStats.ram, history: SystemStats.ramHistory }
                        ]
                        delegate: Item {
                            required property var modelData
                            width: (statsBox.width - 10) / 2
                            height: statsBox.height
                            Text {
                                id: graphLabel
                                text: modelData.label + " " + Math.round(modelData.value * 100) + "%"
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Canvas {
                                id: graph
                                anchors.top: graphLabel.bottom
                                anchors.topMargin: 4
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                property var history: modelData.history
                                onHistoryChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    const h = graph.history
                                    if (!h || h.length < 2) return
                                    const step = width / (SystemStats.historyLength - 1)
                                    const x0 = width - (h.length - 1) * step
                                    ctx.beginPath()
                                    ctx.moveTo(x0, height)
                                    for (let i = 0; i < h.length; i++) ctx.lineTo(x0 + i * step, height - h[i] * height)
                                    ctx.lineTo(x0 + (h.length - 1) * step, height)
                                    ctx.closePath()
                                    ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                                    ctx.fill()
                                    ctx.beginPath()
                                    for (let i = 0; i < h.length; i++) {
                                        const x = x0 + i * step, y = height - h[i] * height
                                        if (i === 0) ctx.moveTo(x, y)
                                        else ctx.lineTo(x, y)
                                    }
                                    ctx.strokeStyle = Theme.accent
                                    ctx.lineWidth = 1.5
                                    ctx.stroke()
                                }
                            }
                        }
                    }
                }
            }
        }
        Component {
            id: extraVolume
            TileSlider {
                value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
            }
        }
        Component {
            id: extraMic
            TileSlider {
                value: root.source && root.source.audio ? root.source.audio.volume : 0
                onMoved: (v) => { if (root.source && root.source.audio) root.source.audio.volume = v }
            }
        }
        Component {
            id: extraBrightness
            TileSlider {
                value: panel.pendingBacklight >= 0 ? panel.pendingBacklight / 100 : panel.backlight
                onMoved: (v) => panel.setBacklight(v)
            }
        }
        // SunsetPopup's range.
        Component {
            id: extraWarmth
            TileSlider {
                value: (ShellState.sunsetKelvin - 2000) / 3000
                label: "Warmth"
                valueText: ShellState.sunsetKelvin + "K"
                onMoved: (v) => ShellState.setSunsetKelvin(Math.round((2000 + v * 3000) / 100) * 100)
            }
        }
        // TransparencyPopup's range.
        Component {
            id: extraOpacity
            TileSlider {
                value: (BarSettings.terminalOpacity - 0.5) / 0.45
                valueText: Math.round(BarSettings.terminalOpacity * 100) + "%"
                onMoved: (v) => ShellState.setTerminalOpacity(0.5 + v * 0.45)
            }
        }
        Component {
            id: extraDim
            TileSlider {
                value: (GameFocus.dimAmount - GameFocus.minDim) / (GameFocus.maxDim - GameFocus.minDim)
                label: "Dim"
                valueText: Math.round(GameFocus.dimAmount * 100) + "%"
                onMoved: (v) => GameFocus.setDimAmount(GameFocus.minDim + v * (GameFocus.maxDim - GameFocus.minDim))
            }
        }
        Component {
            id: extraProfiles
            Row {
                spacing: 4
                Repeater {
                    model: [
                        { profile: UP.PowerProfile.PowerSaver, label: "Saver" },
                        { profile: UP.PowerProfile.Balanced, label: "Balanced" },
                        { profile: UP.PowerProfile.Performance, label: "Perf" }
                    ]
                    delegate: TileButton {
                        required property var modelData
                        width: (parent.width - 8) / 3
                        label: modelData.label
                        selected: UP.PowerProfiles.profile === modelData.profile
                        onClicked: UP.PowerProfiles.profile = modelData.profile
                    }
                }
            }
        }
        Component {
            id: extraBtDevices
            Column {
                spacing: 2
                Repeater {
                    model: bt.connectedDevices.slice(0, 3)
                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        elide: Text.ElideRight
                        text: (modelData.name || modelData.deviceName)
                            + (modelData.batteryAvailable ? "  ·  " + Math.round(modelData.battery * 100) + "%" : "")
                        color: Theme.text
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Text {
                    visible: bt.connectedDevices.length === 0
                    text: root.adapter && root.adapter.enabled ? "No devices connected" : "Bluetooth is off"
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
        Component {
            id: extraWifi
            Column {
                spacing: 2
                Text {
                    text: net.wifiUp && net.wifiNetwork ? "Signal " + Math.round(net.wifiNetwork.signalStrength * 100) + "%" : "Not connected"
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    visible: net.wiredUp
                    text: "Ethernet connected"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
        // A 2-row phone tile: the page card's state line. No buttons -- the
        // tile opens the page, which has them.
        Component {
            id: extraPhone
            Text {
                readonly property var d: Sichlink.phone
                verticalAlignment: Text.AlignTop
                topPadding: 4
                elide: Text.ElideRight
                text: !d || !d.connected ? ""
                    : [Sichlink.lockText(d), d.adb_serial ? "Wireless adb" : "",
                       d.bt_link ? "Bluetooth" : ""].filter(t => t !== "").join("  ·  ")
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Item {
            anchors.fill: parent

            Column {
                id: column
                anchors.centerIn: parent
                width: root.cardWidth
                spacing: Theme.sectionSpacing

                // Header
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        HeaderIcon {
                            glyph: "\u{f1542}" // nf-md-tune_variant
                            color: Theme.accent
                        }
                        Text {
                            text: panel.editing ? "Edit tiles" : "Control Center"
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
                        Text {
                            visible: !panel.editing
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.batteryText()
                            color: root.battery && root.battery.state === UP.UPowerDeviceState.Charging ? Theme.success : Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        HeaderButton {
                            visible: panel.editing
                            label: "Reset"
                            onClicked: ControlCenterTiles.reset()
                        }
                        HeaderButton {
                            label: panel.editing ? "Done" : ""
                            glyph: panel.editing ? "" : "\u{f03eb}" // nf-md-pencil
                            primary: panel.editing
                            onClicked: panel.editing = !panel.editing
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.separator }

                // Tiles (ControlCenterTiles): w 1-4 columns x h 1-2 rows,
                // packed first-fit. Tap toggles; a wide tile's chevron -- or
                // long-press/right-click on any tile -- opens its page; a
                // 2-row tile at least 2 wide also gets extra controls
                // (slider, buttons, device list). In edit mode: drag to
                // reorder, drag the right/bottom edge or corner to resize.
                Item {
                    id: tileGrid
                    width: parent.width
                    height: Math.max(0, ControlCenterTiles.layout.rows * (panel.tileHeight + panel.tileSpacing) - panel.tileSpacing)
                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    // Over the "Add tiles" section, which a dragged tile
                    // can be pulled across.
                    z: 1
                    readonly property real stepX: panel.tileUnit + panel.tileSpacing
                    readonly property real stepY: panel.tileHeight + panel.tileSpacing
                    // The tile being dragged, "" for none.
                    property string dragId: ""
                    // It's past the grid, over "Add tiles": dropping it
                    // there removes it.
                    property bool dragOut: false
                    // Grid y below which the pointer counts as over "Add
                    // tiles". Moves down when a tile dragged in from there
                    // opens a new row, and back up when it leaves -- so
                    // crossing it doesn't flip in and out.
                    readonly property real dropLimit: spareSection.y - tileGrid.y

                    // Where the dragged tile will land: the others already
                    // make room for it there while it follows the pointer.
                    Rectangle {
                        readonly property var cell: tileGrid.dragId !== "" ? ControlCenterTiles.layout.pos[tileGrid.dragId] : undefined
                        visible: !!cell
                        x: cell ? cell.c * tileGrid.stepX : 0
                        y: cell ? cell.r * tileGrid.stepY : 0
                        width: cell ? cell.w * panel.tileUnit + (cell.w - 1) * panel.tileSpacing : 0
                        height: cell ? cell.h * panel.tileHeight + (cell.h - 1) * panel.tileSpacing : 0
                        radius: Theme.controlRadius
                        color: "transparent"
                        border.color: Theme.accent
                        border.width: 1
                        opacity: 0.6
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    Repeater {
                        id: tileRepeater
                        model: ControlCenterTiles.model

                        delegate: Item {
                            id: tile
                            required property string tileId
                            readonly property var info: panel.tileInfo(tile.tileId)
                            readonly property var cell: ControlCenterTiles.layout.pos[tile.tileId] || { r: 0, c: 0, w: 1, h: 1 }
                            readonly property bool small: tile.cell.w === 1
                            readonly property bool tall: tile.cell.h === 2
                            readonly property Component extra: !tile.small ? panel.extraFor(tile.tileId, tile.tall) : null
                            // 1-row tile with extra controls: 2 wide puts
                            // them under a label-only top line, 3+ wide
                            // beside the label.
                            readonly property bool inlineNarrow: !tile.tall && !!tile.extra && tile.cell.w === 2
                            readonly property bool inlineWide: !tile.tall && !!tile.extra && tile.cell.w >= 3
                            readonly property bool resizing: rightEdge.pressed || bottomEdge.pressed || corner.pressed
                            readonly property bool dragging: tile.held || tile.resizing

                            // Dragged: the tile follows the pointer (dragX/Y)
                            // instead of its cell, then glides into the cell
                            // on release (settle). Not a Behavior toggled by
                            // `held`: whether it is re-enabled before or after
                            // x jumps back to the cell isn't defined.
                            property bool held: false
                            readonly property bool floating: tile.held || settle.running
                            property real dragX: 0
                            property real dragY: 0
                            property real grabX: 0
                            property real grabY: 0
                            // Cell the tile had when a resize started; sizes
                            // are measured from it, not from the tile's
                            // current (possibly moving) position.
                            property var resizeFrom: null

                            readonly property real cellX: tile.cell.c * tileGrid.stepX
                            readonly property real cellY: tile.cell.r * tileGrid.stepY
                            x: tile.floating ? tile.dragX : tile.cellX
                            y: tile.floating ? tile.dragY : tile.cellY
                            width: tile.cell.w * panel.tileUnit + (tile.cell.w - 1) * panel.tileSpacing
                            height: tile.cell.h * panel.tileHeight + (tile.cell.h - 1) * panel.tileSpacing
                            z: tile.floating ? 10 : tile.resizing ? 5 : 0
                            Behavior on x { enabled: !tile.floating; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: !tile.floating; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            property alias settle: settle
                            ParallelAnimation {
                                id: settle
                                NumberAnimation { target: tile; property: "dragX"; to: tile.cellX; duration: 180; easing.type: Easing.OutCubic }
                                NumberAnimation { target: tile; property: "dragY"; to: tile.cellY; duration: 180; easing.type: Easing.OutCubic }
                            }

                            function startDrag(mx, my) {
                                settle.stop()
                                tile.dragX = tile.x
                                tile.dragY = tile.y
                                tile.grabX = mx
                                tile.grabY = my
                                tile.held = true
                                tileGrid.dragId = tile.tileId
                            }
                            // `item`/(mx, my): the pointer, in any item's
                            // coordinates -- a tile dragged in from "Add
                            // tiles" is driven by that spare's MouseArea.
                            function dragTo(item, mx, my) {
                                const p = item.mapToItem(tileGrid, mx, my)
                                tileGrid.dragOut = p.y > tileGrid.dropLimit
                                tile.dragX = Math.max(0, Math.min(tileGrid.width - tile.width, p.x - tile.grabX))
                                tile.dragY = tileGrid.dragOut ? p.y - tile.grabY : Math.max(0, Math.min(tileGrid.height, p.y - tile.grabY))
                                if (tileGrid.dragOut) return
                                const to = ControlCenterTiles.nearestIndex(tile.tileId, tile.cell.w, tile.cell.h,
                                    tile.dragY / tileGrid.stepY, tile.dragX / tileGrid.stepX,
                                    tileGrid.stepY / tileGrid.stepX, 0.2)
                                ControlCenterTiles.move(tile.tileId, to)
                            }
                            // Settle starts before `held` drops so `floating`
                            // never goes false in between (that would start
                            // the x/y Behavior towards the cell).
                            function endDrag() {
                                if (!tile.held) return
                                const out = tileGrid.dragOut
                                if (!out) settle.restart()
                                tile.held = false
                                tileGrid.dragOut = false
                                if (tileGrid.dragId === tile.tileId) tileGrid.dragId = ""
                                // Later: this destroys the delegate whose
                                // MouseArea is still in its release handler.
                                if (out) { const id = tile.tileId; Qt.callLater(() => ControlCenterTiles.remove(id)) }
                            }
                            Connections {
                                target: panel
                                function onEditingChanged() { if (!panel.editing) tile.endDrag() }
                            }

                            // Resize from an edge: the size that puts the
                            // tile's edge nearest the pointer (snaps once the
                            // pointer is past half a cell), measured from the
                            // cell the tile started in. Wider than the columns
                            // right of that cell isn't offered -- drag the tile
                            // further left first.
                            function resizeTo(item, mx, my, horizontal, vertical) {
                                const from = tile.resizeFrom || tile.cell
                                const p = item.mapToItem(tileGrid, mx, my)
                                const w = horizontal ? Math.round((p.x - from.c * tileGrid.stepX + panel.tileSpacing) / tileGrid.stepX) : tile.cell.w
                                const h = vertical ? Math.round((p.y - from.r * tileGrid.stepY + panel.tileSpacing) / tileGrid.stepY) : tile.cell.h
                                ControlCenterTiles.resizeAt(tile.tileId,
                                    Math.max(1, Math.min(ControlCenterTiles.columns - from.c, w)),
                                    Math.max(1, Math.min(ControlCenterTiles.maxRows, h)), from.r, from.c)
                            }
                            function startResize() { tile.resizeFrom = { r: tile.cell.r, c: tile.cell.c } }

                            Rectangle {
                                id: face
                                anchors.fill: parent
                                radius: Theme.controlRadius
                                // Grows while dragged in edit mode, dips on
                                // a press otherwise; faded while it's over
                                // "Add tiles" (dropping removes it).
                                scale: tile.dragging ? 1.03 : tapArea.pressed ? 0.96 : 1
                                opacity: tile.held && tileGrid.dragOut ? 0.5 : 1
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                color: tile.info.active ? Theme.selectedFill
                                    : (tapArea.containsMouse && !panel.editing) || tile.dragging ? Theme.hoverFill : Theme.controlFill
                                border.color: tile.info.active || tile.info.busy || panel.editing ? Theme.accent : Theme.surfaceBorder
                                border.width: 1

                                MouseArea {
                                    id: tapArea
                                    anchors.fill: parent
                                    enabled: !panel.editing
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    pressAndHoldInterval: 450
                                    property bool held: false
                                    onPressed: tapArea.held = false
                                    onPressAndHold: {
                                        tapArea.held = true
                                        if (tile.info.more) root.openPopup(tile.info.more)
                                    }
                                    onClicked: (mouse) => {
                                        if (tapArea.held) return
                                        if (mouse.button === Qt.RightButton) { if (tile.info.more) root.openPopup(tile.info.more) }
                                        else panel.tileToggle(tile.tileId)
                                    }
                                }

                                // Top row: the whole tile when 1 row tall.
                                Item {
                                    id: head
                                    // 2x1 with a control under the label: the
                                    // pair sat high (more space under the
                                    // slider than over the label) -- nudged
                                    // down to center the pair.
                                    y: tile.inlineNarrow ? 4 : 0
                                    width: parent.width
                                    height: tile.inlineNarrow ? 34 : panel.tileHeight

                                    // HeaderIcon sizes by measured ink, so
                                    // every icon -- and swaps like mic/mic-off
                                    // -- comes out the same size.
                                    // Wide tiles: centered in a fixed 30px slot
                                    // (the ink-width cap) so wide glyphs like
                                    // HDR don't run into the label, and labels
                                    // line up across tiles.
                                    HeaderIcon {
                                        x: tile.small ? (parent.width - width) / 2 : 12 + (30 - width) / 2
                                        anchors.verticalCenterOffset: tile.small ? -9 : 0
                                        glyph: tile.info.glyph
                                        inkHeight: 17
                                        // Width capped at ~1.3x the height so
                                        // wide-and-short glyphs (gamepad)
                                        // don't read bigger than the rest --
                                        // except HDR, which is lettering and
                                        // would shrink to a sliver.
                                        inkWidth: tile.info.glyph === "\u{f0d7d}" ? 30 : 22
                                        color: tile.info.active ? Theme.text : Theme.textMuted
                                        opacity: tile.info.busy ? 0.5 : 1
                                        SequentialAnimation on opacity {
                                            running: !!tile.info.busy
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 1; to: 0.35; duration: 500 }
                                            NumberAnimation { from: 0.35; to: 1; duration: 500 }
                                        }
                                    }
                                    Text {
                                        visible: tile.small
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 9
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        horizontalAlignment: Text.AlignHCenter
                                        text: tile.info.label
                                        elide: Text.ElideRight
                                        color: tile.info.active ? Theme.text : Theme.textMuted
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                    Column {
                                        visible: !tile.small
                                        x: 52
                                        // Up to the inline control (3+ wide;
                                        // not a sibling, so no anchor) or the
                                        // chevron strip.
                                        width: (tile.inlineWide ? inlineExtra.x - 10
                                            : (moreStrip.visible ? moreStrip.x : head.width) - 6) - 52
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            text: tile.info.label
                                            elide: Text.ElideRight
                                            color: Theme.text
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.bold: true
                                        }
                                        Text {
                                            visible: !tile.inlineNarrow
                                            width: parent.width
                                            text: tile.info.sub
                                            elide: Text.ElideRight
                                            color: Theme.textMuted
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                    }
                                    Rectangle {
                                        id: moreStrip
                                        visible: !tile.small && tile.info.more !== "" && !panel.editing
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 1
                                        width: 30
                                        radius: Theme.controlRadius
                                        color: moreArea.containsMouse ? Theme.hoverFill : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "" // nf-fa-chevron_right
                                            color: moreArea.containsMouse ? Theme.text : Theme.textMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                        }
                                        MouseArea {
                                            id: moreArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openPopup(tile.info.more)
                                        }
                                    }
                                }

                                // 1 column x 2 rows: status under the label.
                                Text {
                                    visible: tile.small && tile.tall
                                    anchors.top: head.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    text: tile.info.sub
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }

                                // 1 row, 2+ columns: extra controls under
                                // (2 wide) or beside (3+ wide) the label.
                                Loader {
                                    id: inlineExtra
                                    active: tile.inlineNarrow || tile.inlineWide
                                    sourceComponent: tile.extra
                                    enabled: !panel.editing
                                    x: tile.inlineWide ? 52 + 84 : 14
                                    width: (tile.inlineWide && moreStrip.visible ? moreStrip.x - 8 : parent.width - 14) - x
                                    y: tile.inlineWide ? (parent.height - height) / 2 : head.y + head.height - 2
                                    height: tile.inlineWide ? 28 : 24
                                }

                                // 2+ columns x 2 rows: extra controls.
                                Loader {
                                    active: tile.tall && !!tile.extra
                                    sourceComponent: tile.extra
                                    anchors.top: head.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.bottomMargin: 10
                                    enabled: !panel.editing
                                }

                                // Edit mode: the tile body drags (reorders
                                // live while the pointer crosses other
                                // tiles); edges/corner resize.
                                MouseArea {
                                    id: editArea
                                    anchors.fill: parent
                                    enabled: panel.editing
                                    preventStealing: true
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    onPressed: (mouse) => {
                                        const p = editArea.mapToItem(tile, mouse.x, mouse.y)
                                        tile.startDrag(p.x, p.y)
                                    }
                                    onPositionChanged: (mouse) => { if (tile.held) tile.dragTo(editArea, mouse.x, mouse.y) }
                                    onReleased: tile.endDrag()
                                    onCanceled: tile.endDrag()
                                }
                                MouseArea {
                                    id: rightEdge
                                    enabled: panel.editing
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: -4
                                    width: 12
                                    preventStealing: true
                                    cursorShape: Qt.SizeHorCursor
                                    onPressed: tile.startResize()
                                    onPositionChanged: (mouse) => { if (pressed) tile.resizeTo(rightEdge, mouse.x, mouse.y, true, false) }
                                }
                                MouseArea {
                                    id: bottomEdge
                                    enabled: panel.editing
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: -4
                                    height: 12
                                    preventStealing: true
                                    cursorShape: Qt.SizeVerCursor
                                    onPressed: tile.startResize()
                                    onPositionChanged: (mouse) => { if (pressed) tile.resizeTo(bottomEdge, mouse.x, mouse.y, false, true) }
                                }
                                MouseArea {
                                    id: corner
                                    enabled: panel.editing
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: -4
                                    anchors.bottomMargin: -4
                                    width: 18
                                    height: 18
                                    preventStealing: true
                                    cursorShape: Qt.SizeFDiagCursor
                                    onPressed: tile.startResize()
                                    onPositionChanged: (mouse) => { if (pressed) tile.resizeTo(corner, mouse.x, mouse.y, true, true) }
                                }
                                // Corner grip, so the resize handle is visible.
                                Rectangle {
                                    visible: panel.editing
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 4
                                    width: 10
                                    height: 10
                                    radius: 3
                                    color: corner.containsMouse || corner.pressed ? Theme.accentHover : Theme.accent
                                    opacity: 0.8
                                }

                                EditBadge {
                                    visible: panel.editing
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 4
                                    glyph: "\u{f0374}" // nf-md-minus
                                    onClicked: ControlCenterTiles.remove(tile.tileId)
                                }
                            }
                        }
                    }
                }

                // Edit mode: spare tiles to add -- click, or drag one into
                // the grid. A grid tile dragged down here is removed.
                Column {
                    id: spareSection
                    visible: panel.editing
                    width: parent.width
                    spacing: 8
                    // While a spare is dragged its list stays as it was:
                    // adding the tile changes `unused`, and the Repeater
                    // would rebuild the very delegate holding the drag.
                    property bool frozen: false
                    property var frozenIds: []

                    Text {
                        text: tileGrid.dragOut ? "Release to remove"
                            : ControlCenterTiles.unused.length > 0 ? "Add tiles" : "All tiles are in use"
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Flow {
                        width: parent.width
                        spacing: panel.tileSpacing
                        Repeater {
                            model: spareSection.frozen ? spareSection.frozenIds : ControlCenterTiles.unused
                            delegate: Rectangle {
                                id: spare
                                required property string modelData
                                readonly property var info: panel.tileInfo(spare.modelData)
                                // Dragged past the threshold; inGrid: the
                                // tile is in the grid (its own delegate
                                // follows the pointer, this one hides).
                                property bool dragging: false
                                property bool inGrid: false
                                // Press point: in the spare (= grab offset)
                                // and in the Flow, which the Translate below
                                // doesn't move -- local mouse coordinates do
                                // move with it, so they can't measure the drag.
                                property real pressX: 0
                                property real pressY: 0
                                property point pressAt: Qt.point(0, 0)
                                width: panel.tileUnit
                                height: panel.tileHeight
                                radius: Theme.controlRadius
                                z: spare.dragging ? 10 : 0
                                opacity: spare.inGrid ? 0 : 1
                                color: spare.dragging ? Theme.controlFill : spareArea.containsMouse ? Theme.hoverFill : "transparent"
                                transform: Translate { id: spareShift }

                                function gridTile() {
                                    const i = ControlCenterTiles.indexOf(spare.modelData)
                                    return i === -1 ? null : tileRepeater.itemAt(i)
                                }
                                function dragTo(mx, my) {
                                    const p = spareArea.mapToItem(tileGrid, mx, my)
                                    const over = p.y <= tileGrid.dropLimit
                                    if (over && !spare.inGrid) {
                                        ControlCenterTiles.add(spare.modelData)
                                        const t = spare.gridTile()
                                        if (!t) return
                                        spare.inGrid = true
                                        t.settle.stop()
                                        t.grabX = spare.pressX
                                        t.grabY = spare.pressY
                                        t.held = true
                                        tileGrid.dragId = spare.modelData
                                    } else if (!over && spare.inGrid) {
                                        const t = spare.gridTile()
                                        if (t) t.held = false
                                        tileGrid.dragId = ""
                                        tileGrid.dragOut = false
                                        spare.inGrid = false
                                        ControlCenterTiles.remove(spare.modelData)
                                    }
                                    if (spare.inGrid) {
                                        const t = spare.gridTile()
                                        if (t) t.dragTo(spareArea, mx, my)
                                    }
                                    const q = spareArea.mapToItem(spare.parent, mx, my)
                                    spareShift.x = q.x - spare.pressAt.x
                                    spareShift.y = q.y - spare.pressAt.y
                                }
                                function finish(drop) {
                                    if (spare.inGrid) {
                                        const t = spare.gridTile()
                                        if (t) { if (drop) t.endDrag(); else t.held = false }
                                        tileGrid.dragId = ""
                                        if (!drop) ControlCenterTiles.remove(spare.modelData)
                                    }
                                    spare.dragging = false
                                    spare.inGrid = false
                                    spareShift.x = 0
                                    spareShift.y = 0
                                    // Later: unfreezing rebuilds this delegate.
                                    Qt.callLater(() => { spareSection.frozen = false })
                                }
                                border.color: Theme.surfaceBorder
                                border.width: 1
                                HeaderIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenterOffset: -9
                                    glyph: spare.info.glyph
                                    inkHeight: 17
                                    inkWidth: spare.info.glyph === "\u{f0d7d}" ? 30 : 22
                                    color: Theme.textMuted
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 9
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    horizontalAlignment: Text.AlignHCenter
                                    text: spare.info.label
                                    elide: Text.ElideRight
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                                EditBadge {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 4
                                    glyph: "\u{f0415}" // nf-md-plus
                                    onClicked: ControlCenterTiles.add(spare.modelData)
                                }
                                MouseArea {
                                    id: spareArea
                                    anchors.fill: parent
                                    z: -1
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: spare.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    onPressed: (mouse) => {
                                        spare.pressX = mouse.x
                                        spare.pressY = mouse.y
                                        spare.pressAt = spareArea.mapToItem(spare.parent, mouse.x, mouse.y)
                                        spareSection.frozenIds = ControlCenterTiles.unused.slice()
                                        spareSection.frozen = true
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return
                                        const q = spareArea.mapToItem(spare.parent, mouse.x, mouse.y)
                                        if (!spare.dragging && Math.hypot(q.x - spare.pressAt.x, q.y - spare.pressAt.y) < 6) return
                                        spare.dragging = true
                                        spare.dragTo(mouse.x, mouse.y)
                                    }
                                    onReleased: {
                                        const click = !spare.dragging
                                        spare.finish(true)
                                        if (click) ControlCenterTiles.add(spare.modelData)
                                    }
                                    onCanceled: spare.finish(false)
                                }
                            }
                        }
                    }
                }

                // Everything below the tiles; hidden while editing them.
                Column {
                    visible: !panel.editing
                    width: parent.width
                    spacing: Theme.sectionSpacing

                    // Media
                    Repeater {
                        model: root.players
                        delegate: Rectangle {
                            id: mediaCard
                            required property var modelData
                            readonly property var player: mediaCard.modelData
                            readonly property string artSource: root.artFor(mediaCard.player)
                            width: column.width
                            height: 64
                            radius: Theme.controlRadius
                            color: Theme.controlFill
                            border.color: Theme.surfaceBorder
                            border.width: 1

                            Rectangle {
                                id: art
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 48
                                height: 48
                                radius: Theme.controlRadius
                                color: Theme.controlFill
                                clip: true

                                Text {
                                    visible: mediaCard.artSource === ""
                                    anchors.centerIn: parent
                                    text: "\u{f075a}" // nf-md-music_note
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 10
                                }
                                Image {
                                    visible: mediaCard.artSource !== ""
                                    anchors.fill: parent
                                    source: mediaCard.artSource
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: false
                                    sourceSize.width: 96
                                    sourceSize.height: 96
                                }
                            }

                            Column {
                                anchors.left: art.right
                                anchors.leftMargin: 10
                                anchors.right: mediaButtons.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: mediaCard.player ? (mediaCard.player.trackTitle || mediaCard.player.identity || "") : ""
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                }
                                Text {
                                    width: parent.width
                                    text: mediaCard.player ? [mediaCard.player.trackArtist, mediaCard.player.identity].filter(s => !!s).join(" · ") : ""
                                    elide: Text.ElideRight
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }

                            Row {
                                id: mediaButtons
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                MediaButton {
                                    glyph: "\u{f04ae}" // nf-md-skip_previous
                                    enabledState: !!mediaCard.player && mediaCard.player.canGoPrevious
                                    onClicked: mediaCard.player.previous()
                                }
                                MediaButton {
                                    glyph: mediaCard.player && mediaCard.player.isPlaying ? "\u{f03e4}" : "\u{f040a}" // pause / play
                                    big: true
                                    enabledState: !!mediaCard.player && mediaCard.player.canTogglePlaying
                                    onClicked: mediaCard.player.togglePlaying()
                                }
                                MediaButton {
                                    glyph: "\u{f04ad}" // nf-md-skip_next
                                    enabledState: !!mediaCard.player && mediaCard.player.canGoNext
                                    onClicked: mediaCard.player.next()
                                }
                            }
                        }
                    }

                    // Levels
                    Column {
                        width: parent.width
                        spacing: 8

                        SliderRow {
                            width: parent.width
                            glyph: vol.icon()
                            glyphScale: vol.iconScale()
                            dim: !!(root.sink && root.sink.audio && root.sink.audio.muted)
                            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                            onGlyphClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                            onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
                        }
                        SliderRow {
                            width: parent.width
                            visible: panel.hasBacklight
                            glyph: "\u{f00e0}" // nf-md-brightness_6
                            value: panel.pendingBacklight >= 0 ? panel.pendingBacklight / 100 : panel.backlight
                            onMoved: (v) => panel.setBacklight(v)
                        }
                    }

                    // Power profile
                    Row {
                        spacing: 6

                        Repeater {
                            model: [
                                { profile: UP.PowerProfile.PowerSaver, label: "Saver" },
                                { profile: UP.PowerProfile.Balanced, label: "Balanced" },
                                { profile: UP.PowerProfile.Performance, label: "Performance" }
                            ]
                            delegate: Rectangle {
                                id: profileButton
                                required property var modelData
                                readonly property bool active: UP.PowerProfiles.profile === modelData.profile
                                width: (root.cardWidth - 12) / 3
                                height: Theme.controlHeight + 8
                                radius: Theme.controlRadius
                                color: profileButton.active ? Theme.selectedFill : profileArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                                border.color: profileButton.active ? Theme.accent : Theme.surfaceBorder
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: profileButton.modelData.label
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: profileButton.active ? Theme.text : Theme.textMuted
                                }
                                MouseArea {
                                    id: profileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: UP.PowerProfiles.profile = profileButton.modelData.profile
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.separator }

                    Column {
                        width: parent.width
                        spacing: 2

                        LinkRow {
                            width: parent.width
                            glyph: "\u{f04c3}" // nf-md-speaker
                            label: "Sound"
                            detail: root.nodeName(root.sink)
                            onClicked: root.openPopup("qs-audio")
                        }
                        LinkRow {
                            width: parent.width
                            glyph: "\u{f0e51}"
                            label: "Display"
                            onClicked: root.openPopup("qs-display")
                        }
                    }
                }
            }
        }
    }

    // --- Toggle-row popups as pages (long-press/chevron on their tiles) ---
    // Own instances of the same MorphContents the toggle row uses, anchored
    // here, with the same handlers Bar.qml gives the row's toggles.
    function pageShown(id) {
        return ShellState.activePopup === id && ShellState.activePopupScreen === root.screenName
    }
    readonly property Item _hdrPage: HdrPopup {
        contentWidth: root.cardWidth
        parent: root.popupHost
        anchorItem: root
        shown: root.pageShown("qs-hdr")
        backPopupId: root.popupId
    }
    readonly property Item _sunsetPage: SunsetPopup {
        contentWidth: root.cardWidth
        parent: root.popupHost
        anchorItem: root
        shown: root.pageShown("qs-sunset")
        backPopupId: root.popupId
        active: ShellState.sunsetWarm
        scheduleFollow: ShellState.sunsetScheduleFollow
        kelvin: ShellState.sunsetKelvin
        onSetWarm: (warm) => ShellState.forceSunsetWarm(warm)
        onSetTemperature: (k) => ShellState.setSunsetKelvin(k)
        onSetScheduleFollow: (follow) => ShellState.setScheduleFollow(follow)
        // hyprsunset only reads its config at startup -- see Bar.qml.
        onScheduleSaved: {
            ShellState.setScheduleFollow(true)
            Quickshell.execDetached(["systemctl", "--user", "restart", "hyprsunset.service"])
        }
    }
    readonly property Item _idlePage: IdlePopup {
        contentWidth: root.cardWidth
        parent: root.popupHost
        anchorItem: root
        shown: root.pageShown("qs-idle")
        backPopupId: root.popupId
        active: ShellState.idleActive
        onSettingsSaved: Quickshell.execDetached(["systemctl", "--user", "restart", "hypridle.service"])
    }
    readonly property Item _gameFocusPage: GameFocusPopup {
        contentWidth: root.cardWidth
        parent: root.popupHost
        anchorItem: root
        shown: root.pageShown("qs-gamefocus")
        backPopupId: root.popupId
    }

    // --- Wi-Fi page ---
    readonly property Item _wifiContent: WifiMenu {
        parent: root.popupHost
        anchorItem: root
        shown: ShellState.activePopup === "qs-wifi" && ShellState.activePopupScreen === root.screenName
        contentWidth: root.cardWidth
        screenName: root.screenName
        onBack: root.openPopup(root.popupId)
    }

    // --- Phone page ---
    readonly property Item _phoneContent: PhonePage {
        parent: root.popupHost
        anchorItem: root
        shown: ShellState.activePopup === "qs-phone" && ShellState.activePopupScreen === root.screenName
        contentWidth: root.cardWidth
        screenName: root.screenName
        onBack: root.openPopup(root.popupId)
    }

    // --- Sound page ---
    readonly property Item _audioContent: MorphContent {
        id: audioPanel
        parent: root.popupHost
        anchorItem: root
        shown: root.audioOpen


        implicitWidth: root.cardWidth + 2 * Theme.surfacePadding
        implicitHeight: audioColumn.implicitHeight + 2 * Theme.surfacePadding

        Item {
            anchors.fill: parent

            Column {
                id: audioColumn
                anchors.centerIn: parent
                width: root.cardWidth
                spacing: Theme.sectionSpacing

                // Header, back arrow like BluetoothIndicator/DisplaySettings'.
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        BackButton {
                            onClicked: root.openPopup(root.popupId)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Sound"
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Mixer"
                        color: mixerArea.containsMouse ? Theme.accentHover : Theme.accent
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        MouseArea {
                            id: mixerArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // See Volume.qml for why pavucontrol gets its own GTK theme.
                            onClicked: {
                                ShellState.activePopup = ""
                                Quickshell.execDetached(["env", "GTK_THEME=pavucontrol-dark", "pavucontrol"])
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.separator }

                Text {
                    text: "Output"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                SliderRow {
                    width: parent.width
                    glyph: vol.icon()
                    glyphScale: vol.iconScale()
                    dim: !!(root.sink && root.sink.audio && root.sink.audio.muted)
                    value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                    onGlyphClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                    onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
                }
                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.sinks
                        delegate: DeviceRow {
                            required property var modelData
                            width: audioColumn.width
                            label: root.nodeName(modelData)
                            current: modelData === root.sink
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                        }
                    }
                }

                Text {
                    text: "Input"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                SliderRow {
                    width: parent.width
                    glyph: root.source && root.source.audio && root.source.audio.muted ? "\u{f036d}" : "\u{f036c}"
                    dim: !!(root.source && root.source.audio && root.source.audio.muted)
                    value: root.source && root.source.audio ? root.source.audio.volume : 0
                    onGlyphClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
                    onMoved: (v) => { if (root.source && root.source.audio) root.source.audio.volume = v }
                }
                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.sources
                        delegate: DeviceRow {
                            required property var modelData
                            width: audioColumn.width
                            label: root.nodeName(modelData)
                            current: modelData === root.source
                            onClicked: Pipewire.preferredDefaultAudioSource = modelData
                        }
                    }
                }
            }
        }
    }

    component MediaButton: Item {
        id: mb
        property string glyph: ""
        property bool big: false
        property bool enabledState: true
        signal clicked()

        width: 34
        height: 34
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: mbArea.containsMouse && mb.enabledState ? Theme.hoverFill : "transparent"
        }
        Text {
            anchors.centerIn: parent
            text: mb.glyph
            color: mb.enabledState ? Theme.text : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: mb.big ? Theme.fontSize + 11 : Theme.fontSize + 5
        }
        MouseArea {
            id: mbArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: mb.enabledState
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }
    }

    // Icon + track + percentage; the track takes clicks, drags and wheel.
    component SliderRow: Item {
        id: slider
        property string glyph: ""
        property real glyphScale: 1
        property bool dim: false
        property real value: 0
        signal moved(real v)
        signal glyphClicked()

        height: Theme.controlHeight + 8

        function valueAt(x) { return Math.max(0, Math.min(1, x / track.width)) }

        Item {
            id: glyphBox
            width: 32
            height: parent.height
            Text {
                // Left-aligned like Volume.qml: the volume glyphs differ in
                // width, centering would wobble the speaker side to side.
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: slider.glyph
                color: slider.dim ? Theme.textDim : glyphArea.containsMouse ? Theme.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: (Theme.fontSize + 9) * slider.glyphScale
            }
            MouseArea {
                id: glyphArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: slider.glyphClicked()
            }
        }

        Rectangle {
            id: track
            anchors.left: glyphBox.right
            anchors.leftMargin: 6
            anchors.right: pct.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.trackHeight + 2
            radius: Theme.trackRadius
            color: Theme.track
            opacity: slider.dim ? 0.5 : 1

            Rectangle {
                width: track.width * Math.max(0, Math.min(1, slider.value))
                height: parent.height
                radius: Theme.trackRadius
                color: Theme.accent
            }

            MouseArea {
                // Taller than the track so it's easy to grab.
                anchors.fill: parent
                anchors.topMargin: -8
                anchors.bottomMargin: -8
                cursorShape: Qt.PointingHandCursor
                onPressed: (mouse) => slider.moved(slider.valueAt(mouse.x))
                onPositionChanged: (mouse) => { if (pressed) slider.moved(slider.valueAt(mouse.x)) }
                onWheel: (wheel) => slider.moved(Math.max(0, Math.min(1, slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }

        Text {
            id: pct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.value * 100) + "%"
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    // Full-width row that opens a submenu.
    component LinkRow: Rectangle {
        id: link
        property string glyph: ""
        property string label: ""
        property string detail: ""
        signal clicked()

        height: Theme.controlHeight + 12
        radius: Theme.controlRadius
        color: linkArea.containsMouse ? Theme.hoverFill : "transparent"

        Text {
            id: linkGlyph
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            text: link.glyph
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 6
        }
        Text {
            id: linkLabel
            anchors.left: linkGlyph.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: link.label
            color: Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize
        }
        Text {
            anchors.left: linkLabel.right
            anchors.leftMargin: 16
            anchors.right: linkArrow.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: link.detail
            elide: Text.ElideRight
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            id: linkArrow
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "" // nf-fa-chevron_right
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        MouseArea {
            id: linkArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: link.clicked()
        }
    }

    // Selectable audio device; the current default gets a check.
    component DeviceRow: Rectangle {
        id: dev
        property string label: ""
        property bool current: false
        signal clicked()

        height: Theme.controlHeight + 6
        radius: Theme.controlRadius
        color: dev.current ? Theme.selectedFill : devArea.containsMouse ? Theme.hoverFill : "transparent"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: check.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: dev.label
            elide: Text.ElideRight
            color: dev.current ? Theme.text : Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            id: check
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: dev.current
            text: "" // nf-fa-check
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        MouseArea {
            id: devArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dev.clicked()
        }
    }

    // Round corner button on a tile in edit mode (remove/resize/add).
    component EditBadge: Rectangle {
        id: badge
        property string glyph: ""
        signal clicked()
        width: 18
        height: 18
        radius: 9
        z: 5
        color: badgeArea.containsMouse ? Theme.accentHover : Theme.accent
        Text {
            anchors.centerIn: parent
            text: badge.glyph
            color: Theme.textOnLight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        MouseArea {
            id: badgeArea
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: badge.clicked()
        }
    }

    // Small text/glyph button in the card header (edit pencil, Done, Reset).
    component HeaderButton: Rectangle {
        id: hb
        property string label: ""
        property string glyph: ""
        property bool primary: false
        signal clicked()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: hb.label !== "" ? hbText.implicitWidth + 18 : Theme.controlHeight
        height: Theme.controlHeight - 2
        radius: Theme.controlRadius
        color: hb.primary ? (hbArea.containsMouse ? Theme.accentHover : Theme.accent)
            : hbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
        Text {
            id: hbText
            anchors.centerIn: parent
            text: hb.label !== "" ? hb.label : hb.glyph
            color: hb.primary ? Theme.textOnLight : hbArea.containsMouse ? Theme.text : Theme.textMuted
            font.family: hb.label !== "" ? Theme.uiFontFamily : Theme.fontFamily
            font.pixelSize: hb.label !== "" ? Theme.fontSize - 1 : Theme.fontSize + 1
            font.bold: hb.primary
        }
        MouseArea {
            id: hbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }

    // Slider for a tile's extra area. Given room (2-row tile): label and
    // percentage over the track. Short (1-row tile): track with the
    // percentage beside it.
    component TileSlider: Item {
        id: ts
        property real value: 0
        property string label: ""
        // Shown beside/over the track; a percentage of the slider's own
        // position unless the value has a real unit (Night Light's kelvin).
        property string valueText: Math.round(ts.clamped * 100) + "%"
        signal moved(real v)
        readonly property bool compact: ts.height < 34
        readonly property real clamped: Math.max(0, Math.min(1, ts.value))
        Text {
            visible: ts.label !== "" && !ts.compact
            anchors.left: parent.left
            anchors.bottom: tsTrack.top
            anchors.bottomMargin: 6
            text: ts.label
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        Text {
            id: tsPct
            anchors.right: parent.right
            anchors.bottom: ts.compact ? undefined : tsTrack.top
            anchors.bottomMargin: 6
            anchors.verticalCenter: ts.compact ? tsTrack.verticalCenter : undefined
            width: ts.compact ? Math.max(32, implicitWidth) : implicitWidth
            horizontalAlignment: Text.AlignRight
            text: ts.valueText
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        Rectangle {
            id: tsTrack
            anchors.left: parent.left
            anchors.right: ts.compact ? tsPct.left : parent.right
            anchors.rightMargin: ts.compact ? 6 : 0
            y: ts.compact ? (ts.height - height) / 2 : ts.height - height - 6
            height: Theme.trackHeight
            radius: Theme.trackRadius
            color: Theme.track
            Rectangle {
                width: tsTrack.width * ts.clamped
                height: parent.height
                radius: Theme.trackRadius
                color: Theme.accent
            }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -10
                anchors.bottomMargin: -8
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                function at(x) { return Math.max(0, Math.min(1, x / tsTrack.width)) }
                onPressed: (mouse) => ts.moved(at(mouse.x))
                onPositionChanged: (mouse) => { if (pressed) ts.moved(at(mouse.x)) }
                onWheel: (wheel) => ts.moved(Math.max(0, Math.min(1, ts.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
    }

    // Small button inside a tile's extra area.
    component TileButton: Rectangle {
        id: tb
        property string label: ""
        property bool selected: false
        signal clicked()
        anchors.bottom: parent ? parent.bottom : undefined
        height: Math.min(Theme.controlHeight, parent ? parent.height : Theme.controlHeight)
        radius: Theme.controlRadius
        color: tb.selected ? Theme.accent : tbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
        Text {
            anchors.centerIn: parent
            text: tb.label
            color: tb.selected ? Theme.textOnLight : Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: tb.selected
        }
        MouseArea {
            id: tbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }
}
