import QtQuick
import Quickshell

// Proton VPN page of the Control Center (QuickSettings.qml, popupId
// "qs-vpn"; the VPN tile's chevron opens it). Everything goes through
// VpnStatus, i.e. Proton's own CLI inside the Flatpak: the header switch
// (reconnect to the last server -- the fastest if there's none -- /
// disconnect), a status card, one-tap profiles (Fastest, Random, Secure
// Core, P2P, Tor), favorites (the star on any country or server row, or
// the status card's), recent servers, the country list (collapsed until
// opened or searched) -- tap a country for its fastest server, expand it
// for its cities, Secure Core and individual servers (fastest first, more
// on demand) -- with a search field, and the app's settings that the CLI
// can change. The server list is Proton's own cache, summarised by
// scripts/vpn-servers.py (it's 26 MB); loads are as of its last refresh.
//
// The search field isn't a TextInput: a popup surface never gets keyboard
// focus, so while it's open this page is ShellState.keySink (see WifiMenu).
MorphContent {
    id: page
    property real contentWidth: 360
    property string screenName: ""
    signal back()

    implicitWidth: page.contentWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    // Expanded country, how many of its servers are listed, and a city
    // filter for them.
    property string expanded: ""
    property int serverLimit: 15
    property string cityFilter: ""
    property bool settingsOpen: false
    // Country list: collapsed by default (favorites/recent cover the usual
    // picks); a search shows it regardless.
    property bool countriesOpen: false
    readonly property bool countriesShown: page.countriesOpen || page.query.trim() !== ""
    // One of the two at a time, or the card outgrows the screen.
    onCountriesShownChanged: if (page.countriesShown) page.settingsOpen = false
    function openSettings() {
        page.countriesOpen = false
        page.query = ""
        page.searching = false
        page.settingsOpen = true
    }

    property bool searching: false
    property string query: ""

    onShownChanged: {
        if (page.shown) VpnStatus.loadCountries()
        else { page.searching = false; page.query = ""; page.expanded = "" }
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) { page.searching = false; page.query = "" }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (page.serverQuery) VpnStatus.connect({ server: page.serverQuery })
            else if (page.filtered.length === 1) page.toggleExpand(page.filtered[0].c)
        }
        else if (event.key === Qt.Key_Backspace) page.query = page.query.slice(0, -1)
        else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && page.query.length < 40) page.query += event.text
    }
    readonly property bool wantsKeys: page.shown && page.searching
    onWantsKeysChanged: {
        if (page.wantsKeys) {
            ShellState.keySinkScreen = page.screenName
            ShellState.keySink = page
        } else if (ShellState.keySink === page) {
            ShellState.keySink = null
        }
    }

    // A typed server name ("de#12", "is-de#1") gets its own connect row.
    readonly property string serverQuery: /^[a-z]{2}(-[a-z]{2})?#\d+$/i.test(page.query.trim()) ? page.query.trim().toUpperCase() : ""
    readonly property var filtered: {
        const q = page.query.trim().toLowerCase()
        if (q === "" || page.serverQuery) return VpnStatus.countries
        return VpnStatus.countries.filter(c => c.n.toLowerCase().includes(q) || c.c.toLowerCase() === q
            || c.cities.some(ct => ct[0].toLowerCase().includes(q)))
    }

    function toggleExpand(code) {
        page.cityFilter = ""
        page.serverLimit = 15
        page.expanded = page.expanded === code ? "" : code
        if (page.expanded) VpnStatus.loadServers(code)
    }
    function loadColor(l) { return l >= 90 ? Theme.danger : l >= 75 ? Theme.textMuted : Theme.success }
    // Proton feature bits: 1 Secure Core, 2 Tor, 4 P2P, 8 Streaming.
    function featureText(f) {
        return [f & 4 ? "P2P" : "", f & 2 ? "Tor" : "", f & 8 ? "Streaming" : ""].filter(t => t).join(" · ")
    }
    readonly property string lastCity: {
        const r = (VpnStatus.recent || []).find(x => x.name === VpnStatus.lastServer)
        return r ? r.city || "" : ""
    }
    readonly property string statusTitle: VpnStatus.connected ? VpnStatus.server
        : VpnStatus.connecting ? "Connecting…" : "Not connected"
    readonly property string statusLine: {
        if (VpnStatus.pending === "connect")
            return (VpnStatus.connected ? "Switching to " : "To ") + VpnStatus.pendingLabel
        if (VpnStatus.pending === "disconnect") return "Disconnecting…"
        if (!VpnStatus.connected) return VpnStatus.lastServer ? "Last: " + VpnStatus.lastServer + (page.lastCity ? " · " + page.lastCity : "")
            : VpnStatus.killSwitch ? "Kill switch is on" : "Your traffic isn't protected"
        return [VpnStatus.city, VpnStatus.secureCore ? "Secure Core" : "", VpnStatus.protocol,
            VpnStatus.load >= 0 ? "load " + VpnStatus.load + "%" : ""].filter(t => t).join(" · ")
    }

    Column {
        id: column
        anchors.centerIn: parent
        width: page.contentWidth
        spacing: Theme.sectionSpacing

        // Header: back, title, on/off.
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
                    text: "Proton VPN"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
            }
            Switch {
                anchors.right: parent.right
                checked: VpnStatus.connected || VpnStatus.connecting
                onToggled: VpnStatus.toggle()
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        // Status card.
        Rectangle {
            width: parent.width
            height: statusCol.implicitHeight + 20
            radius: Theme.controlRadius
            color: VpnStatus.connected ? Theme.selectedFill : Theme.surfaceRaised
            Text {
                id: bigFlag
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: VpnStatus.connected && VpnStatus.countryFlag ? VpnStatus.countryFlag : "\u{f0565}"
                color: VpnStatus.connected ? Theme.text : Theme.textMuted
                font.family: VpnStatus.connected && VpnStatus.countryFlag ? Theme.uiFontFamily : Theme.fontFamily
                font.pixelSize: Theme.fontSize + 13
            }
            Column {
                id: statusCol
                anchors.left: bigFlag.right
                anchors.leftMargin: 12
                anchors.right: currentStar.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: page.statusTitle
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: page.statusLine
                    elide: Text.ElideRight
                    color: VpnStatus.connected ? Theme.text : Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    visible: VpnStatus.connected && VpnStatus.connectedSince > 0
                    width: parent.width
                    text: "Connected " + SystemStats.durationText((uptimeTick.now - VpnStatus.connectedSince) / 1000)
                        + (VpnStatus.device ? " · " + VpnStatus.device : "")
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                    Timer {
                        id: uptimeTick
                        property real now: Date.now()
                        interval: 1000
                        repeat: true
                        running: page.shown && VpnStatus.connected
                        onTriggered: now = Date.now()
                    }
                }
                Text {
                    visible: VpnStatus.error !== ""
                    width: parent.width
                    text: VpnStatus.error
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Theme.danger
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            // Star the server you're on.
            StarButton {
                id: currentStar
                anchors.right: statusButton.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: VpnStatus.connected ? 30 : 0
                shown: VpnStatus.connected
                starred: VpnStatus.isFavorite("server", VpnStatus.server)
                onClicked: VpnStatus.toggleFavorite({ kind: "server", id: VpnStatus.server, label: VpnStatus.server,
                    country: VpnStatus.country, city: VpnStatus.city })
            }
            PageButton {
                id: statusButton
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                large: true
                accent: !VpnStatus.connected && !VpnStatus.connecting
                label: VpnStatus.connected || VpnStatus.connecting ? (VpnStatus.pending === "connect" ? "Cancel" : "Disconnect")
                    : VpnStatus.lastServer ? "Reconnect" : "Quick connect"
                onClicked: VpnStatus.toggle()
            }
        }

        // One-tap profiles: the CLI's own selectors.
        Column {
            width: parent.width
            spacing: 4
            SectionLabel { text: "Connect to" }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        { label: "Fastest", opts: { label: "Fastest" } },
                        { label: "Random", opts: { random: true, label: "a random server" } },
                        { label: "Secure Core", opts: { secureCore: true, label: "Secure Core" } },
                        { label: "P2P", opts: { p2p: true, label: "the fastest P2P server" } },
                        { label: "Tor", opts: { tor: true, label: "the fastest Tor server" } }
                    ]
                    PageButton {
                        required property var modelData
                        label: modelData.label
                        onClicked: VpnStatus.connect(modelData.opts)
                    }
                }
            }
        }

        // Starred countries and servers; the star removes them again.
        Column {
            visible: VpnStatus.favorites.length > 0
            width: parent.width
            spacing: 2
            SectionLabel { text: "Favorites" }
            Repeater {
                model: VpnStatus.favorites
                ListRow {
                    required property var modelData
                    flag: VpnStatus.flagFor(modelData.country)
                    title: modelData.label
                    subtitle: modelData.kind === "country" ? "Fastest server" : modelData.city || ""
                    selected: VpnStatus.connected && (modelData.kind === "server" ? VpnStatus.server === modelData.id
                        : VpnStatus.country === modelData.id || (VpnStatus.country === "GB" && modelData.id === "UK"))
                    canFavorite: true
                    favorite: true
                    onClicked: VpnStatus.connectFavorite(modelData)
                    onFavoriteClicked: VpnStatus.toggleFavorite(modelData)
                }
            }
        }

        // Recent servers (not the current one).
        Column {
            readonly property var items: (VpnStatus.recent || []).filter(r => r.name !== VpnStatus.server).slice(0, 3)
            visible: items.length > 0
            width: parent.width
            spacing: 2
            SectionLabel { text: "Recent" }
            Repeater {
                model: parent.items
                ListRow {
                    required property var modelData
                    flag: VpnStatus.flagFor(modelData.country)
                    title: modelData.name
                    subtitle: modelData.city || ""
                    canFavorite: true
                    favorite: VpnStatus.isFavorite("server", modelData.name)
                    onClicked: VpnStatus.connect({ server: modelData.name })
                    onFavoriteClicked: VpnStatus.toggleFavorite({ kind: "server", id: modelData.name, label: modelData.name,
                        country: modelData.country, city: modelData.city || "" })
                }
            }
        }

        // Countries, with search. No spacing: the gap above the list is the
        // Collapsible's topPadding, so it animates with it.
        Column {
            width: parent.width
            Item {
                width: parent.width
                height: Theme.controlHeight + 4
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: searchBox.left
                    anchors.rightMargin: 8
                    height: parent.height
                    radius: Theme.controlRadius
                    color: countriesArea.containsMouse ? Theme.hoverFill : "transparent"
                    SectionLabel {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        bottomPadding: 0
                        text: VpnStatus.loadingCountries && VpnStatus.countries.length === 0 ? "Countries · loading…"
                            : "Countries · " + VpnStatus.countries.length
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0140}" // nf-md-chevron_down, turned up while open
                        rotation: page.countriesShown ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic } }
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    MouseArea {
                        id: countriesArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Closing also drops a search, which would keep it open.
                            if (page.countriesShown) { page.countriesOpen = false; page.query = ""; page.searching = false }
                            else page.countriesOpen = true
                        }
                    }
                }
                Rectangle {
                    id: searchBox
                    anchors.right: parent.right
                    width: 170
                    height: parent.height
                    radius: Theme.controlRadius
                    color: Theme.controlFill
                    border.width: page.searching ? 1 : 0
                    border.color: Theme.accent
                    Text {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0349}" // nf-md-magnify
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        id: queryText
                        anchors.left: searchIcon.right
                        anchors.leftMargin: 6
                        // Room for the clear button; not anchored to it, so
                        // its width doesn't feed back into this.
                        anchors.right: parent.right
                        anchors.rightMargin: page.query !== "" || page.searching ? 26 : 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.query !== "" ? page.query : page.searching ? "" : "Country, city, DE#12"
                        color: page.query !== "" ? Theme.text : Theme.textDim
                        elide: Text.ElideLeft
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    // Caret, since there's no real TextInput.
                    Rectangle {
                        visible: page.searching
                        x: queryText.x + Math.min(queryText.contentWidth, queryText.width) * (page.query !== "" ? 1 : 0) + 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Theme.fontSize
                        color: Theme.text
                        SequentialAnimation on opacity {
                            running: page.searching
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: page.searching = true
                    }
                    Text {
                        id: clearSearch
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.query !== "" || page.searching
                        text: "\u{f0156}" // nf-md-close
                        color: clearArea.containsMouse ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { page.query = ""; page.searching = false }
                        }
                    }
                }
            }

            Collapsible {
                open: page.countriesShown
                width: parent.width
                topPadding: 6
                spacing: 6

                ListRow {
                    visible: page.serverQuery !== ""
                    flag: VpnStatus.flagFor(page.serverQuery.replace(/^[A-Z]{2}-/, "").slice(0, 2))
                    title: "Connect to " + page.serverQuery
                    subtitle: "Server by name"
                    onClicked: VpnStatus.connect({ server: page.serverQuery })
                }

                Flickable {
                    id: list
                    width: parent.width
                    height: Math.min(listColumn.implicitHeight, 300)
                    contentHeight: listColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: listColumn
                        width: list.width
                        spacing: 2

                        Text {
                            visible: !VpnStatus.loadingCountries && page.filtered.length === 0
                            text: VpnStatus.countries.length === 0 ? "No server list yet -- open the Proton VPN app once" : "No matches"
                            color: Theme.textDim
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        Repeater {
                            model: page.filtered
                            delegate: Column {
                                id: country
                                required property var modelData
                                readonly property bool open: page.expanded === country.modelData.c
                                readonly property bool current: VpnStatus.connected
                                    && (VpnStatus.country === country.modelData.c || (VpnStatus.country === "GB" && country.modelData.c === "UK"))
                                width: listColumn.width

                                ListRow {
                                    flag: VpnStatus.flagFor(country.modelData.c)
                                    title: country.modelData.n
                                    subtitle: country.modelData.s + (country.modelData.s === 1 ? " server" : " servers")
                                        + (country.modelData.l >= 0 ? " · " + country.modelData.l + "% load" : "")
                                        + (page.featureText(country.modelData.f) ? " · " + page.featureText(country.modelData.f) : "")
                                    selected: country.current
                                    canFavorite: true
                                    favorite: VpnStatus.isFavorite("country", country.modelData.c)
                                    onFavoriteClicked: VpnStatus.toggleFavorite({ kind: "country", id: country.modelData.c,
                                        label: country.modelData.n, country: country.modelData.c })
                                    expandable: true
                                    expanded: country.open
                                    onClicked: VpnStatus.connect({ country: country.modelData.c, label: country.modelData.n })
                                    onExpandClicked: page.toggleExpand(country.modelData.c)
                                }

                                // Expanded: cities / Secure Core, then servers.
                                Collapsible {
                                    open: country.open
                                    width: parent.width
                                    topPadding: 4
                                    leftPadding: 12
                                    spacing: 4
                                    Flow {
                                        width: parent.width - 12
                                        spacing: 6
                                        PageButton {
                                            visible: country.modelData.cities.length > 1
                                            label: "All cities"
                                            accent: page.cityFilter === ""
                                            onClicked: page.cityFilter = ""
                                        }
                                        Repeater {
                                            model: country.open && country.modelData.cities.length > 1 ? country.modelData.cities : []
                                            PageButton {
                                                required property var modelData
                                                label: modelData[0]
                                                accent: page.cityFilter === modelData[0]
                                                onClicked: page.cityFilter = page.cityFilter === modelData[0] ? "" : modelData[0]
                                            }
                                        }
                                    }
                                    Flow {
                                        width: parent.width - 12
                                        spacing: 6
                                        PageButton {
                                            label: page.cityFilter ? "Fastest in " + page.cityFilter : "Fastest in " + country.modelData.n
                                            onClicked: page.cityFilter
                                                ? VpnStatus.connect({ city: page.cityFilter, label: page.cityFilter })
                                                : VpnStatus.connect({ country: country.modelData.c, label: country.modelData.n })
                                        }
                                        PageButton {
                                            visible: country.modelData.sc > 0
                                            label: "Secure Core"
                                            onClicked: VpnStatus.connect({ country: country.modelData.c, secureCore: true,
                                                label: country.modelData.n + " via Secure Core" })
                                        }
                                        PageButton {
                                            visible: (country.modelData.f & 4) !== 0
                                            label: "P2P"
                                            onClicked: VpnStatus.connect({ country: country.modelData.c, p2p: true,
                                                label: country.modelData.n + " (P2P)" })
                                        }
                                    }

                                    Text {
                                        visible: country.open && !VpnStatus.servers[country.modelData.c]
                                        text: "Loading servers…"
                                        color: Theme.textDim
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                    Repeater {
                                        id: serverRepeater
                                        readonly property var all: country.open
                                            ? (VpnStatus.servers[country.modelData.c] || []).filter(s => !page.cityFilter || s[1] === page.cityFilter)
                                            : []
                                        model: serverRepeater.all.slice(0, page.serverLimit)
                                        ServerRow {
                                            required property var modelData
                                            width: listColumn.width - 12
                                            name: modelData[0]
                                            city: modelData[1]
                                            load: modelData[2]
                                            features: modelData[3]
                                            current: VpnStatus.server === modelData[0]
                                            favorite: VpnStatus.isFavorite("server", modelData[0])
                                            onClicked: VpnStatus.connect({ server: modelData[0] })
                                            onFavoriteClicked: VpnStatus.toggleFavorite({ kind: "server", id: modelData[0], label: modelData[0],
                                                country: country.modelData.c, city: modelData[1] })
                                        }
                                    }
                                    PageButton {
                                        visible: serverRepeater.all.length > page.serverLimit
                                        label: "Show more (" + (serverRepeater.all.length - page.serverLimit) + ")"
                                        onClicked: page.serverLimit += 25
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        // Settings: what `protonvpn config set` can change, read back from
        // the app's settings.json (shared with the app).
        Column {
            width: parent.width

            Rectangle {
                width: parent.width
                height: Theme.controlHeight + 8
                radius: Theme.controlRadius
                color: settingsArea.containsMouse ? Theme.hoverFill : "transparent"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Settings"
                    color: Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    id: settingsChevron
                    text: "\u{f0140}" // nf-md-chevron_down, turned up while open
                    rotation: page.settingsOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic } }
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    anchors.right: settingsChevron.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: [VpnStatus.killSwitch ? "Kill switch" : "", VpnStatus.netShieldLevel > 0 ? "NetShield" : ""].filter(t => t).join(" · ")
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.settingsOpen ? page.settingsOpen = false : page.openSettings()
                }
            }

            Collapsible {
                open: page.settingsOpen
                width: parent.width
                topPadding: Theme.sectionSpacing
                spacing: 4
                SettingRow {
                    label: "Kill switch"
                    caption: "Block the internet if the VPN drops"
                    Switch {
                        checked: VpnStatus.killSwitch
                        onToggled: VpnStatus.setSetting("kill-switch", checked ? "off" : "standard")
                    }
                }
                SettingRow {
                    label: "NetShield"
                    caption: ["DNS filtering, off", "Blocks malware", "Blocks malware, ads, trackers"][VpnStatus.netShieldLevel] || ""
                    minHeight: Theme.controlHeight + 4
                    Segmented {
                        anchors.verticalCenter: parent.verticalCenter
                        options: [{ value: "off", label: "Off" }, { value: "malware-only", label: "Malware" },
                            { value: "malware-ads-trackers", label: "+ Ads" }]
                        current: ["off", "malware-only", "malware-ads-trackers"][VpnStatus.netShieldLevel] || "off"
                        onPicked: (v) => VpnStatus.setSetting("netshield", v)
                    }
                }
                SettingRow {
                    label: "Port forwarding"
                    caption: "On P2P servers"
                    Switch {
                        checked: VpnStatus.portForwarding
                        onToggled: VpnStatus.setSetting("port-forwarding", checked ? "off" : "on")
                    }
                }
                SettingRow {
                    label: "VPN Accelerator"
                    caption: "Faster on distant servers"
                    Switch {
                        checked: VpnStatus.vpnAccelerator
                        onToggled: VpnStatus.setSetting("vpn-accelerator", checked ? "off" : "on")
                    }
                }
                SettingRow {
                    label: "Moderate NAT"
                    caption: "For games and P2P"
                    Switch {
                        checked: VpnStatus.moderateNat
                        onToggled: VpnStatus.setSetting("moderate-nat", checked ? "off" : "on")
                    }
                }
                SettingRow {
                    label: "IPv6"
                    caption: VpnStatus.protocolSetting === "wireguard" ? "Protocol: WireGuard (change it in the app)"
                        : VpnStatus.protocolSetting ? "Protocol: " + VpnStatus.protocolSetting + " (change it in the app)" : ""
                    Switch {
                        checked: VpnStatus.ipv6
                        onToggled: VpnStatus.setSetting("ipv6", checked ? "off" : "on")
                    }
                }
                Text {
                    width: parent.width
                    leftPadding: 10
                    text: "Changes apply on the next connection."
                    color: Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }

        // The app itself (sign-in, protocol, split tunneling, account).
        Rectangle {
            width: parent.width
            height: Theme.controlHeight + 8
            radius: Theme.controlRadius
            color: appArea.containsMouse ? Theme.hoverFill : "transparent"
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Open Proton VPN"
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
                id: appArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { ShellState.activePopup = ""; VpnStatus.openApp() }
            }
        }
    }

    // A section that slides open/closed (height) and fades its content
    // instead of popping; the card's own height follows it. It stays
    // visible at height 0 -- going invisible made the parent Column drop
    // its spacing at once, a jump at the start/end of every slide -- so it
    // goes in a spacing-0 column with its gap as topPadding, which slides too.
    component Collapsible: Item {
        id: col
        property bool open: false
        property alias spacing: colInner.spacing
        property alias leftPadding: colInner.leftPadding
        default property alias content: colInner.data
        property alias topPadding: colInner.topPadding
        implicitHeight: col.open ? colInner.implicitHeight : 0
        height: implicitHeight
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic } }
        Column {
            id: colInner
            width: parent.width
            // clip only hides: closed rows would still take clicks/hover
            // over what's below. The section itself stays visible.
            visible: col.height > 0.5
            opacity: col.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic } }
        }
    }

    component SectionLabel: Text {
        bottomPadding: 4
        color: Theme.textMuted
        font.family: Theme.uiFontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    // Flag, title + subtitle; tap = connect, the chevron (if any) expands.
    component ListRow: Rectangle {
        id: lr
        property string flag: ""
        property string title: ""
        property string subtitle: ""
        property bool selected: false
        property bool expandable: false
        property bool expanded: false
        property bool canFavorite: false
        property bool favorite: false
        signal clicked()
        signal expandClicked()
        signal favoriteClicked()
        width: parent ? parent.width : 0
        height: Theme.controlHeight + 12
        radius: Theme.controlRadius
        color: lr.selected ? Theme.selectedFill : lrArea.containsMouse ? Theme.hoverFill : "transparent"
        MouseArea {
            id: lrArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lr.clicked()
        }
        Text {
            id: lrFlag
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            text: lr.flag || "\u{f0565}"
            color: Theme.textMuted
            font.family: lr.flag ? Theme.uiFontFamily : Theme.fontFamily
            font.pixelSize: Theme.fontSize + 5
        }
        Column {
            anchors.left: lrFlag.right
            anchors.leftMargin: 6
            anchors.right: lrStar.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: lr.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: lr.selected
            }
            Text {
                visible: lr.subtitle !== ""
                width: parent.width
                text: lr.subtitle
                elide: Text.ElideRight
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
        StarButton {
            id: lrStar
            anchors.right: lrMore.left
            anchors.verticalCenter: parent.verticalCenter
            shown: lr.canFavorite && (lr.favorite || lrArea.containsMouse || hovered || lrMoreArea.containsMouse)
            starred: lr.favorite
            onClicked: lr.favoriteClicked()
        }
        Rectangle {
            id: lrMore
            visible: lr.expandable
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: lr.expandable ? 30 : 0
            radius: Theme.controlRadius
            color: lrMoreArea.containsMouse ? Theme.hoverFill : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\u{f0140}" // nf-md-chevron_down, turned up while expanded
                rotation: lr.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic } }
                color: lrMoreArea.containsMouse ? Theme.text : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            MouseArea {
                id: lrMoreArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lr.expandClicked()
            }
        }
    }

    // One server: name, city / features, load.
    component ServerRow: Rectangle {
        id: sv
        property string name: ""
        property string city: ""
        property int load: -1
        property int features: 0
        property bool current: false
        property bool favorite: false
        signal clicked()
        signal favoriteClicked()
        height: Theme.controlHeight + 6
        radius: Theme.controlRadius
        color: sv.current ? Theme.selectedFill : svArea.containsMouse ? Theme.hoverFill : "transparent"
        MouseArea {
            id: svArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sv.clicked()
        }
        Text {
            id: svName
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 78
            text: sv.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: sv.current
        }
        Text {
            anchors.left: svName.right
            anchors.leftMargin: 6
            anchors.right: svStar.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: [sv.city, sv.features & 1 ? "Secure Core" : "", page.featureText(sv.features)].filter(t => t).join(" · ")
            elide: Text.ElideRight
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        StarButton {
            id: svStar
            anchors.right: svLoad.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            shown: sv.favorite || svArea.containsMouse || hovered
            starred: sv.favorite
            onClicked: sv.favoriteClicked()
        }
        Row {
            id: svLoad
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 4
                radius: 2
                color: Theme.track
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, sv.load)) / 100
                    height: parent.height
                    radius: 2
                    color: page.loadColor(sv.load)
                }
            }
            Text {
                width: 30
                horizontalAlignment: Text.AlignRight
                text: sv.load >= 0 ? sv.load + "%" : ""
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // Favorite toggle: an outline star on hover, a filled one once starred.
    // Keeps its width while hidden so the row's text doesn't shift.
    component StarButton: Item {
        id: star
        property bool shown: false
        property bool starred: false
        readonly property bool hovered: starArea.containsMouse
        signal clicked()
        width: 30
        height: 28
        Text {
            visible: star.shown
            anchors.centerIn: parent
            text: star.starred ? "\u{f04ce}" : "\u{f04d2}" // nf-md-star / star_outline
            color: star.starred ? Theme.accentHover : starArea.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 9
        }
        MouseArea {
            id: starArea
            anchors.fill: parent
            enabled: star.shown || star.starred
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: star.clicked()
        }
    }

    // A label (and caption) on the left, a control on the right.
    component SettingRow: Item {
        id: sr
        property string label: ""
        property string caption: ""
        default property alias controls: srControls.data
        property real minHeight: Theme.controlHeight
        width: column.width
        height: Math.max(sr.minHeight, srText.implicitHeight + 8)
        Column {
            id: srText
            anchors.left: parent.left
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
            id: srControls
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 6
        }
    }

    // Segmented control, as on the Phone page.
    component Segmented: Rectangle {
        id: seg
        property var options: []  // [{value, label}]
        property string current: ""
        signal picked(string value)
        readonly property int index: seg.options.findIndex(o => o.value === seg.current)
        width: 180
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
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 2
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

    component PageButton: Rectangle {
        id: pb
        property string label: ""
        property bool accent: false
        property bool large: false
        signal clicked()
        width: pbLabel.implicitWidth + (pb.large ? 28 : 18)
        height: pb.large ? Theme.controlHeight + 4 : Theme.controlHeight - 2
        radius: Theme.controlRadius
        color: pb.accent ? (pbArea.containsMouse ? Theme.accentHover : Theme.accent)
            : pbArea.containsMouse ? Theme.hoverFill : Theme.controlFill
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
