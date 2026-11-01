import QtQuick
import Quickshell
import Quickshell.Io

// Idle timeout settings popup panel for IdleToggle.qml (and the Control
// Center's Stay Awake page): the Stay Awake switch, then lock, dim and
// screen-off timers stepped with − / + (Never past the longest), written
// to hypridle.conf by themselves. Hover-driven with persistent hover.
MorphContent {
    id: popup
    // Set when the Control Center embeds this as one of its pages: the
    // header's back button returns there.
    property string backPopupId: ""
    // Wider when embedded, to match the Control Center card.
    property real contentWidth: Theme.togglePopupWidth

    property bool active: false

    signal settingsSaved()


    // HoverHandler rather than a background MouseArea: a MouseArea only reports
    // containsMouse while it's the topmost hover-accepting item, so it goes false
    // the moment the cursor is over a descendant control that sets hoverEnabled
    // itself (the step buttons) — closing the
    // popup mid-interaction. HoverHandler tracks its own item's bounds
    // independently of what's on top.
    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    onShownChanged: if (shown) loadSettings()

    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"
        printErrors: false
        // There's one of these popups per bar plus one per Control Center,
        // each with its own copy of the file: without picking up the
        // others' saves, opening this one showed (and its Save wrote back
        // on top of) whatever was in the file when quickshell started.
        watchChanges: true
        onFileChanged: reload()
    }

    property bool lockNever: false
    property int lockHours: 0
    property int lockMinutes: 5

    property bool dimNever: false
    property int dimSeconds: 15 // lead time before the lock, not an absolute idle time

    property bool offNever: false
    property int offHours: 0
    property int offMinutes: 10

    function loadSettings() {
        const text = confFile.text()
        const dimMatch = /listener\s*\{\s*timeout\s*=\s*(\d+)\s*\n\s*on-timeout\s*=\s*quickshell ipc call idledim/.exec(text)
        const lockMatch = /listener\s*\{\s*timeout\s*=\s*(\d+)\s*\n\s*on-timeout\s*=\s*pidof hyprlock/.exec(text)
        const offMatch = /listener\s*\{\s*timeout\s*=\s*(\d+)\s*\n\s*on-timeout\s*=\s*hyprctl eval[^\n]*dpms/.exec(text)

        popup.lockNever = !lockMatch
        if (lockMatch) {
            const total = +lockMatch[1]
            popup.lockHours = Math.floor(total / 3600)
            popup.lockMinutes = Math.floor((total % 3600) / 60)
        }

        popup.offNever = !offMatch
        if (offMatch) {
            const total = +offMatch[1]
            popup.offHours = Math.floor(total / 3600)
            popup.offMinutes = Math.floor((total % 3600) / 60)
        }

        popup.dimNever = !dimMatch
        if (dimMatch && lockMatch) popup.dimSeconds = Math.max(0, +lockMatch[1] - +dimMatch[1])
    }

    function saveSettings() {
        let listeners = ""
        if (!popup.lockNever) {
            const lockSec = popup.lockHours * 3600 + popup.lockMinutes * 60
            if (!popup.dimNever) {
                const dimSec = Math.max(0, lockSec - popup.dimSeconds)
                // Software dim (IdleDimOverlay.qml), not brightnessctl -- a
                // backlight write only ever dims the laptop panel, leaving
                // external/DDC-less monitors undimmed. See
                // IdleDimOverlay.qml's header for the full rationale.
                listeners += "listener {\n    timeout = " + dimSec
                    + "\n    on-timeout = quickshell ipc call idledim dim\n    on-resume = quickshell ipc call idledim undim\n}\n\n"
            }
            listeners += "listener {\n    timeout = " + lockSec
                + "\n    on-timeout = pidof hyprlock || hyprlock\n}\n\n"
        }
        if (!popup.offNever) {
            const offSec = popup.offHours * 3600 + popup.offMinutes * 60
            listeners += "listener {\n    timeout = " + offSec
                + "\n    on-timeout = hyprctl eval 'hl.dispatch(hl.dsp.dpms(\"off\"))'"
                + "\n    on-resume = hyprctl eval 'hl.dispatch(hl.dsp.dpms(\"on\"))'\n}\n"
        }

        const text = confFile.text()
        confFile.setText(/listener\s*\{/.test(text)
            ? text.replace(/listener\s*\{[\s\S]*/, listeners)
            : text.replace(/\s*$/, "\n") + listeners)
        popup.settingsSaved()
    }

    // Changes apply by themselves a moment after the last step (each save
    // restarts hypridle, so not one per click) -- the page used to need a
    // Save button, the only page in the Control Center that did.
    Timer {
        id: saveTimer
        interval: 700
        onTriggered: popup.saveSettings()
    }
    function changed() { saveTimer.restart() }

    // The steps a duration row walks through, minutes (or seconds for
    // dim), with whatever is configured now slotted in if it isn't one --
    // a hand-edited hypridle.conf keeps its exact value until stepped.
    readonly property var minuteSteps: [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
    readonly property var secondSteps: [5, 10, 15, 20, 30, 45]
    function stepsWith(list, cur) {
        return list.includes(cur) ? list : list.concat([cur]).sort((x, y) => x - y)
    }
    function minutesText(m) {
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60), r = m % 60
        return h + " h" + (r ? " " + r + " min" : "")
    }

    readonly property int lockTotal: popup.lockHours * 60 + popup.lockMinutes
    readonly property int offTotal: popup.offHours * 60 + popup.offMinutes
    function setLock(m) { popup.lockHours = Math.floor(m / 60); popup.lockMinutes = m % 60 }
    function setOff(m) { popup.offHours = Math.floor(m / 60); popup.offMinutes = m % 60 }

    Item {
        id: bg
        anchors.fill: parent

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            PageHeader {
                width: popup.contentWidth
                title: "Stay Awake"
                showBack: popup.backPopupId !== ""
                onBack: ShellState.activePopup = popup.backPopupId
                PinButton {
                    toggleId: "idle"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Switch {
                    checked: popup.active
                    onToggled: ShellState.setIdleActive(!ShellState.idleActive, 0)
                }
            }

            PageRow {
                width: popup.contentWidth
                clickable: false
                glyph: "\u{f0176}"
                active: popup.active
                title: popup.active ? "Staying awake" : "Off"
                subtitle: popup.active ? "No lock, dimming or screen off until switched off"
                    : "The timers below apply when idle"
            }

            Column {
                width: popup.contentWidth
                spacing: 6
                SectionLabel {
                    text: "When idle"
                }
                StepRow {
                    glyph: "\u{f033e}"
                    title: "Lock"
                    never: popup.lockNever
                    valueText: popup.minutesText(popup.lockTotal)
                    steps: popup.stepsWith(popup.minuteSteps, popup.lockTotal)
                    current: popup.lockTotal
                    onPick: (v) => { popup.lockNever = v < 0; if (v >= 0) popup.setLock(v); popup.changed() }
                }
                StepRow {
                    glyph: "\u{f00de}"
                    title: "Dim first"
                    // Lead time before the lock, so nothing without one.
                    available: !popup.lockNever
                    never: popup.dimNever
                    valueText: popup.dimSeconds + " s before"
                    steps: popup.stepsWith(popup.secondSteps, popup.dimSeconds)
                    current: popup.dimSeconds
                    onPick: (v) => { popup.dimNever = v < 0; if (v >= 0) popup.dimSeconds = v; popup.changed() }
                }
                StepRow {
                    glyph: "\u{f0e51}"
                    title: "Screen off"
                    never: popup.offNever
                    valueText: popup.minutesText(popup.offTotal)
                    steps: popup.stepsWith(popup.minuteSteps, popup.offTotal)
                    current: popup.offTotal
                    onPick: (v) => { popup.offNever = v < 0; if (v >= 0) popup.setOff(v); popup.changed() }
                }
            }
        }
    }

    // A timer as a page row: its value under the title, − / + walking the
    // steps, "Never" past the last one (− from Never comes back to it).
    component StepRow: PageRow {
        id: sr
        property bool never: false
        property string valueText: ""
        property var steps: []
        property int current: 0
        signal pick(int value) // -1 = never
        readonly property int index: sr.steps.indexOf(sr.current)
        clickable: false
        active: !sr.never && sr.available
        subtitle: sr.never ? "Never" : sr.valueText
        StepButton {
            glyph: "\u{f0374}" // nf-md-minus
            enabled: sr.never || sr.index > 0
            onClicked: sr.pick(sr.never ? sr.steps[sr.steps.length - 1] : sr.steps[sr.index - 1])
        }
        StepButton {
            glyph: "\u{f0415}" // nf-md-plus
            enabled: !sr.never
            onClicked: sr.pick(sr.index >= sr.steps.length - 1 ? -1 : sr.steps[sr.index + 1])
        }
    }
}
