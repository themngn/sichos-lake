import QtQuick
import Quickshell
import Quickshell.Io

// System Update widget: a pill that only renders once dnf and/or Flatpak
// report at least one pending update (hidden the rest of the time -- most
// days), and stays hidden for 24h after the last successful update even if
// a new pending count shows up in that window (e.g. a repo publishing a
// same-day follow-up build) -- avoids nagging again right after "Update
// All" was just used. Hover opens a menu with the pending count (broken
// down by source), when the system was last updated, a "Check now" re-poll,
// and an "Update All" button that opens a floating kitty console running
// system-update-run.sh (dnf upgrade + flatpak update, system and user) --
// same float-and-center floating-terminal treatment as wlctl/btop/fastfetch
// (see window_rules.lua's float-center-* rules; sichos-update-console needs
// its own entry there too).
Pill {
    id: root

    readonly property bool recentlyUpdated: root.lastUpdateEpoch !== null
        && (root._nowSec - root.lastUpdateEpoch) < 86400
    visible: root.count !== null && root.count > 0 && !root.recentlyUpdated
    property string screenName: ""

    // Only needs to be fresh enough to flip `recentlyUpdated` off within a
    // reasonable window of crossing the 24h mark -- same pattern/interval as
    // AiModelUsage.qml's _nowSec.
    property real _nowSec: Date.now() / 1000
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root._nowSec = Date.now() / 1000 }

    property var count: null
    property var dnfCount: null
    property var flatpakCount: null
    property bool lastCheckOk: true
    property var lastUpdateEpoch: null
    property var checkedAt: null
    property bool updating: false

    tooltipText: root.count
        ? (root.count + (root.count === 1 ? " update available" : " updates available"))
        : ""

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    // (identical pattern to BluetoothIndicator.qml/AiModelUsage.qml)
    readonly property string popupId: "system-update"
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool popupHovered: popupMouseArea.containsMouse

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

    function _dateText(epoch) {
        if (!epoch) return "unknown"
        return Qt.formatDateTime(new Date(epoch * 1000), "MMM d, " + (TimeRegion.use24Hour ? "HH:mm" : "h:mm AP"))
    }

    function _breakdownText() {
        if (root.count === null) return "Update status unknown"
        const parts = []
        if (root.dnfCount) parts.push(root.dnfCount + " dnf")
        if (root.flatpakCount) parts.push(root.flatpakCount + " flatpak")
        if (parts.length === 0) return "No updates available"
        return root.count + (root.count === 1 ? " update available" : " updates available")
            + " (" + parts.join(", ") + ")"
    }

    // nf-md-update, ink 600/1000em (fontTools glyf bbox) -- scaled to the
    // shared bar icon target, same as AiModelUsage's circle-slice glyphs.
    BarIcon {
        glyph: "󰚰"
        pixelSize: Theme.barIconInkHeight * 1000 / 600
        color: root.lastCheckOk ? Theme.submap : Theme.critical
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.count !== null ? String(root.count) : "?"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }

    PopupWindow {
        id: panel
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        visible: root.popupOpen

        readonly property int popupWidth: 260

        implicitWidth: popupWidth
        implicitHeight: bg.implicitHeight

        Rectangle {
            id: bg
            implicitWidth: panel.popupWidth
            implicitHeight: content.implicitHeight + 24
            color: "#1c1c1c"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 6

            MouseArea {
                id: popupMouseArea
                anchors.fill: parent
                hoverEnabled: true
                z: -1
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

                Row {
                    spacing: 6
                    Text {
                        text: "󰚰"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        color: Theme.submap
                    }
                    Text {
                        text: "System Update"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Text {
                    width: parent.width
                    text: root._breakdownText()
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    wrapMode: Text.Wrap
                }

                Text {
                    text: "Last updated: " + root._dateText(root.lastUpdateEpoch)
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Item {
                    width: parent.width
                    height: checkNowLabel.implicitHeight

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.checkedAt
                            ? (root.lastCheckOk ? "Checked " : "Check failed ") + root._dateText(root.checkedAt)
                            : "Not checked yet"
                        color: root.lastCheckOk ? Theme.textDim : Theme.critical
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }

                    Text {
                        id: checkNowLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: checkProc.running ? "Checking…" : "Check now"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!checkProc.running) checkProc.running = true
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 4
                    color: root.updating ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.14)

                    Text {
                        anchors.centerIn: parent
                        text: root.updating ? "Updating…" : "Update All"
                        color: root.updating ? Theme.textDim : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.updating ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (root.updating) return
                            root.updating = true
                            updateProc.running = true
                        }
                    }
                }
            }
        }
    }

    // system-update-check.py maintains its own on-disk cache the same way
    // claude-usage.py/weather.py do -- reading it here shows the last known
    // count on the very first frame, before checkProc's own first run
    // (which can take a while: system-update-check.py gives dnf up to 180s)
    // finishes.
    FileView {
        id: cacheFile
        path: Quickshell.env("HOME") + "/.config/quickshell/system-update-cache.json"
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text())
                root.count = data.count !== undefined ? data.count : null
                root.dnfCount = data.dnfCount !== undefined ? data.dnfCount : null
                root.flatpakCount = data.flatpakCount !== undefined ? data.flatpakCount : null
                root.lastCheckOk = data.lastCheckOk !== false
                root.lastUpdateEpoch = data.lastUpdateEpoch || null
                root.checkedAt = data.checkedAt || null
            } catch (e) { /* no cache yet -- stays hidden until checkProc finishes */ }
        }
    }

    Process {
        id: checkProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/system-update-check.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.count = data.count !== undefined ? data.count : null
                    root.dnfCount = data.dnfCount !== undefined ? data.dnfCount : null
                    root.flatpakCount = data.flatpakCount !== undefined ? data.flatpakCount : null
                    root.lastCheckOk = data.lastCheckOk !== false
                    root.lastUpdateEpoch = data.lastUpdateEpoch || null
                    root.checkedAt = data.checkedAt || null
                } catch (e) { /* keep last known values on parse failure */ }
            }
        }
    }

    // Run as an attached Process (not Quickshell.execDetached) so onExited
    // can fire an immediate re-check the moment the user closes the
    // console, instead of waiting up to pollTimer's full 30-minute interval
    // to notice the upgrade already happened. --hold keeps the window open
    // showing the transaction's final output/exit status (same as the
    // fastfetch "Info" window in Launcher.qml) rather than the console
    // vanishing the instant it finishes. system-update-run.sh is a real
    // script (not a `kitty -e ... && ...` command line) because kitty -e
    // execs its argv directly with no shell, so it can only ever run one
    // command on its own -- see that script's own header comment.
    Process {
        id: updateProc
        command: ["kitty", "--class", "sichos-update-console", "--hold",
                  "-e", "bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/system-update-run.sh"]
        onExited: {
            root.updating = false
            checkProc.running = true
        }
    }

    Timer {
        id: pollTimer
        interval: 1800000 // 30 min -- dnf check-update hits the network, no need for anything tighter
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!checkProc.running) checkProc.running = true
    }
}
