import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// SUPER+SHIFT+W: full-screen wallpaper gallery on the focused monitor. The
// highlighted wallpaper fills the screen behind a carousel of cards, so
// browsing is a live preview without touching hyprpaper; Enter (or a click
// on the highlighted card) applies it everywhere via scripts/wallpaper.py,
// which also remembers it for the next login and hyprlock. The images are
// ~/Pictures/Wallpapers (see that script's header). Unless "Match colors"
// is off, applying one also re-tints the shell's palette (Theme.qml) after
// it; the swatch under the name previews that.
PanelWindow {
    id: win
    WlrLayershell.namespace: "sichos-wallpaper"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    screen: Quickshell.screens[0]
    visible: false
    focusable: true
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper.py"
    // wallpaper.py list's output. Kept between opens so the gallery shows
    // at once; re-read on every open (the first one makes the thumbnails,
    // ~1.5s for a handful of 4K+ images).
    property var items: []
    property string current: ""
    property string folder: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    property bool loaded: false
    property bool followColors: true
    // Set once the user moves in this open; until then a fresh list starts
    // at the current wallpaper rather than wherever the list was left.
    property bool browsed: false
    readonly property var selected: items[list.currentIndex] ?? null

    function prettyName(name) {
        return name.replace(/[-_]+/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2")
    }
    function activeScreen() {
        const mon = Hyprland.focusedMonitor
        if (mon) {
            for (const s of Quickshell.screens) {
                if (s.name === mon.name) return s
            }
        }
        return Quickshell.screens[0]
    }
    function selectCurrent() {
        const i = win.items.findIndex(w => w.path === win.current)
        // Only the index: StrictlyEnforceRange scrolls to it, and a
        // positionViewAtIndex() on top of that, mid width animation, made
        // the range re-pick the neighbouring card.
        list.currentIndex = Math.max(0, i)
    }
    function open() {
        win.screen = win.activeScreen()
        win.browsed = false
        win.visible = true
        win.selectCurrent()
        listProc.running = false
        listProc.running = true
    }
    function close() {
        win.visible = false
    }
    function toggle() {
        if (win.visible) win.close()
        else win.open()
    }
    function move(delta) {
        if (!win.items.length) return
        win.browsed = true
        list.currentIndex = Math.max(0, Math.min(win.items.length - 1, list.currentIndex + delta))
    }
    function apply(item) {
        if (!item) return
        win.current = item.path
        setProc.command = ["python3", win.script, "set", item.path]
        setProc.running = true
        win.close()
    }

    Process {
        id: listProc
        command: ["python3", win.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data
                try { data = JSON.parse(text) } catch (e) { return }
                const keep = win.browsed && win.selected ? win.selected.path : ""
                win.items = data.items
                win.current = data.current
                win.folder = data.dir
                win.followColors = data.follow
                win.loaded = true
                // Stay on what's highlighted if the user already moved (the
                // list can land while browsing), else start at the current one.
                const i = keep ? win.items.findIndex(w => w.path === keep) : -1
                if (i >= 0) list.currentIndex = i
                else win.selectCurrent()
            }
        }
    }
    Process { id: setProc }
    Process { id: colorsProc }
    function toggleColors() {
        win.followColors = !win.followColors
        colorsProc.command = ["python3", win.script, "colors", win.followColors ? "on" : "off"]
        colorsProc.running = true
    }

    IpcHandler {
        target: "wallpaper"
        function toggle() { win.toggle() }
        function close() { win.close() }
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        opacity: win.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.openDuration; easing.type: Easing.OutCubic } }

        Keys.onPressed: (event) => {
            const k = event.key
            if (k === Qt.Key_Escape) win.close()
            else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backtab) win.move(-1)
            else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Tab) win.move(1)
            else if (k === Qt.Key_Home) win.move(-win.items.length)
            else if (k === Qt.Key_End) win.move(win.items.length)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) win.apply(win.selected)
            else if (k === Qt.Key_C) win.toggleColors()
            else return
            event.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.background
        }

        // Preview: the cached thumbnail at once, then the real image decoded
        // at screen size fades in over it once browsing pauses -- decoding
        // every image scrolled past (one is 9504x6336) made arrows lag.
        Image {
            anchors.fill: parent
            source: win.selected ? "file://" + win.selected.thumb : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
        Image {
            id: full
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize: Qt.size(win.screen.width, win.screen.height)
            opacity: status === Image.Ready && source == fullTimer.wanted ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Timer {
            id: fullTimer
            property string wanted: win.selected ? "file://" + win.selected.path : ""
            onWantedChanged: restart()
            interval: 250
            onTriggered: if (win.visible) full.source = wanted
        }

        // Darkens the lower half so the carousel and the name read over any
        // image, bright skies included.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.15) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: win.close()
            onWheel: (wheel) => {
                const d = wheel.angleDelta.y || -wheel.angleDelta.x
                if (d !== 0) win.move(d > 0 ? -1 : 1)
            }
        }

        Column {
            id: info
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: list.top
            anchors.bottomMargin: Theme.sectionSpacing * 2
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.selected ? win.prettyName(win.selected.name)
                    : win.loaded ? "No wallpapers yet" : "Loading wallpapers…"
                color: Theme.text
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize * 2.4
                font.bold: true
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.4)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !win.selected
                    ? (win.loaded ? "Put images in " + win.folder.replace(Quickshell.env("HOME"), "~") : "")
                    : win.selected.path === win.current ? "Current wallpaper"
                    : (list.currentIndex + 1) + " of " + win.items.length
                color: win.selected && win.selected.path === win.current ? Theme.success : Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
            }
            // The palette this wallpaper gives the shell.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6
                spacing: 6
                visible: win.followColors && !!win.selected
                opacity: visible ? 1 : 0
                Repeater {
                    model: win.selected ? win.selected.colors : []
                    Rectangle {
                        required property var modelData
                        width: 14
                        height: 14
                        radius: 7
                        color: modelData
                        border.color: Qt.rgba(0, 0, 0, 0.35)
                        Behavior on color { ColorAnimation { duration: Theme.morphDuration } }
                    }
                }
            }
        }

        // The highlighted card is a full 16:9 picture; its neighbours are
        // narrow slices of theirs that open up as they come into focus.
        ListView {
            id: list
            readonly property real cardHeight: Math.round(win.screen.height * 0.24)
            readonly property real wideWidth: Math.round(cardHeight * 16 / 9)
            readonly property real narrowWidth: Math.round(cardHeight * 0.42)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: hints.top
            anchors.bottomMargin: Theme.sectionSpacing * 2
            height: cardHeight
            orientation: ListView.Horizontal
            spacing: Theme.sectionSpacing
            model: win.items
            interactive: false
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width - wideWidth) / 2
            preferredHighlightEnd: (width + wideWidth) / 2
            highlightMoveDuration: Theme.morphDuration
            highlightFollowsCurrentItem: true

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool isSelected: ListView.isCurrentItem
                readonly property bool isCurrent: modelData.path === win.current
                width: isSelected ? list.wideWidth : list.narrowWidth
                height: list.cardHeight
                Behavior on width { NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic } }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: Theme.surfaceSquircleRadius
                    color: Theme.surface

                    Image {
                        anchors.fill: parent
                        source: "file://" + card.modelData.thumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.height: list.cardHeight
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                        opacity: card.isSelected ? 0 : hover.containsMouse ? 0.2 : 0.45
                        Behavior on opacity { NumberAnimation { duration: Theme.morphDuration } }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.surfaceSquircleRadius
                    color: "transparent"
                    border.color: card.isSelected ? Theme.accent : Theme.surfaceBorder
                    border.width: card.isSelected ? 3 : 1
                }
                // Marks the wallpaper in use, also on a narrow slice.
                Rectangle {
                    visible: card.isCurrent
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    width: 22
                    height: 22
                    radius: 11
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (card.isSelected) win.apply(card.modelData)
                        else win.move(card.index - list.currentIndex)
                    }
                }
            }
        }

        Row {
            id: hints
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.sectionSpacing * 3
            spacing: Theme.sectionSpacing * 2

            Repeater {
                model: [["←  →", "Browse"], ["Enter", "Apply"], ["Esc", "Close"]]
                Row {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: keyText.implicitWidth + 12
                        height: Theme.controlHeight - 4
                        radius: Theme.controlRadius
                        color: Theme.controlFill
                        border.color: Theme.surfaceBorder
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData[0]
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[1]
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: colorsRow.implicitWidth + 20
                height: Theme.controlHeight
                radius: Theme.controlRadius
                color: colorsMouse.containsMouse ? Theme.hoverFill : win.followColors ? Theme.selectedFill : Theme.controlFill
                border.color: win.followColors ? Theme.accent : Theme.surfaceBorder
                Row {
                    id: colorsRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf53f"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Match colors: " + (win.followColors ? "On" : "Off")
                        color: Theme.text
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
                MouseArea {
                    id: colorsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.toggleColors()
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: folderRow.implicitWidth + 20
                height: Theme.controlHeight
                radius: Theme.controlRadius
                color: folderMouse.containsMouse ? Theme.hoverFill : Theme.controlFill
                border.color: Theme.surfaceBorder
                Row {
                    id: folderRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Open folder"
                        color: Theme.text
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
                MouseArea {
                    id: folderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // nautilus directly, as on the Phone page: inode/directory's
                    // default handler can be anything (VS Code had it here).
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && exec nautilus "$1"', "sh", win.folder])
                        win.close()
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (win.visible) root.forceActiveFocus()
        else full.source = ""
    }
}
