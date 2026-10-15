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
        "qs-update", "qs-hdr", "qs-sunset", "qs-idle", "qs-gamefocus", "qs-phone", "qs-vpn"]
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

        // The tiles' data sources poll only while the card is open.
        Binding { target: NetInfo; property: "active"; value: panel.shown }
        Binding { target: PowerInfo; property: "active"; value: panel.shown }
        Binding { target: Displays; property: "active"; value: panel.shown }
        Binding { target: AudioInfo; property: "active"; value: panel.shown }

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
            : bt.connectedDevices.length > 1 ? bt.connectedDevices.length + " connected"
            : bt.connectedDevices.length === 1 ? bt.connectedDevices[0].name || bt.connectedDevices[0].deviceName
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
        // (wide) or long-press/right-click (small) opens, "" for none;
        // `opens`: a tap opens that page too, so no chevron. `short`: the
        // 1-column label, when `label` doesn't fit or say enough there.
        // `extraSub`: the status line once its control/body shows (1 row:
        // none, 2 rows: this), when those repeat `sub`. `detail`: a 2-row
        // tile's line above its control.
        function tileInfo(id) {
            switch (id) {
            case "wifi": return {
                glyph: Networking.wifiEnabled || !net.wifiDevice ? (net.wiredUp && !net.wifiUp ? "\u{f0200}" : "\u{f05a9}") : "\u{f05aa}",
                label: net.wifiDevice ? "Wi-Fi" : "Network", sub: panel.wifiSubtitle,
                extraSub: net.wifiUp && net.wifiNetwork ? "Signal " + Math.round(net.wifiNetwork.signalStrength * 100) + "%" : panel.wifiSubtitle,
                active: net.wifiDevice ? Networking.wifiEnabled : net.wiredUp, more: net.wifiDevice ? "qs-wifi" : "" }
            case "bluetooth": return {
                glyph: root.adapter && root.adapter.enabled ? "\u{f00af}" : "\u{f00b2}",
                label: "Bluetooth", sub: panel.btSubtitle,
                extraSub: bt.connectedDevices.length > 0 ? bt.connectedDevices.length + " connected" : panel.btSubtitle,
                active: !!(root.adapter && root.adapter.enabled), more: root.adapter ? "qs-bluetooth" : "" }
            case "airplane": return {
                glyph: "\u{f001d}", label: "Airplane", sub: panel.onOff(panel.airplane),
                detail: "Or one radio at a time", active: panel.airplane, more: "" }
            case "nightlight": return {
                glyph: "\u{f0594}", label: "Night Light",
                sub: ShellState.sunsetWarm ? ShellState.sunsetKelvin + "K" : "Off", extraSub: panel.onOff(ShellState.sunsetWarm),
                detail: ShellState.sunsetScheduleFollow ? "Follows the sunset schedule" : "Manual, schedule off",
                active: ShellState.sunsetWarm, more: "qs-sunset" }
            case "silence": return {
                glyph: ShellState.notificationsMuted ? "\u{f009b}" : "\u{f009a}", label: "Silence",
                sub: !ShellState.notificationsMuted ? "Off"
                    : ShellState.notificationsMutedUntil > 0 ? "Until " + Qt.formatTime(new Date(ShellState.notificationsMutedUntil), "HH:mm")
                    : "Notifications muted",
                detail: ShellState.notificationsMuted ? "" : "Mute notifications for",
                active: ShellState.notificationsMuted, more: "" }
            // The input device, like Sound is the output: lit while live,
            // the tap mutes. (Id kept from "Mic Mute" so saved layouts hold.)
            case "micmute": return {
                glyph: panel.micMuted ? "\u{f036d}" : "\u{f036c}", label: "Mic",
                sub: panel.micMuted ? "Muted" : root.nodeName(root.source),
                active: !!root.source && !panel.micMuted, more: "qs-audio" }
            case "awake": return {
                glyph: "\u{f0176}", label: "Stay Awake", sub: ShellState.idleActive ? "Screen stays on" : "Off",
                detail: ShellState.idleActive ? "No dimming, locking or sleep" : "Locks when idle",
                active: ShellState.idleActive, more: "qs-idle" }
            case "gamefocus": return {
                glyph: "\u{f02b4}", label: "Game Focus",
                sub: GameFocus.enabled ? (GameFocus.dimming ? "Dimming" : "Armed") : "Off",
                detail: "Dims the other screens", active: GameFocus.enabled, more: "qs-gamefocus" }
            case "hdr": return {
                glyph: "\u{f0d7d}", label: "HDR", sub: panel.onOff(HdrSettings.active),
                detail: "On these monitors", active: HdrSettings.active, more: "qs-hdr" }
            case "opaque": return {
                glyph: "", label: "Opaque",
                sub: ShellState.transparencyOpaque ? "Solid" : Math.round(BarSettings.terminalOpacity * 100) + "%",
                extraSub: ShellState.transparencyOpaque ? "Solid" : "Translucent",
                detail: "Terminal background",
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
                short: "Phone",
                detail: !Sichlink.phone || !Sichlink.phone.connected ? ""
                    : [Sichlink.lockText(Sichlink.phone), Sichlink.phone.adb_serial ? "Wireless adb" : "",
                       Sichlink.phone.bt_link ? "Bluetooth" : ""].filter(t => t !== "").join(" · "),
                active: PhoneMirrorState.open && !PhoneMirrorState.collapsed,
                busy: PhoneMirrorState.loading || Sichlink.busy, more: "qs-phone", opens: true }
            case "powerprofile": {
                const p = UP.PowerProfiles.profile
                return {
                    glyph: p === UP.PowerProfile.Performance ? "" : p === UP.PowerProfile.PowerSaver ? "\u{f032a}" : "",
                    label: "Power", sub: p === UP.PowerProfile.Performance ? "Performance" : p === UP.PowerProfile.PowerSaver ? "Saver" : "Balanced",
                    extraSub: "", detail: panel.batteryText() ? "Battery " + panel.batteryText() : "",
                    active: p !== UP.PowerProfile.Balanced, more: "" }
            }
            case "sound": return {
                glyph: vol.icon(), label: "Sound", sub: root.nodeName(root.sink),
                active: !!(root.sink && root.sink.audio && !root.sink.audio.muted), more: "qs-audio" }
            case "display": return {
                glyph: "\u{f0e51}", label: "Display",
                sub: Quickshell.screens.length + (Quickshell.screens.length === 1 ? " display" : " displays"),
                detail: Quickshell.screens.map(s => s.name).join(" · "),
                active: false, more: "qs-display", opens: true }
            case "update": return {
                glyph: "\u{f06b0}", label: "Updates",
                sub: upd.updating ? "Updating…" : upd.checking && upd.count === null ? "Checking…"
                    : upd.count === null ? "Unknown" : upd.count === 0 ? "Up to date"
                    : upd.count + (upd.count === 1 ? " update" : " updates"),
                detail: [upd.dnfCount ? upd.dnfCount + " dnf" : "", upd.flatpakCount ? upd.flatpakCount + " flatpak" : ""]
                    .filter(t => t !== "").join(" · "),
                active: !!upd.count, busy: upd.updating || upd.checking, more: "qs-update", opens: true }
            case "vpn": return {
                glyph: "\u{f0565}", label: "Proton VPN",
                sub: VpnStatus.busy ? "Disconnecting…" : VpnStatus.connected ? VpnStatus.server : VpnStatus.connecting ? "Connecting…" : "Off",
                active: VpnStatus.connected, busy: VpnStatus.busy || VpnStatus.connecting, more: "qs-vpn" }
            // What closing the lid does with another monitor connected
            // (LidSettings.qml, hypr/keybindings.lua). `short`: the 1x1
            // tile's label, which has to carry the state on its own.
            case "lid": return {
                glyph: LidSettings.sleep ? "\u{f04b2}" : "\u{f0322}", label: "When lid closes",
                short: LidSettings.sleep ? "Lid: Sleep" : "Lid: Keep on",
                extraSub: "", detail: "With another monitor",
                sub: LidSettings.sleep ? "Sleep" : "Screen off, keep working",
                active: LidSettings.sleep, more: "" }
            // The deployed SichOS commit (update.sh info via SichosVersion):
            // lit when it isn't the checkout's HEAD -- pinned by
            // `update.sh switch`, or a deploy that didn't happen.
            case "version": {
                const sv = SichosVersion
                return {
                    glyph: "\u{f062c}", label: "SichOS",
                    sub: !sv.known ? (sv.repo === "" ? "No version recorded" : "…")
                        : [sv.name, sv.info.deployed].concat(sv.flags.slice(0, 1)).join(" · "),
                    short: sv.known ? sv.info.deployed : "SichOS",
                    detail: sv.known ? sv.info.deployed_subject : "",
                    active: sv.pinned || sv.offHead, more: "" }
            }
            case "stats": return {
                glyph: "\u{f035b}", label: "System",
                sub: "CPU " + Math.round(SystemStats.cpu * 100) + "% · RAM " + Math.round(SystemStats.ram * 100) + "%"
                    + (SystemStats.temp > 0 ? " · " + Math.round(SystemStats.temp) + "°C" : ""),
                extraSub: SystemStats.temp > 0 ? Math.round(SystemStats.temp) + "°C" : "",
                active: false, more: "" }
            }
            return { glyph: "", label: id, sub: "", active: false, more: "" }
        }

        // Scrolling over a level tile changes its level, like the bar pill.
        function tileWheel(id, wheel) {
            const step = wheel.angleDelta.y > 0 ? 0.05 : wheel.angleDelta.y < 0 ? -0.05 : 0
            switch (id) {
            case "sound": vol.wheel(wheel); return
            case "micmute":
                if (root.source && root.source.audio) root.source.audio.volume = Math.max(0, Math.min(1, root.source.audio.volume + step))
                return
            case "display": if (panel.hasBacklight) panel.setBacklight((panel.pendingBacklight >= 0 ? panel.pendingBacklight / 100 : panel.backlight) + step); return
            }
            wheel.accepted = false
        }

        function tileToggle(id) {
            switch (id) {
            case "wifi": if (net.wifiDevice) Networking.wifiEnabled = !Networking.wifiEnabled; break
            case "bluetooth": if (root.adapter) ShellState.setBluetooth(!root.adapter.enabled); break
            // Turning it off puts the radios back as they were.
            case "airplane": ShellState.setAirplane(!panel.airplane); break
            case "nightlight": ShellState.forceSunsetWarm(!ShellState.sunsetWarm); break
            case "silence": ShellState.setNotificationsMuted(!ShellState.notificationsMuted, 0); break
            case "micmute": if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted; break
            case "awake": ShellState.setIdleActive(!ShellState.idleActive, 0); break
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
            case "lid": LidSettings.setSleep(!LidSettings.sleep); break
            // update.sh status + recent commits in a terminal.
            case "version": SichosVersion.openDetails(); break
            // btop, floated/centered like SUPER+B (window_rules.lua).
            case "stats": Quickshell.execDetached(["kitty", "--class", "btop", "-e", "btop"]); break
            }
        }

        // Grid: 4 columns of tileUnit x tileHeight cells.
        readonly property real tileSpacing: 10
        readonly property real tileUnit: (root.cardWidth - 3 * panel.tileSpacing) / 4
        readonly property real tileHeight: 64

        // --- Per-size content. tileView(id, w, h): tileInfo plus what the
        // tile shows at that size:
        //   title / sub -- the header lines (title defaults to the label);
        //   short -- 1x1 label; lines -- 1x2 status lines (default: sub
        //     split at " · ");
        //   control -- a Component (slider/buttons/readout) shown at 1 row
        //     under the title (`under`, with `tag` on the title line) or
        //     beside the header, and at 2 rows under the `detail` line;
        //   body -- a 2-row tile's whole lower half instead (lists, graphs).
        // Components read `parent.cols`/`parent.tall` (their Loader's) to
        // adapt -- three buttons at 3 wide, presets at 2 rows.
        // 1-row controls that go under the title at 3 wide too: beside it
        // they'd get ~110px (buttons elided, the stats ran out of the tile).
        readonly property var underAt3: ["powerprofile", "update", "lid", "silence", "airplane", "hdr", "phone", "awake"]
        // ...and at 4 wide: rows of four buttons.
        readonly property var underAt4: ["phone", "silence"]
        function clock(ms) {
            return Qt.formatTime(new Date(ms), TimeRegion.use24Hour ? "HH:mm" : "h:mm AP")
        }
        function pct(v) { return Math.round(v * 100) + "%" }
        // Apps recording, one name each: OBS opens a stream per capture
        // ("OBS", "OBS: Application Audio Capture (PipeWire)", ...).
        function micUsers() {
            const out = []
            for (const st of AudioInfo.inputStreams) {
                const name = st.name.split(":")[0].trim()
                if (name && !out.includes(name)) out.push(name)
            }
            return out
        }
        function tileView(id, w, h) {
            const v = Object.assign({ title: "", tag: "", titleTail: "", lines: null, control: null, body: null, detail: "", under: undefined, besideWidth: 0 },
                panel.tileInfo(id))
            v.title = v.label
            const tall = h === 2
            switch (id) {
            case "wifi": {
                const n = net.wifiUp ? net.wifiNetwork : null
                const link = n ? panel.pct(n.signalStrength) + (NetInfo.wifiBand ? " · " + NetInfo.wifiBand : "") : ""
                if (n) v.short = n.name
                else if (net.wifiDevice && !Networking.wifiEnabled) v.short = "Wi-Fi off"
                if (NetInfo.connectivity) v.sub = (n ? n.name + " · " : "") + NetInfo.connectivity
                // 1-row tiles 2+ wide: the band beside the title, so the
                // name keeps the whole status line (at 2 wide it fills it).
                if (!tall && w >= 2 && n) v.titleTail = NetInfo.wifiBand
                v.lines = n ? [n.name, link, NetInfo.connectivity].filter(t => t) : [v.sub]
                if (w >= 3 && !tall && (n || net.wiredUp)) { v.control = meterNet; v.under = false }
                if (tall) {
                    v.body = bodyWifi
                    if (n) v.sub = w >= 3 && NetInfo.ipv4 ? link + " · " + NetInfo.ipv4 : link
                }
                break
            }
            case "bluetooth": {
                const devs = bt.connectedDevices
                const batt = d => d.batteryAvailable && d.battery > 0 ? panel.pct(d.battery) : ""
                if (devs.length === 1) v.short = devs[0].name || devs[0].deviceName
                else if (devs.length > 1) v.short = devs.length + " devices"
                v.lines = devs.length === 0 ? [v.sub]
                    : devs.length > 1 ? [devs.length + " connected"]
                    : [devs[0].name || devs[0].deviceName, batt(devs[0])].filter(t => t)
                // A bare percentage can't say whose it is once the status
                // line is just a count, so at 3 wide (no names in the
                // readout) it shows only for a single device.
                if (w >= 3 && !tall && devs.some(d => batt(d)) && (w >= 4 || devs.length === 1)) {
                    v.control = meterBt
                    v.under = false
                    if (w >= 4) v.sub = devs.length + " connected"
                    // 3 wide shows bare percentages: at the right edge, so the
                    // device name keeps the status line (from the shared
                    // inline column it got ~90px, "GuliKit Controll…").
                    else v.besideWidth = 34
                }
                if (tall) {
                    v.body = bodyBt
                    v.sub = devs.length > 0 ? devs.length + " connected" : v.sub
                }
                break
            }
            case "airplane":
                v.control = extraRadios
                v.sub = panel.airplane ? "On" : [Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off",
                    root.adapter && root.adapter.enabled ? "BT on" : "BT off"].join(" · ")
                v.lines = panel.airplane ? ["On"] : [Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off",
                    root.adapter && root.adapter.enabled ? "BT on" : "BT off"]
                v.detail = "Or one radio at a time"
                break
            case "nightlight": {
                v.control = tall ? bodyNight : extraWarmth
                const next = ShellState.sunsetScheduleFollow && ShellState.sunsetNextChange() > 0
                    ? (ShellState.sunsetWarm ? "Until " : "At ") + panel.clock(ShellState.sunsetNextChange()) : ""
                v.tag = next || (ShellState.sunsetWarm ? ShellState.sunsetKelvin + "K" : "")
                if (!tall && !v.under && w >= 4) v.sub = ShellState.sunsetScheduleFollow ? "Auto" : panel.onOff(ShellState.sunsetWarm)
                if (tall) {
                    v.body = bodyNight
                    v.sub = (ShellState.sunsetWarm ? ShellState.sunsetKelvin + "K" : "Off")
                        + (ShellState.sunsetScheduleFollow ? " · auto" : "")
                }
                v.lines = [ShellState.sunsetWarm ? ShellState.sunsetKelvin + "K" : "Off", ShellState.sunsetScheduleFollow ? "Auto" : ""].filter(t => t)
                break
            }
            case "silence": {
                const until = ShellState.notificationsMutedUntil
                if (ShellState.notificationsMuted) v.short = until > 0 ? "Until " + panel.clock(until) : "Silenced"
                v.control = extraSilence
                const missed = NotificationHistory.missedCount > 0 ? NotificationHistory.missedCount + " missed" : ""
                v.tag = [ShellState.notificationsMuted && until > 0 ? "Until " + panel.clock(until) : "", missed].filter(t => t).join(" · ")
                if (ShellState.notificationsMuted) v.sub = [until > 0 ? "Until " + panel.clock(until) : "Until turned off", missed].filter(t => t).join(" · ")
                if (tall && w >= 3) v.body = bodySilence
                v.detail = ShellState.notificationsMuted ? "" : "Mute notifications for"
                v.lines = !ShellState.notificationsMuted ? ["Off"]
                    : (until > 0 ? ["Until", panel.clock(until)] : ["Until you", "turn it off"]).concat(missed ? [missed] : [])
                break
            }
            case "micmute": {
                const level = root.source && root.source.audio ? panel.pct(root.source.audio.volume) : ""
                const users = panel.micUsers()
                v.short = panel.micMuted ? "Muted" : "Mic " + level
                v.control = extraMic
                v.tag = panel.micMuted ? "Muted" : AudioInfo.shortName(root.source)
                // 2 rows: the body says who's recording.
                v.sub = (panel.micMuted ? "Muted" : AudioInfo.shortName(root.source)) + (users.length > 0 && !tall ? " · " + users[0] : "")
                if (w === 3) v.under = true
                if (tall) v.body = bodyMic
                v.lines = [panel.micMuted ? "Muted" : level, AudioInfo.shortName(root.source), users[0] || ""].filter(t => t)
                break
            }
            case "awake":
                if (ShellState.idleActive && ShellState.idleActiveUntil > 0) {
                    v.short = "Until " + panel.clock(ShellState.idleActiveUntil)
                    v.sub = v.short
                }
                v.tag = ShellState.idleActive ? (ShellState.idleActiveUntil > 0 ? "Until " + panel.clock(ShellState.idleActiveUntil) : "On") : ""
                v.control = extraAwake
                v.detail = ShellState.idleActive ? "No dimming, locking or sleep" : "Locks when idle"
                v.lines = !ShellState.idleActive ? ["Off"]
                    : ShellState.idleActiveUntil > 0 ? ["Until", panel.clock(ShellState.idleActiveUntil)] : ["On"]
                break
            case "gamefocus":
                v.control = extraDim
                v.tag = GameFocus.enabled ? (GameFocus.dimming ? "Dimming" : "Armed") : ""
                v.detail = GameFocus.dimming && Hyprland.activeToplevel ? Hyprland.activeToplevel.title : "Dims the screens without the game"
                v.lines = [v.sub, GameFocus.enabled ? "Dim " + panel.pct(GameFocus.dimAmount) : ""].filter(t => t)
                break
            case "hdr": {
                const on = Displays.monitors.filter(m => HdrSettings.isSelected(m.name))
                v.control = extraHdrMonitors
                v.tag = panel.onOff(HdrSettings.active)
                v.sub = HdrSettings.active ? "On" + (on.length ? " · " + on.map(m => m.name).join(", ") : "") : "Off"
                v.detail = on.length === 0 ? "Pick the monitors it applies to"
                    : HdrSettings.active ? on.map(m => m.name + (m.hdrApplied ? " HDR" : " SDR")).join(" · ")
                    : "Applies to " + on.map(m => m.name).join(", ")
                if (tall && w >= 3) v.body = bodyHdr
                v.lines = [panel.onOff(HdrSettings.active), on.map(m => m.name).join(", ")].filter(t => t)
                break
            }
            case "opaque":
                v.short = ShellState.transparencyOpaque ? "Solid" : "Glass " + Math.round(BarSettings.terminalOpacity * 100) + "%"
                v.control = tall ? bodyOpaque : extraOpacity
                v.tag = ShellState.transparencyOpaque ? "Solid" : "Glass"
                v.sub = ShellState.transparencyOpaque ? "Solid" : "Bar + terminals"
                if (tall) v.body = bodyOpaque
                v.lines = [ShellState.transparencyOpaque ? "Solid" : "Glass " + Math.round(BarSettings.terminalOpacity * 100) + "%"]
                break
            case "phone": {
                const d = Sichlink.phone
                const batt = d && d.connected ? Sichlink.batteryText(d) : ""
                const pctOnly = d && d.connected && d.battery !== null && d.battery !== undefined ? d.battery + "%" : ""
                v.short = pctOnly || (PhoneMirrorState.open ? "Mirroring" : "Phone")
                if (w === 1 && tall) v.label = "Phone"
                v.control = extraPhoneButtons
                v.tag = w >= 4 ? batt : pctOnly
                v.detail = !d || !d.connected ? ""
                    : [Sichlink.lockText(d), d.adb_serial ? "Wireless adb" : "", d.bt_link ? "Extend Unlock" : ""].filter(t => t !== "").join(" · ")
                v.lines = [pctOnly, d && d.charging ? "Charging" : "",
                    PhoneMirrorState.open ? "Mirroring" : d && d.connected ? Sichlink.lockText(d) : "Offline"].filter(t => t)
                break
            }
            case "powerprofile": {
                const bat = PowerInfo.present
                const pctText = bat && root.battery ? panel.pct(root.battery.percentage) : ""
                v.short = v.sub
                v.control = extraProfiles
                v.tag = pctText
                const time = PowerInfo.timeText()
                v.sub = [pctText, time].filter(t => t).join(" · ") || v.sub
                const watts = PowerInfo.watts !== 0 ? (PowerInfo.watts > 0 ? "+" : "−") + Math.abs(PowerInfo.watts).toFixed(1) + " W"
                    : SystemStats.apuWatts > 0 ? "On AC · APU " + Math.round(SystemStats.apuWatts) + " W" : ""
                v.detail = [watts, w >= 3 && PowerInfo.healthPercent > 0 ? "health " + Math.round(PowerInfo.healthPercent) + "%" : "",
                    w >= 3 && PowerInfo.cycles > 0 ? PowerInfo.cycles + " cycles" : ""].filter(t => t).join(" · ")
                v.lines = [v.short, pctText, time].filter(t => t)
                break
            }
            case "sound":
                v.short = root.sink && root.sink.audio && root.sink.audio.muted ? "Muted" : "Sound " + (root.sink && root.sink.audio ? panel.pct(root.sink.audio.volume) : "")
                v.control = tall ? bodySound : extraVolume
                v.tag = AudioInfo.shortName(root.sink)
                v.sub = AudioInfo.shortName(root.sink) + (AudioInfo.outputStreams.length > 0 ? " · " + AudioInfo.outputStreams[0].name : "")
                if (w === 3) v.under = true
                if (tall) v.body = bodySound
                v.lines = [root.sink && root.sink.audio ? panel.pct(root.sink.audio.volume) : "", AudioInfo.shortName(root.sink),
                    AudioInfo.outputStreams.length > 0 ? AudioInfo.outputStreams[0].name : ""].filter(t => t)
                break
            case "display": {
                const n = Displays.monitors.filter(m => !m.disabled).length || Quickshell.screens.length
                v.sub = n + (n === 1 ? " display" : " displays")
                v.control = panel.hasBacklight ? extraBrightness : null
                v.tag = v.sub
                v.detail = Displays.monitors.filter(m => !m.disabled).map(m => m.friendly).join(" · ")
                if (tall && w >= 3) v.body = bodyDisplays
                v.lines = [v.sub, panel.hasBacklight ? "Panel " + panel.pct(panel.backlight) : ""].filter(t => t)
                break
            }
            case "update":
                v.short = upd.count ? upd.count + (upd.count === 1 ? " update" : " updates") : upd.count === 0 ? "Up to date" : "Updates"
                v.control = extraUpdate
                if (tall && w >= 4) v.body = bodyUpdates
                if (upd.rebootNeeded) v.sub = "Restart to finish"
                // 1 row: the count is the title (the control hides the status).
                if (!tall && w <= 3) v.title = upd.rebootNeeded ? "Restart needed" : v.short
                v.tag = w >= 3 ? [upd.dnfCount ? upd.dnfCount + " dnf" : "", upd.flatpakCount ? upd.flatpakCount + " flatpak" : ""].filter(t => t).join(" · ") : ""
                v.detail = [upd.dnfCount ? upd.dnfCount + " dnf" : "", upd.flatpakCount ? upd.flatpakCount + " flatpak" : ""]
                    .filter(t => t !== "").join(" · ")
                v.lines = [v.sub, v.detail.split(" · ")[0] || "", v.detail.split(" · ")[1] || ""].filter(t => t)
                break
            case "vpn": {
                const where = [VpnStatus.countryFlag, VpnStatus.city].filter(t => t).join(" ")
                v.short = VpnStatus.connected ? (VpnStatus.countryFlag + " " + VpnStatus.server).trim() : VpnStatus.connecting ? "Connecting…" : "VPN off"
                v.sub = VpnStatus.connecting && !VpnStatus.connected ? "Connecting…"
                    : VpnStatus.connected ? [where, VpnStatus.server].filter(t => t).join(" · ") : "Off"
                if (w >= 3 || tall) v.control = extraVpn
                if (w >= 3 && !tall) v.under = false
                v.detail = VpnStatus.connected ? [VpnStatus.protocol, VpnStatus.load >= 0 ? "load " + VpnStatus.load + "%" : "",
                    VpnStatus.secureCore ? "Secure Core" : "", VpnStatus.killSwitch ? "kill switch on" : ""].filter(t => t).join(" · ")
                    : VpnStatus.error || (VpnStatus.lastServer ? "Tap to reconnect to " + VpnStatus.lastServer : "Tap for the fastest server")
                v.lines = VpnStatus.connected ? [VpnStatus.server, VpnStatus.city].filter(t => t) : ["Off"]
                break
            }
            case "lid": {
                if (w <= 2) { v.title = "Lid closes"; v.label = "Lid closes" }
                v.control = extraLid
                v.tag = Displays.docked ? Displays.externalCount + (Displays.externalCount === 1 ? " monitor" : " monitors") : "Undocked"
                v.sub = LidSettings.sleep ? "Sleep" : "Keep working"
                v.detail = !Displays.docked ? "Undocked it always sleeps"
                    : LidSettings.sleep ? "Suspends the laptop" : "Panel off, others keep running"
                v.lines = [LidSettings.sleep ? "Sleep" : "Keep on", v.tag]
                break
            }
            case "version": {
                const sv = SichosVersion
                if (!sv.known) break
                const when = sv.ago(sv.info.deployed_at)
                // The flags (pinned, to pull, parked edits...) go first:
                // they're why anyone looks; when it was deployed otherwise.
                const tail = sv.flags.length > 0 ? sv.flags : [when]
                v.short = sv.info.deployed
                if (!tall && w >= 2) v.titleTail = sv.name
                v.sub = (w >= 2 && !tall ? [sv.info.deployed] : [sv.name, sv.info.deployed])
                    .concat(w >= 3 ? tail.slice(0, 2) : tail.slice(0, 1))
                    .concat(w >= 4 && !tall ? [sv.info.deployed_subject] : []).join(" · ")
                v.lines = [sv.name, sv.info.deployed, tail[0]]
                v.detail = sv.info.deployed_subject
                if (tall) {
                    v.sub = sv.name + " · " + sv.info.deployed
                    v.body = bodyVersion
                }
                break
            }
            case "stats": {
                const cpu = "CPU " + panel.pct(SystemStats.cpu)
                const temp = SystemStats.temp > 0 ? Math.round(SystemStats.temp) + "°C" : ""
                const ram = "RAM " + SystemStats.ramUsedGb.toFixed(1) + " / " + Math.round(SystemStats.ramTotalGb) + " GB"
                const gpu = SystemStats.gpu >= 0 ? "GPU " + panel.pct(SystemStats.gpu) : ""
                v.short = panel.pct(SystemStats.cpu) + (temp ? " · " + temp : "")
                v.lines = [cpu, "RAM " + panel.pct(SystemStats.ram), temp].filter(t => t)
                if (!tall && w <= 3) {
                    v.title = [cpu, temp].filter(t => t).join(" · ")
                    v.sub = w === 2 ? ram : ["RAM " + panel.pct(SystemStats.ram), gpu].filter(t => t).join(" · ")
                    if (w === 3) { v.control = extraSpark; v.under = false; v.besideWidth = 64 }
                } else if (!tall) {
                    v.sub = [temp, SystemStats.fanRpm > 0 ? SystemStats.fanRpm + " rpm" : ""].filter(t => t).join(" · ")
                    v.control = extraMeters
                    v.under = false
                } else {
                    v.body = extraStats
                    v.sub = [temp ? "CPU " + temp : "", SystemStats.gpuTemp > 0 ? "GPU " + Math.round(SystemStats.gpuTemp) + "°" : "",
                        w >= 3 && SystemStats.fanRpm > 0 ? SystemStats.fanRpm + " rpm" : "",
                        w >= 4 ? "up " + SystemStats.durationText(SystemStats.uptimeSec) : ""].filter(t => t).join(" · ")
                }
                break
            }
            }
            if (w === 1) { v.control = null; v.body = null }
            if (!v.lines) v.lines = v.sub.split(" · ")
            if (v.under === undefined)
                v.under = w === 2 || (w === 3 && panel.underAt3.includes(id)) || (w >= 4 && panel.underAt4.includes(id))
            // The detail line only says what the header doesn't.
            if (v.detail === v.sub) v.detail = ""
            return v
        }
        // --- Tile controls and bodies (see tileView). `parent` is the
        // Loader: parent.cols = tile width in columns, parent.tall = 2 rows.

        Component {
            id: extraUpdate
            ButtonRow {
                buttons: [
                    upd.rebootNeeded
                        ? { label: "Restart", selected: true, action: () => { ShellState.activePopup = ""; upd.reboot() } }
                        : { label: upd.checking ? "Checking…" : "Check", action: () => upd.checkNow() },
                    { label: upd.updating ? "Updating…" : "Update all", selected: !!upd.count && !upd.updating,
                      available: !!upd.count || upd.updating, action: () => upd.runUpdate() }
                ]
            }
        }
        // 4x2 Updates: pending packages beside the buttons.
        Component {
            id: bodyUpdates
            Row {
                spacing: 12
                Column {
                    width: parent.width - 100 - 12
                    spacing: 2
                    Repeater {
                        model: upd.packages.slice(0, 2)
                        delegate: TileListRow {
                            required property var modelData
                            name: modelData.name
                            status: modelData.kind === "flatpak" ? "flatpak" : modelData.version
                            onClicked: root.openPopup("qs-update")
                        }
                    }
                    Text {
                        visible: upd.packages.length > 2
                        leftPadding: 4
                        text: "+" + (upd.packages.length - 2) + " more"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Text {
                        visible: upd.packages.length === 0
                        leftPadding: 4
                        text: upd.count === 0 ? "Everything is up to date" : upd.checking ? "Checking…" : "No list yet"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Column {
                    width: 100
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    TileButton {
                        width: parent.width
                        anchors.bottom: undefined
                        height: Theme.controlHeight
                        label: upd.updating ? "Updating…" : "Update all"
                        selected: !!upd.count && !upd.updating
                        available: !!upd.count || upd.updating
                        onClicked: upd.runUpdate()
                    }
                    TileButton {
                        width: parent.width
                        anchors.bottom: undefined
                        height: Theme.controlHeight
                        label: upd.rebootNeeded ? "Restart" : upd.checking ? "Checking…" : "Check"
                        onClicked: upd.rebootNeeded ? (ShellState.activePopup = "", upd.reboot()) : upd.checkNow()
                    }
                }
            }
        }
        // VPN: 1 row shows where it's connected (the tap already toggles);
        // 2 rows get the buttons.
        Component {
            id: extraVpn
            Item {
                Readout2 {
                    visible: !parent.parent.tall
                    width: parent.width
                    line1: VpnStatus.connected ? [VpnStatus.protocol, VpnStatus.connectedSince > 0
                        ? SystemStats.durationText((Date.now() - VpnStatus.connectedSince) / 1000) : ""].filter(t => t).join(" · ")
                        : VpnStatus.connecting ? "Connecting…" : ""
                    line2: VpnStatus.connected ? [VpnStatus.load >= 0 ? "Load " + VpnStatus.load + "%" : "",
                        VpnStatus.killSwitch ? "Kill switch" : ""].filter(t => t).join(" · ") : ""
                }
                ButtonRow {
                    visible: !!parent.parent.tall
                    width: parent.width
                    height: parent.height
                    buttons: [
                        { label: VpnStatus.connected || VpnStatus.connecting ? "Disconnect" : "Connect", selected: VpnStatus.connected, action: () => VpnStatus.toggle() },
                        { label: "Servers", action: () => root.openPopup("qs-vpn") }
                    ]
                }
            }
        }
        // System. 1 row, 3 wide: a CPU sparkline; 4 wide: CPU/RAM/GPU bars;
        // 2 rows: graphs (CPU, RAM, + GPU at 3+ wide), plus a summary line
        // at 4 wide.
        Component {
            id: extraSpark
            MiniGraph { height: 30; history: SystemStats.cpuHistory }
        }
        Component {
            id: extraMeters
            Row {
                id: meters
                spacing: 8
                Repeater {
                    model: [
                        { label: "CPU", value: SystemStats.cpu },
                        { label: "RAM", value: SystemStats.ram },
                        { label: "GPU", value: SystemStats.gpu }
                    ].filter(m => m.value >= 0)
                    delegate: Column {
                        required property var modelData
                        width: (meters.width - 16) / 3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: modelData.label + " " + panel.pct(modelData.value)
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.track
                            Rectangle { width: parent.width * Math.min(1, modelData.value); height: parent.height; radius: 2; color: Theme.accent }
                        }
                    }
                }
            }
        }
        Component {
            id: extraStats
            Column {
                id: statsBox
                readonly property bool wide: parent.cols >= 4
                spacing: 4
                Row {
                    id: graphs
                    width: parent.width
                    height: statsBox.height - (statsBox.wide ? summary.height + 4 : 0)
                    spacing: 10
                    Repeater {
                        model: [
                            { label: "CPU", value: SystemStats.cpu, history: SystemStats.cpuHistory },
                            { label: "RAM", value: SystemStats.ram, history: SystemStats.ramHistory },
                            { label: "GPU", value: SystemStats.gpu, history: SystemStats.gpuHistory }
                        ].filter(g => g.value >= 0).slice(0, statsBox.parent.cols >= 3 ? 3 : 2)
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: (graphs.width - 10 * (statsBox.parent.cols >= 3 ? 2 : 1)) / (statsBox.parent.cols >= 3 ? 3 : 2)
                            height: graphs.height
                            Text {
                                id: graphLabel
                                text: modelData.label + " " + panel.pct(modelData.value)
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                            MiniGraph {
                                anchors.top: graphLabel.bottom
                                anchors.topMargin: 4
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                history: modelData.history
                            }
                        }
                    }
                }
                Text {
                    id: summary
                    visible: statsBox.wide
                    width: parent.width
                    elide: Text.ElideRight
                    text: ["RAM " + SystemStats.ramUsedGb.toFixed(1) + "/" + Math.round(SystemStats.ramTotalGb) + " GB",
                        SystemStats.swapTotalGb > 0 ? "swap " + SystemStats.swapUsedGb.toFixed(1) + " GB" : "",
                        SystemStats.diskTotalGb > 0 ? "disk " + Math.round(SystemStats.diskUsedGb / SystemStats.diskTotalGb * 100) + "%" : "",
                        "↓" + SystemStats.rateText(SystemStats.netRx)].filter(t => t).join(" · ")
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
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
        // 2-row Sound: volume, then the outputs to switch to (rows at 2
        // wide, buttons wider); 4 wide adds what's playing.
        Component {
            id: bodySound
            Row {
                id: soundBody
                spacing: 12
                readonly property bool split: parent.cols >= 4 && AudioInfo.outputStreams.length > 0
                Column {
                    width: soundBody.split ? (soundBody.width - 12) / 2 : soundBody.width
                    spacing: 6
                    TileSlider {
                        width: parent.width
                        height: 24
                        value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                        onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
                    }
                    ButtonRow {
                        visible: root.sinks.length > 1
                        width: parent.width
                        height: Theme.controlHeight
                        buttons: root.sinks.slice(0, soundBody.parent.cols >= 3 ? 3 : 2).map(n => ({
                            label: AudioInfo.shortName(n), selected: n === root.sink,
                            action: () => AudioInfo.setDefaultSink(n) }))
                    }
                    Text {
                        visible: root.sinks.length <= 1
                        width: parent.width
                        elide: Text.ElideRight
                        text: AudioInfo.outputStreams.length > 0 ? "Playing: " + AudioInfo.outputStreams.map(s => s.name).join(", ") : root.nodeName(root.sink)
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Column {
                    visible: soundBody.split
                    width: (soundBody.width - 12) / 2
                    spacing: 2
                    Repeater {
                        model: soundBody.split ? AudioInfo.outputStreams.slice(0, 3) : []
                        delegate: Item {
                            required property var modelData
                            width: parent.width
                            height: 20
                            Text {
                                id: appName
                                width: 62
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelData.name
                                color: Theme.textMuted
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                            TileSlider {
                                anchors.left: appName.right
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                height: 20
                                value: modelData.node && modelData.node.audio ? modelData.node.audio.volume : 0
                                onMoved: (v) => { if (modelData.node && modelData.node.audio) modelData.node.audio.volume = v }
                            }
                        }
                    }
                }
            }
        }
        // 2-row Mic, like Sound's: level, then the inputs to switch to, or
        // (one input) who's recording / the device's full name.
        Component {
            id: bodyMic
            Column {
                id: micBody
                spacing: 6
                TileSlider {
                    width: parent.width
                    height: 24
                    value: root.source && root.source.audio ? root.source.audio.volume : 0
                    onMoved: (v) => { if (root.source && root.source.audio) root.source.audio.volume = v }
                }
                ButtonRow {
                    visible: root.sources.length > 1
                    width: parent.width
                    height: Theme.controlHeight
                    buttons: root.sources.slice(0, micBody.parent.cols >= 3 ? 3 : 2).map(n => ({
                        label: AudioInfo.shortName(n), selected: n === root.source,
                        action: () => AudioInfo.setDefaultSource(n) }))
                }
                Text {
                    visible: root.sources.length <= 1
                    width: parent.width
                    elide: Text.ElideRight
                    text: panel.micUsers().length > 0 ? "Used by " + panel.micUsers().join(", ") : root.nodeName(root.source)
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
        Component {
            id: extraBrightness
            TileSlider {
                value: panel.pendingBacklight >= 0 ? panel.pendingBacklight / 100 : panel.backlight
                onMoved: (v) => panel.setBacklight(v)
            }
        }
        // 2-row Display, 3+ wide: a row per monitor -- mode at 3 wide, its
        // own brightness slider at 4 (laptop backlight or DDC).
        Component {
            id: bodyDisplays
            Column {
                id: dispList
                spacing: 2
                readonly property bool sliders: parent.cols >= 4
                Repeater {
                    model: Displays.monitors.slice(0, 3)
                    delegate: Item {
                        required property var modelData
                        width: dispList.width
                        height: 22
                        Text {
                            id: monName
                            width: dispList.sliders ? 64 : dispList.width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: modelData.friendly || modelData.name
                            color: modelData.disabled ? Theme.textDim : Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            id: monMode
                            anchors.left: monName.right
                            anchors.leftMargin: 6
                            anchors.right: dispList.sliders ? undefined : parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: dispList.sliders ? Text.AlignLeft : Text.AlignRight
                            text: modelData.disabled ? "Off" : modelData.refreshRate + " Hz"
                                + (dispList.sliders ? "" : " · " + modelData.width + "×" + modelData.height)
                            color: Theme.textDim
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                        TileSlider {
                            visible: dispList.sliders && modelData.brightness >= 0
                            anchors.left: monMode.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            height: 22
                            value: modelData.brightness
                            onMoved: (v) => Displays.setBrightness(modelData.name, v)
                        }
                        Text {
                            visible: dispList.sliders && modelData.brightness < 0
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.disabled ? "" : "No brightness control"
                            color: Theme.textDim
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
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
        // 2-row Night Light: warmth, then Auto (follow the schedule) and,
        // 3+ wide, presets.
        Component {
            id: bodyNight
            Column {
                spacing: 8
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                TileSlider {
                    width: parent.width
                    height: 24
                    value: (ShellState.sunsetKelvin - 2000) / 3000
                    valueText: ShellState.sunsetKelvin + "K"
                    onMoved: (v) => ShellState.setSunsetKelvin(Math.round((2000 + v * 3000) / 100) * 100)
                }
                ButtonRow {
                    width: parent.width
                    height: Theme.controlHeight
                    buttons: [{ label: parent.parent.cols >= 4 ? "Auto " + ShellState.sunsetNightTime + "–" + ShellState.sunsetDayTime : "Auto",
                                selected: ShellState.sunsetScheduleFollow,
                                action: () => ShellState.setScheduleFollow(!ShellState.sunsetScheduleFollow) }]
                        .concat(parent.parent.cols >= 3 ? [2700, 3400, 4500].map(k => ({
                            label: k + "K", selected: ShellState.sunsetWarm && ShellState.sunsetKelvin === k,
                            action: () => { ShellState.setSunsetKelvin(k); if (!ShellState.sunsetWarm) ShellState.forceSunsetWarm(true) } })) : [])
                }
            }
        }
        // TransparencyPopup's range. Moving it while Solid switches to glass
        // -- otherwise the drag changes nothing visible.
        Component {
            id: extraOpacity
            TileSlider {
                value: (BarSettings.terminalOpacity - 0.5) / 0.45
                valueText: Math.round(BarSettings.terminalOpacity * 100) + "%"
                opacity: ShellState.transparencyOpaque ? 0.5 : 1
                onMoved: (v) => {
                    ShellState.setTerminalOpacity(0.5 + v * 0.45)
                    if (ShellState.transparencyOpaque) ShellState.setTransparencyOpaque(false)
                }
            }
        }
        Component {
            id: bodyOpaque
            Column {
                spacing: 8
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Loader { width: parent.width; height: 24; sourceComponent: extraOpacity }
                ButtonRow {
                    width: parent.width
                    height: Theme.controlHeight
                    buttons: (parent.parent.cols >= 3 ? [60, 80, 90].map(p => ({
                        label: p + "%", selected: !ShellState.transparencyOpaque && Math.round(BarSettings.terminalOpacity * 100) === p,
                        action: () => { ShellState.setTerminalOpacity(p / 100); if (ShellState.transparencyOpaque) ShellState.setTransparencyOpaque(false) } }))
                        : [{ label: "Glass", selected: !ShellState.transparencyOpaque, action: () => ShellState.setTransparencyOpaque(false) }])
                        .concat([{ label: "Solid", selected: ShellState.transparencyOpaque, action: () => ShellState.setTransparencyOpaque(true) }])
                }
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
        // Power: profiles (full names at 3+ wide); a 4-wide 2-row tile adds
        // the battery charge limit.
        Component {
            id: extraProfiles
            ButtonRow {
                readonly property bool long: parent.cols >= 3
                buttons: [
                    { profile: UP.PowerProfile.PowerSaver, label: "Saver" },
                    { profile: UP.PowerProfile.Balanced, label: "Balanced" },
                    { profile: UP.PowerProfile.Performance, label: long ? "Performance" : "Perf" }
                ].map(p => ({ label: p.label, selected: UP.PowerProfiles.profile === p.profile,
                              action: () => UP.PowerProfiles.profile = p.profile }))
                    .concat(parent.tall && parent.cols >= 4 && PowerInfo.chargeLimitSupported ? [{
                        label: "Limit " + PowerInfo.chargeLimitEnd + "%", selected: PowerInfo.chargeLimitEnabled,
                        available: !PowerInfo.chargeLimitBusy, action: () => PowerInfo.setChargeLimit(!PowerInfo.chargeLimitEnabled) }] : [])
            }
        }
        Component {
            id: extraLid
            ButtonRow {
                buttons: [
                    { label: "Sleep", selected: LidSettings.sleep, action: () => LidSettings.setSleep(true) },
                    { label: parent.cols >= 3 ? "Keep working" : "Keep on", selected: !LidSettings.sleep, action: () => LidSettings.setSleep(false) }
                ]
            }
        }
        // Wi-Fi body: the connected network, then saved, then the strongest
        // (WifiMenu's order); a tap connects, or opens the Wi-Fi page for a
        // password. Scans while the card is open. 4 wide: a traffic graph
        // beside the list.
        Component {
            id: bodyWifi
            Row {
                id: wifiBody
                spacing: 12
                readonly property bool graph: parent.cols >= 4
                Column {
                    id: wifiList
                    width: wifiBody.graph ? wifiBody.width * 0.6 : wifiBody.width
                    spacing: 2
                    readonly property var networks: {
                        if (!net.wifiDevice || !Networking.wifiEnabled) return []
                        const byName = {}
                        for (const n of net.wifiDevice.networks.values) {
                            if (!n.name) continue
                            const cur = byName[n.name]
                            if (!cur || n.connected || (!cur.connected && n.signalStrength > cur.signalStrength)) byName[n.name] = n
                        }
                        return Object.values(byName).sort((a, b) => {
                            if (a.connected !== b.connected) return a.connected ? -1 : 1
                            if (a.known !== b.known) return a.known ? -1 : 1
                            return b.signalStrength - a.signalStrength
                        }).slice(0, 3)
                    }
                    Binding {
                        target: net.wifiDevice
                        property: "scannerEnabled"
                        value: true
                        when: panel.shown && !!net.wifiDevice
                    }
                    Repeater {
                        model: wifiList.networks
                        delegate: TileListRow {
                            required property var modelData
                            name: modelData.name
                            current: modelData.connected
                            status: modelData.state === ConnectionState.Connecting ? "Connecting…"
                                : modelData.connected && NetInfo.connectivity ? NetInfo.connectivity
                                : (modelData.known && !modelData.connected && wifiBody.parent.cols >= 3 ? "Saved · " : "")
                                  + panel.pct(modelData.signalStrength)
                            onClicked: {
                                const n = modelData
                                if (n.connected) return
                                if (n.known || n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe) n.connect()
                                else root.openPopup("qs-wifi")
                            }
                        }
                    }
                    Text {
                        visible: wifiList.networks.length === 0
                        text: !net.wifiDevice ? (net.wiredUp ? "Ethernet connected" : "No Wi-Fi adapter")
                            : !Networking.wifiEnabled ? "Wi-Fi is off" : "Searching…"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Item {
                    visible: wifiBody.graph
                    width: wifiBody.width - wifiList.width - 12
                    height: wifiBody.height
                    Text {
                        id: trafficText
                        width: parent.width
                        elide: Text.ElideRight
                        text: "↓" + NetInfo.rateText(NetInfo.rxRate) + "  ↑" + NetInfo.rateText(NetInfo.txRate)
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                    MiniGraph {
                        anchors.top: trafficText.bottom
                        anchors.topMargin: 4
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        maxValue: 0
                        history: NetInfo.rxHistory
                    }
                }
            }
        }
        // Wide 1-row Wi-Fi: traffic (3 wide), address and traffic (4).
        Component {
            id: meterNet
            Readout2 {
                line1: parent.cols >= 4 ? (NetInfo.ipv4 || "") : "↓ " + NetInfo.rateText(NetInfo.rxRate)
                line2: parent.cols >= 4 ? "↓" + NetInfo.rateText(NetInfo.rxRate) + "  ↑" + NetInfo.rateText(NetInfo.txRate)
                    : "↑ " + NetInfo.rateText(NetInfo.txRate)
            }
        }
        // Bluetooth body: paired devices, connected first; a tap connects or
        // disconnects (BluetoothIndicator.activate). The whole width, for
        // device names; pairing and Visible are on the page (the chevron).
        Component {
            id: bodyBt
            Column {
                id: btList
                spacing: 2
                readonly property var devices: root.adapter && root.adapter.enabled ? bt.pairedDevices.slice(0, 3) : []
                Repeater {
                    model: btList.devices
                    delegate: TileListRow {
                        required property var modelData
                        name: modelData.name || modelData.deviceName
                        current: modelData.connected
                        status: modelData.state === BluetoothDeviceState.Connecting ? "Connecting…"
                            : modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                            : modelData.connected ? (modelData.batteryAvailable && modelData.battery > 0 ? panel.pct(modelData.battery) : "\u{f0337}")
                            : "Connect"
                        statusGlyph: status === "\u{f0337}"
                        onClicked: bt.activate(modelData)
                    }
                }
                // Off / no adapter: the header's status line already says so.
                Text {
                    visible: btList.devices.length === 0 && !!(root.adapter && root.adapter.enabled)
                    text: "No paired devices"
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
        Component {
            id: meterBt
            TileReadout {
                text: bt.connectedDevices.filter(d => d.batteryAvailable && d.battery > 0)
                    .map(d => (parent.cols >= 4 ? (d.name || d.deviceName) + " " : "") + panel.pct(d.battery)).join("  ·  ")
            }
        }
        // Phone: mirror and files, then -- with room -- what fits the state:
        // Unlock while locked, Audio while mirroring, else Display.
        Component {
            id: extraPhoneButtons
            ButtonRow {
                readonly property var d: Sichlink.phone
                readonly property bool online: !!(d && d.connected)
                readonly property var extras: [
                    online && d.locked ? { label: "Unlock", action: () => Sichlink.wake(d.id) } : null,
                    PhoneMirrorState.open ? { label: "Audio", selected: PhoneMirrorState.audio, action: () => PhoneMirrorState.setAudio(!PhoneMirrorState.audio) }
                        : { label: Sichlink.displayStarting ? "Starting…" : "Display", selected: Sichlink.displayOn, available: online,
                            action: () => Sichlink.setDisplay(!Sichlink.displayOn) },
                    PhoneMirrorState.open ? { label: "Stop", action: () => PhoneMirrorState.close() } : null
                ].filter(b => b)
                buttons: [
                    { label: PhoneMirrorState.toggleLabel, selected: PhoneMirrorState.open && !PhoneMirrorState.collapsed,
                      available: PhoneMirrorState.open || online, action: () => PhoneMirrorState.toggle(root.screenName) },
                    { label: Sichlink.driveBusy ? "Mounting…" : "Files", selected: Sichlink.driveMounted,
                      available: !Sichlink.driveBusy && (Sichlink.driveMounted || online),
                      action: () => { if (!Sichlink.driveMounted) { Sichlink.setDrive(true); return } ShellState.activePopup = ""; Sichlink.openDrive() } }
                ].concat(extras.slice(0, Math.max(0, parent.cols - 2)))
            }
        }
        // Silence for a while (NotificationMutePopup's choices); while on,
        // extend it instead.
        function nextMorning() {
            const d = new Date()
            if (d.getHours() >= 8) d.setDate(d.getDate() + 1)
            d.setHours(8, 0, 0, 0)
            return d.getTime()
        }
        function extendMute(minutes) {
            const from = Math.max(Date.now(), ShellState.notificationsMutedUntil)
            ShellState.muteNotificationsUntil(from + minutes * 60000)
        }
        Component {
            id: extraSilence
            ButtonRow {
                readonly property bool on: ShellState.notificationsMuted
                readonly property bool timed: on && ShellState.notificationsMutedUntil > 0
                buttons: (parent.cols >= 4 ? [30, 60, 120] : parent.cols === 3 ? [60, 120] : [60]).map(m => ({
                    label: (timed ? "+" : "") + (m < 60 ? m + " min" : m === 60 ? "1 hour" : m / 60 + " hours"),
                    action: () => timed ? panel.extendMute(m) : ShellState.setNotificationsMuted(true, m) }))
                    .concat([{ label: "Until 08:00", selected: timed && ShellState.notificationsMutedUntil === panel.nextMorning(),
                               action: () => ShellState.muteNotificationsUntil(panel.nextMorning()) }])
            }
        }
        // 2-row Silence, 3+ wide: what came in (missed while silenced,
        // else the latest), then the presets.
        Component {
            id: bodySilence
            Column {
                spacing: 6
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: NotificationHistory.recent(2)
                        delegate: TileListRow {
                            required property var modelData
                            name: modelData.appName + (modelData.summary ? ": " + modelData.summary : "")
                            status: panel.clock(modelData.time)
                            onClicked: ShellState.notificationCenterScreen = root.screenName
                        }
                    }
                    Text {
                        visible: NotificationHistory.recent(1).length === 0
                        leftPadding: 4
                        text: "No notifications"
                        color: Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Loader {
                    width: parent.width
                    height: Theme.controlHeight
                    sourceComponent: extraSilence
                    property int cols: parent.parent.cols
                    property bool tall: true
                }
            }
        }
        // Airplane: the two radios it switches, one at a time.
        Component {
            id: extraRadios
            ButtonRow {
                buttons: [
                    { label: "Wi-Fi", selected: Networking.wifiEnabled, available: !!net.wifiDevice,
                      action: () => Networking.wifiEnabled = !Networking.wifiEnabled },
                    { label: "Bluetooth", selected: !!(root.adapter && root.adapter.enabled), available: !!root.adapter,
                      action: () => ShellState.setBluetooth(!root.adapter.enabled) }
                ]
            }
        }
        // HDR: which monitors it applies to (HdrSettings); ones that can't
        // do HDR are dimmed but can still be unticked.
        Component {
            id: extraHdrMonitors
            ButtonRow {
                buttons: Displays.monitors.filter(m => !m.disabled).map(m => ({
                    label: parent.cols >= 3 ? m.friendly : m.name, selected: HdrSettings.isSelected(m.name),
                    available: m.hdrCapable !== false || HdrSettings.isSelected(m.name),
                    action: () => HdrSettings.toggleMonitor(m.name) }))
            }
        }
        // Version, 2 rows: what each part of "which version" says, as
        // label/value rows (two columns at 4 wide), most telling first.
        Component {
            id: bodyVersion
            Grid {
                id: verGrid
                readonly property var sv: SichosVersion
                readonly property var i: sv.info
                // The Loader's: `parent` inside the Repeater below is this Grid
                readonly property int cols: parent.cols
                width: parent.width
                columns: cols >= 4 ? 2 : 1
                columnSpacing: 14
                rowSpacing: 3
                clip: true
                Repeater {
                    model: !verGrid.i ? [] : [
                        ["Commit", verGrid.i.deployed_subject],
                        ["Deployed", [verGrid.sv.ago(verGrid.i.deployed_at),
                            verGrid.sv.pinned ? "pinned to " + verGrid.i.pinned
                            : verGrid.sv.offHead ? "HEAD is " + verGrid.i.head : ""].filter(t => t).join(" · ")],
                        ["Origin", !verGrid.i.upstream ? "no upstream"
                            : [verGrid.sv.behindOrigin > 0 ? verGrid.sv.behindOrigin + " to pull" : "",
                               verGrid.sv.aheadOrigin > 0 ? verGrid.sv.aheadOrigin + " to push" : "",
                               verGrid.sv.behindOrigin + verGrid.sv.aheadOrigin === 0 ? "up to date" : ""]
                                .filter(t => t).join(" · ") + (verGrid.cols >= 3 ? " · " + verGrid.i.upstream : "")],
                        ["Local", [verGrid.sv.conflicts > 0 ? verGrid.sv.conflicts + " parked" : "",
                            verGrid.sv.systemPending > 0 ? verGrid.sv.systemPending + " system to apply" : "",
                            verGrid.sv.dirty > 0 ? verGrid.sv.dirty + " uncommitted" : "",
                            !verGrid.sv.hooks ? "auto-update off" : ""].filter(t => t).join(" · ") || "in step, auto-update on"],
                        ["Branch", verGrid.i.branch || "detached"],
                        ["Host", verGrid.i.host]
                    ].slice(0, verGrid.cols >= 4 ? 6 : verGrid.cols >= 3 ? 4 : 3)
                    delegate: Row {
                        required property var modelData
                        spacing: 6
                        width: (verGrid.width - (verGrid.columns - 1) * verGrid.columnSpacing) / verGrid.columns
                        Text {
                            id: verKey
                            width: 54
                            text: modelData[0]
                            color: Theme.textMuted
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Text {
                            width: parent.width - verKey.width - parent.spacing
                            elide: Text.ElideRight
                            text: modelData[1]
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }
        Component {
            id: bodyHdr
            Column {
                spacing: 2
                Repeater {
                    model: Displays.monitors.filter(m => !m.disabled).slice(0, 3)
                    delegate: TileListRow {
                        required property var modelData
                        name: modelData.friendly + "  " + modelData.name
                        current: HdrSettings.isSelected(modelData.name)
                        status: modelData.hdrCapable === false ? "No HDR"
                            : modelData.hdrApplied ? "HDR · 10-bit"
                            : HdrSettings.isSelected(modelData.name) ? (HdrSettings.active ? "SDR (didn't apply)" : "Selected") : "Tap to use"
                        opacity: modelData.hdrCapable === false && !current ? 0.5 : 1
                        onClicked: HdrSettings.toggleMonitor(modelData.name)
                    }
                }
            }
        }
        // Stay Awake: for a while, then lock/sleep now with room.
        Component {
            id: extraAwake
            ButtonRow {
                readonly property bool timed: ShellState.idleActive && ShellState.idleActiveUntil > 0
                buttons: (parent.cols >= 3 ? [60, 240] : [60]).map(m => ({
                    label: parent.cols >= 4 && !parent.tall ? m / 60 + " h" : m / 60 + (m === 60 ? " hour" : " hours"),
                    action: () => ShellState.setIdleActive(true, m) }))
                    .concat([{ label: parent.cols >= 4 && !parent.tall ? "Lock" : "Lock now",
                               action: () => { ShellState.activePopup = ""; Quickshell.execDetached(["hyprlock"]) } }])
                    .concat(parent.tall && parent.cols >= 4 ? [{ label: "Sleep",
                               action: () => { ShellState.activePopup = ""; Quickshell.execDetached(["systemctl", "suspend"]) } }] : [])
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
                            readonly property var cell: ControlCenterTiles.layout.pos[tile.tileId] || { r: 0, c: 0, w: 1, h: 1 }
                            // What this tile shows at its size (panel.tileView).
                            readonly property var info: panel.tileView(tile.tileId, tile.cell.w, tile.cell.h)
                            readonly property bool small: tile.cell.w === 1
                            readonly property bool tall: tile.cell.h === 2
                            readonly property Component control: tile.info.control
                            readonly property Component body: tile.tall ? tile.info.body : null
                            // 1 row: the control under a title line (with
                            // `tag` on its right), or beside the header.
                            readonly property bool inlineNarrow: !tile.tall && !!tile.control && tile.info.under
                            readonly property bool inlineWide: !tile.tall && !!tile.control && !tile.info.under
                            readonly property bool partsShown: tile.tall ? !!(tile.body || tile.control) : !!tile.control
                            readonly property string subText: tile.info.sub
                            readonly property string detail: tile.tall ? tile.info.detail : ""
                            // Chevron strip: tiles whose tap doesn't already open their page.
                            readonly property bool hasMore: !tile.small && tile.info.more !== "" && !tile.info.opens
                            // Where the inline control starts: the same column
                            // in every tile of a width, past the longest label
                            // that gets one there ("When lid closes" at 4 wide,
                            // "Night Light" at 3 -- underAt3 go under).
                            // A narrow readout (`besideWidth`) sits at the right instead.
                            readonly property real inlineX: tile.info.besideWidth
                                ? tile.width - (tile.hasMore ? 38 : 14) - tile.info.besideWidth
                                : 52 + (tile.cell.w >= 4 ? 112 : 90)
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
                                    onWheel: (wheel) => panel.tileWheel(tile.tileId, wheel)
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
                                    // down to center the pair. 2 rows with
                                    // nothing under it: centered, as is the
                                    // 1-wide icon/label/status stack; with
                                    // something, a shorter header.
                                    y: tile.inlineNarrow ? 3
                                        : tile.small && tile.tall ? Math.max(0, (tile.height - 74 - smallSub.height) / 2)
                                        : tile.tall && !tile.partsShown && tile.detail === "" ? (tile.height - panel.tileHeight) / 2 : 0
                                    width: parent.width
                                    height: tile.inlineNarrow ? 30 : tile.tall && !tile.small && (tile.partsShown || tile.detail !== "") ? 54 : panel.tileHeight

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
                                        // 1x2: the lines below carry the specifics.
                                        text: tile.tall ? tile.info.label : (tile.info.short || tile.info.label)
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
                                        // chevron strip (or edit mode's badge).
                                        width: (tile.inlineWide ? inlineExtra.x - 10
                                            : (moreStrip.visible ? moreStrip.x : head.width - (panel.editing ? 26 : 0)) - 6) - 52
                                            - (tagText.visible ? tagText.width + 8 : 0)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        // titleTail: a short muted note after
                                        // the title (Wi-Fi's band); the title
                                        // elides first.
                                        Row {
                                            width: parent.width
                                            spacing: 6
                                            Text {
                                                id: titleText
                                                width: Math.min(implicitWidth, parent.width - (titleTailText.visible ? titleTailText.implicitWidth + parent.spacing : 0))
                                                text: tile.info.title
                                                elide: Text.ElideRight
                                                color: Theme.text
                                                font.family: Theme.uiFontFamily
                                                font.pixelSize: Theme.fontSize
                                                font.bold: true
                                            }
                                            Text {
                                                id: titleTailText
                                                visible: text !== ""
                                                // Centred, not on the baseline: the
                                                // smaller text sat low beside the title.
                                                anchors.verticalCenter: titleText.verticalCenter
                                                text: tile.info.titleTail || ""
                                                color: Theme.textMuted
                                                font.family: Theme.uiFontFamily
                                                font.pixelSize: Theme.fontSize - 2
                                            }
                                        }
                                        Text {
                                            visible: !tile.inlineNarrow && tile.subText !== ""
                                            width: parent.width
                                            text: tile.subText
                                            elide: Text.ElideRight
                                            color: Theme.textMuted
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                    }
                                    // A short status on the title line when the
                                    // control took the status line's place.
                                    // The title keeps its room; the tag shows
                                    // only if it fits whole.
                                    Text {
                                        id: tagText
                                        readonly property real room: (moreStrip.visible ? moreStrip.x - 4 : head.width - (panel.editing ? 30 : 14))
                                            - 52 - titleText.implicitWidth - 10
                                        visible: tile.inlineNarrow && tile.info.tag !== "" && room >= implicitWidth
                                        anchors.right: moreStrip.visible ? moreStrip.left : parent.right
                                        anchors.rightMargin: moreStrip.visible ? 4 : (panel.editing ? 30 : 14)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, room)
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                        text: tile.info.tag
                                        color: Theme.textMuted
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                    // Kept (empty) in edit mode, so the label
                                    // and controls don't shift under the badge.
                                    Rectangle {
                                        id: moreStrip
                                        visible: tile.hasMore
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 1
                                        width: 30
                                        radius: Theme.controlRadius
                                        color: moreArea.containsMouse ? Theme.hoverFill : "transparent"
                                        Text {
                                            visible: !panel.editing
                                            anchors.centerIn: parent
                                            text: "" // nf-fa-chevron_right
                                            color: moreArea.containsMouse ? Theme.text : Theme.textMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                        }
                                        MouseArea {
                                            id: moreArea
                                            enabled: !panel.editing
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openPopup(tile.info.more)
                                        }
                                    }
                                }

                                // 1 column x 2 rows: status under the label,
                                // a line per " · " part.
                                Text {
                                    id: smallSub
                                    visible: tile.small && tile.tall
                                    anchors.top: head.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    anchors.topMargin: -4
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    text: tile.info.lines.join("\n")
                                    color: Theme.textMuted
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }

                                // 1 row, 2+ columns: the control under (2
                                // wide) or beside (3+ wide) the label, or the
                                // meter beside it.
                                Loader {
                                    id: inlineExtra
                                    active: tile.inlineNarrow || tile.inlineWide
                                    sourceComponent: tile.control
                                    // Read by the components, which adapt to the tile.
                                    property int cols: tile.cell.w
                                    property bool tall: false
                                    enabled: !panel.editing
                                    x: tile.inlineWide ? tile.inlineX : 14
                                    // Clear of edit mode's resize grip.
                                    width: (tile.inlineWide && moreStrip.visible ? moreStrip.x - 8 : parent.width - (panel.editing ? 24 : 14)) - x
                                    y: tile.inlineWide ? (parent.height - height) / 2 : head.y + head.height
                                    height: tile.inlineWide ? 28 : 24
                                }

                                // 2+ columns x 2 rows: the body, or the
                                // detail line over the control, centered
                                // under the header.
                                Item {
                                    visible: tile.tall && !tile.small
                                    anchors.top: head.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 14
                                    // Clear of edit mode's resize grip.
                                    anchors.rightMargin: panel.editing ? 24 : 14
                                    anchors.bottomMargin: 10
                                    enabled: !panel.editing
                                    Loader {
                                        active: !!tile.body
                                        anchors.fill: parent
                                        sourceComponent: tile.body
                                        property int cols: tile.cell.w
                                        property bool tall: true
                                    }
                                    Column {
                                        visible: !tile.body
                                        width: parent.width
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        Text {
                                            visible: tile.detail !== ""
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: tile.detail
                                            color: Theme.textMuted
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                        // A slider alone gets its label/value row.
                                        Loader {
                                            active: !tile.body && !!tile.control
                                            visible: active
                                            width: parent.width
                                            height: tile.detail !== "" ? Theme.controlHeight : 40
                                            sourceComponent: tile.control
                                            property int cols: tile.cell.w
                                            property bool tall: true
                                        }
                                    }
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
                                // Tucked into the corner, under the baseline of
                                // a 1-wide tile's label.
                                Rectangle {
                                    visible: panel.editing
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 3
                                    width: 8
                                    height: 8
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

                            // Title / artist / app. The title gets the full width;
                            // the buttons only sit beside the two smaller lines.
                            Column {
                                anchors.left: art.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    width: parent.width
                                    rightPadding: 4
                                    text: mediaCard.player ? (mediaCard.player.trackTitle || mediaCard.player.identity || "") : ""
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                }
                                Item {
                                    width: parent.width
                                    // Keeps room for the buttons when the player gives neither line.
                                    height: Math.max(lowerLines.height, 24)

                                    Column {
                                        id: lowerLines
                                        anchors.left: parent.left
                                        anchors.right: mediaButtons.left
                                        anchors.rightMargin: 8
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            visible: text !== ""
                                            text: mediaCard.player ? (mediaCard.player.trackArtist || "") : ""
                                            elide: Text.ElideRight
                                            color: Theme.textMuted
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                        Text {
                                            width: parent.width
                                            visible: text !== ""
                                            text: mediaCard.player ? (mediaCard.player.identity || "") : ""
                                            elide: Text.ElideRight
                                            color: Theme.textDim
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                        }
                                    }

                                    Row {
                                        id: mediaButtons
                                        anchors.right: parent.right
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
        onScheduleSaved: ShellState.restartSunsetSchedule()
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

    // --- Proton VPN page ---
    readonly property Item _vpnContent: VpnPage {
        parent: root.popupHost
        anchorItem: root
        shown: ShellState.activePopup === "qs-vpn" && ShellState.activePopupScreen === root.screenName
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
        // y, not anchors switched by `compact`: the Loader starts at height
        // 0 (compact), and dropping verticalCenter for bottom on the way to
        // a 2-row tile left the value under the track, outside the tile.
        Text {
            id: tsPct
            anchors.right: parent.right
            y: ts.compact ? tsTrack.y + (tsTrack.height - height) / 2 : tsTrack.y - height - 6
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
    // A list row of the Wi-Fi/Bluetooth bodies: name, status on the
    // right, the whole row a button.
    component TileListRow: Rectangle {
        id: lr
        property string name: ""
        property string status: ""
        // `status` is a Nerd Font glyph (Inter has none of them).
        property bool statusGlyph: false
        property bool current: false
        signal clicked()
        width: parent ? parent.width : 0
        height: 20
        radius: 4
        color: lrArea.containsMouse ? Theme.hoverFill : "transparent"
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: lrStatus.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: lr.name
            color: lr.current ? Theme.text : Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: lr.current
        }
        Text {
            id: lrStatus
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: lr.status
            color: lr.current ? Theme.success : Theme.textDim
            font.family: lr.statusGlyph ? Theme.fontFamily : Theme.uiFontFamily
            font.pixelSize: lr.statusGlyph ? Math.round(Theme.fontSize * 1.25) : Theme.fontSize - 3
        }
        MouseArea {
            id: lrArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lr.clicked()
        }
    }
    // Wide 1-row readouts.
    component TileReadout: Text {
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideLeft
        color: Theme.textMuted
        font.family: Theme.uiFontFamily
        font.pixelSize: Theme.fontSize - 2
    }
    // Buttons laid out in a row, widths by label length so a long one
    // ("Balanced", "Until 08:00") doesn't elide next to short ones.
    component ButtonRow: Row {
        id: br
        // [{label, selected, available, action}]
        property var buttons: []
        spacing: 4
        FontMetrics { id: brMetrics; font.family: Theme.uiFontFamily; font.pixelSize: Theme.fontSize - 2 }
        readonly property var weights: br.buttons.map(b => brMetrics.advanceWidth(b.label) + 18)
        readonly property real total: br.weights.reduce((a, b) => a + b, 0)
        Repeater {
            model: br.buttons
            delegate: TileButton {
                required property var modelData
                required property int index
                width: (br.width - br.spacing * (br.buttons.length - 1)) * br.weights[index] / br.total
                label: modelData.label
                selected: !!modelData.selected
                available: modelData.available !== false
                onClicked: modelData.action()
            }
        }
    }
    // Small two-line readout, right-aligned (1-row wide tiles).
    component Readout2: Column {
        property string line1: ""
        property string line2: ""
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        spacing: 1
        TileReadout { width: parent.width; text: parent.line1 }
        TileReadout { width: parent.width; text: parent.line2; visible: text !== ""; color: Theme.textDim }
    }
    // History graph like the System tile's: area + line.
    component MiniGraph: Canvas {
        id: mg
        property var history: []
        property real maxValue: 1   // 0 = auto (largest sample)
        property color tint: Theme.accent
        onHistoryChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const h = mg.history
            if (!h || h.length < 2) return
            const top = mg.maxValue > 0 ? mg.maxValue : Math.max(1, ...h)
            const step = width / (SystemStats.historyLength - 1)
            const x0 = width - (h.length - 1) * step
            const y = v => height - Math.min(1, v / top) * height
            ctx.beginPath()
            ctx.moveTo(x0, height)
            for (let i = 0; i < h.length; i++) ctx.lineTo(x0 + i * step, y(h[i]))
            ctx.lineTo(x0 + (h.length - 1) * step, height)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(mg.tint.r, mg.tint.g, mg.tint.b, 0.3)
            ctx.fill()
            ctx.beginPath()
            for (let i = 0; i < h.length; i++) {
                if (i === 0) ctx.moveTo(x0, y(h[0]))
                else ctx.lineTo(x0 + i * step, y(h[i]))
            }
            ctx.strokeStyle = mg.tint
            ctx.lineWidth = 1.5
            ctx.stroke()
        }
    }

    component TileButton: Rectangle {
        id: tb
        property string label: ""
        property bool selected: false
        // Dimmed and inert when false (phone offline, no adapter). Not
        // `enabled`: that's inherited, and edit mode disables every tile.
        property bool available: true
        signal clicked()
        anchors.bottom: parent ? parent.bottom : undefined
        height: Math.min(Theme.controlHeight, parent ? parent.height : Theme.controlHeight)
        radius: Theme.controlRadius
        opacity: tb.available ? 1 : 0.4
        color: tb.selected ? Theme.accent : tbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
        // Not bold when selected: the fill already says so, and bold
        // "Balanced" overflowed a third of a 2-wide tile.
        Text {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, tb.width - 8)
            elide: Text.ElideRight
            text: tb.label
            color: tb.selected ? Theme.textOnLight : Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        MouseArea {
            id: tbArea
            enabled: tb.available
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }
}
