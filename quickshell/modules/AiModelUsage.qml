import QtQuick
import Quickshell
import Quickshell.Io

// AI Model Usage Widget (Claude Code & Google Antigravity / AGY)
// Tracks and displays real-time 5-hour window usage percentages, weekly limits,
// and reset times for both AI models with an identical visual language.
// Supports 250ms initial delay, immediate switching when moving between open widgets,
// and persistent hover over popup.
Pill {
    id: root

    visible: root.claudeRunning || root.agyRunning

    property bool claudeRunning: false
    property bool agyRunning: false
    property string currentAgent: "claude" // "claude" | "agy"
    property string screenName: ""
    readonly property bool bothRunning: root.claudeRunning && root.agyRunning

    function toggleAgent() {
        if (!root.bothRunning) return
        root.currentAgent = (root.currentAgent === "claude" ? "agy" : "claude")
    }

    onClaudeRunningChanged: {
        if (root.claudeRunning && !root.agyRunning) root.currentAgent = "claude"
        if (root.claudeRunning) usageProc.running = true
    }
    onAgyRunningChanged: {
        if (root.agyRunning && !root.claudeRunning) root.currentAgent = "agy"
        if (root.agyRunning) agyUsageProc.running = true
    }

    onClicked: (mouse) => {
        if (root.bothRunning) root.toggleAgent()
    }

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "ai-model-usage"
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

    // --- Claude State ---
    property var claudeFiveHourPercent: null
    property var claudeFiveHourResetsAt: null
    property var claudeWeeklyPercent: null
    property var claudeWeeklyResetsAt: null

    // --- AGY State ---
    property var agyFiveHourPercent: null
    property var agyFiveHourResetsAt: null
    property var agyWeeklyPercent: null
    property var agyWeeklyResetsAt: null
    property string agyTitle: ""
    property int agyStepCount: 0
    property string agyStatus: "Idle"
    property bool agyIsBusy: false

    // --- Active Agent Computed Metrics ---
    readonly property var activeFiveHourPercent: (root.currentAgent === "claude")
        ? root.claudeFiveHourPercent
        : root.agyFiveHourPercent

    readonly property var activeFiveHourResetsAt: (root.currentAgent === "claude")
        ? root.claudeFiveHourResetsAt
        : root.agyFiveHourResetsAt

    readonly property var activeWeeklyPercent: (root.currentAgent === "claude")
        ? root.claudeWeeklyPercent
        : root.agyWeeklyPercent

    readonly property var activeWeeklyResetsAt: (root.currentAgent === "claude")
        ? root.claudeWeeklyResetsAt
        : root.agyWeeklyResetsAt

    readonly property bool haveData: root.activeFiveHourPercent !== null

    // Strictly 3-character format in monospace font (" 7%", "24%", "$$$" at 100%)
    function _formatPillText(percent) {
        if (percent === null || percent === undefined) return "---"
        const rounded = Math.round(percent)
        if (rounded >= 100) return "$$$"
        if (rounded < 10) return " " + rounded + "%"
        return rounded + "%"
    }

    // nf-md-circle_slice_1..8 (U+F0A9E..F0A5), 8 pie-fill steps of 5h window fraction
    readonly property var sliceIcons: ["󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥"]
    readonly property string sliceIcon: (root.activeFiveHourPercent !== null)
        ? root.sliceIcons[Math.max(0, Math.min(7, Math.ceil(root.activeFiveHourPercent / 12.5) - 1))]
        : "󰚩"

    function _resetTimeText(epoch) {
        if (!epoch) return "?"
        const d = new Date(epoch * 1000)
        const diffHours = (epoch - root._nowSec) / 3600
        if (diffHours > 24) {
            return Qt.formatDateTime(d, "MMM d, " + (TimeRegion.use24Hour ? "HH:mm" : "h:mm AP"))
        }
        return Qt.formatDateTime(d, TimeRegion.use24Hour ? "HH:mm" : "h:mm AP")
    }

    function _barColor(percent) {
        if (percent === null) return Theme.textDim
        if (percent >= 90) return Theme.critical
        if (percent >= 70) return Theme.submap
        return Theme.success
    }

    property real _nowSec: Date.now() / 1000
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root._nowSec = Date.now() / 1000 }

    function _timeProgress(resetsAt, windowSeconds) {
        if (!resetsAt) return null
        const remaining = resetsAt - root._nowSec
        return Math.max(0, Math.min(100, 100 * (windowSeconds - remaining) / windowSeconds))
    }
    readonly property var fiveHourTimeProgress: root._timeProgress(root.activeFiveHourResetsAt, 5 * 60 * 60)
    readonly property var weeklyTimeProgress: root._timeProgress(root.activeWeeklyResetsAt, 7 * 24 * 60 * 60)

    // Pill Bar Content - strictly equal width across all values
    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.haveData
        text: root.sliceIcon
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * 1.5
        color: Theme.text
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._formatPillText(root.activeFiveHourPercent)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: (root.activeFiveHourPercent !== null && root.activeFiveHourPercent >= 90) ? Theme.critical : Theme.text
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.bothRunning
        text: "⇄"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
        color: Theme.textDim
    }

    // Hover Popup Window
    PopupWindow {
        id: popup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        visible: root.popupOpen

        readonly property int popupWidth: 280
        readonly property int contentWidth: 256

        width: popupWidth
        implicitWidth: popupWidth
        implicitHeight: bg.implicitHeight

        Rectangle {
            id: bg
            width: popup.popupWidth
            implicitWidth: popup.popupWidth
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
                width: popup.contentWidth
                anchors {
                    top: parent.top
                    topMargin: 12
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 12

                // Multi-agent Switcher Tabs (when both running)
                Row {
                    width: popup.contentWidth
                    spacing: 6
                    visible: root.bothRunning

                    Rectangle {
                        width: Math.floor((popup.contentWidth - 6) / 2)
                        height: 28
                        radius: 4
                        color: root.currentAgent === "claude" ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: root.currentAgent === "claude" ? Theme.accent : "transparent"
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰚩"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                text: "Claude"
                                color: root.currentAgent === "claude" ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: root.currentAgent === "claude"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentAgent = "claude"
                        }
                    }

                    Rectangle {
                        width: Math.floor((popup.contentWidth - 6) / 2)
                        height: 28
                        radius: 4
                        color: root.currentAgent === "agy" ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: root.currentAgent === "agy" ? Theme.accent : "transparent"
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󱚣"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                text: "Antigravity"
                                color: root.currentAgent === "agy" ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: root.currentAgent === "agy"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentAgent = "agy"
                        }
                    }
                }

                // Single-agent Header (when only one agent is running)
                Item {
                    width: popup.contentWidth
                    height: 20
                    visible: !root.bothRunning

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            text: root.currentAgent === "claude" ? "󰚩" : "󱚣"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: root.currentAgent === "claude" ? "Claude Code" : "Antigravity (AGY)"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                    }
                }

                // --- 5-Hour Window Section ---
                Column {
                    width: popup.contentWidth
                    spacing: 4

                    Item {
                        width: parent.width
                        height: fiveHourLabel.implicitHeight
                        Text {
                            id: fiveHourLabel
                            text: "5h window"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.activeFiveHourPercent !== null ? (Math.round(root.activeFiveHourPercent) >= 100 ? "100%" : Math.round(root.activeFiveHourPercent) + "%") : "—"
                            color: root._barColor(root.activeFiveHourPercent)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 8
                        radius: 0
                        color: Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, (root.activeFiveHourPercent || 0) / 100))
                            height: parent.height
                            radius: 0
                            color: root._barColor(root.activeFiveHourPercent)
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 0
                        color: Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, (root.fiveHourTimeProgress || 0) / 100))
                            height: parent.height
                            radius: 0
                            color: Theme.textDim
                        }
                    }

                    Text {
                        text: "resets " + root._resetTimeText(root.activeFiveHourResetsAt)
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                // --- Weekly Section ---
                Column {
                    width: popup.contentWidth
                    spacing: 4

                    Item {
                        width: parent.width
                        height: weeklyLabel.implicitHeight
                        Text {
                            id: weeklyLabel
                            text: "Weekly"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.activeWeeklyPercent !== null ? (Math.round(root.activeWeeklyPercent) >= 100 ? "100%" : Math.round(root.activeWeeklyPercent) + "%") : "—"
                            color: root._barColor(root.activeWeeklyPercent)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 8
                        radius: 0
                        color: Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, (root.activeWeeklyPercent || 0) / 100))
                            height: parent.height
                            radius: 0
                            color: root._barColor(root.activeWeeklyPercent)
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 0
                        color: Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, (root.weeklyTimeProgress || 0) / 100))
                            height: parent.height
                            radius: 0
                            color: Theme.textDim
                        }
                    }

                    Text {
                        text: "resets " + root._resetTimeText(root.activeWeeklyResetsAt)
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                // Context footer (for AGY active task / steps)
                Column {
                    width: popup.contentWidth
                    spacing: 3
                    visible: root.currentAgent === "agy" && Boolean(root.agyTitle)

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    Text {
                        width: parent.width
                        text: root.agyTitle
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Process: pgrep for claude
    Process {
        id: pgrepClaude
        command: ["pgrep", "-x", "claude"]
        onExited: (exitCode) => { root.claudeRunning = (exitCode === 0) }
    }

    // Process: pgrep for agy
    Process {
        id: pgrepAgy
        command: ["pgrep", "-x", "agy"]
        onExited: (exitCode) => { root.agyRunning = (exitCode === 0) }
    }

    // Process: Claude Usage Fetcher
    Process {
        id: usageProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/claude-usage.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.claudeFiveHourPercent = data.fiveHourPercent
                    root.claudeFiveHourResetsAt = data.fiveHourResetsAt
                    root.claudeWeeklyPercent = data.weeklyPercent
                    root.claudeWeeklyResetsAt = data.weeklyResetsAt
                } catch (e) {
                    root.claudeFiveHourPercent = null
                }
            }
        }
    }

    // Process: AGY Status Fetcher
    Process {
        id: agyUsageProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/agy-usage.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.agyFiveHourPercent = data.fiveHourPercent
                    root.agyFiveHourResetsAt = data.fiveHourResetsAt
                    root.agyWeeklyPercent = data.weeklyPercent
                    root.agyWeeklyResetsAt = data.weeklyResetsAt
                    root.agyTitle = data.title || ""
                    root.agyStepCount = data.stepCount || 0
                    root.agyStatus = data.status || "Idle"
                    root.agyIsBusy = Boolean(data.isBusy)
                } catch (e) {
                    root.agyFiveHourPercent = null
                }
            }
        }
    }

    // Process detection timer (fast, low overhead)
    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pgrepClaude.running = true
            pgrepAgy.running = true
        }
    }

    // Claude API usage timer (180s to respect strict Anthropic rate limits)
    Timer {
        interval: 180000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.claudeRunning) usageProc.running = true
    }

    // AGY local state poll timer (5s for live step counts and activity)
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.agyRunning) agyUsageProc.running = true
    }
}
