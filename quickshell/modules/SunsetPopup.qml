import QtQuick
import Quickshell
import Quickshell.Io

// Night Light popup panel for SunsetToggle.qml (and the Control Center's
// Night Light page): the force on/off switch in the header, the
// independent "Follow schedule" switch, the 100K warmth slider, and the
// schedule times (±15 min, saved by themselves).
// Hover-driven with persistent hover, no focus grabs.
MorphContent {
    id: popup
    // Set when the Control Center embeds this as one of its pages: the
    // header's back button returns there.
    property string backPopupId: ""
    // Wider when embedded, to match the Control Center card.
    property real contentWidth: Theme.togglePopupWidth

    property bool active: false // mirrors ShellState.sunsetWarm
    property bool scheduleFollow: true // mirrors ShellState.sunsetScheduleFollow, fully independent of active
    property int kelvin: 2500 // last manually-set warmth

    signal setWarm(bool warm)
    signal setTemperature(int kelvin)
    signal setScheduleFollow(bool follow)
    signal scheduleSaved()


    // HoverHandler rather than a background MouseArea: a MouseArea only reports
    // containsMouse while it's the topmost hover-accepting item, so it goes false
    // the moment the cursor is over a descendant control that sets hoverEnabled
    // itself (the step buttons, a switch) — closing the popup mid-interaction.
    // HoverHandler tracks its own item's bounds independently of what's on top.
    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    onShownChanged: if (shown) loadTimes()

    readonly property int minKelvin: 2000
    readonly property int maxKelvin: 5000

    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/hypr/hyprsunset.conf"
        printErrors: false
        // There's one of these popups per bar plus one per Control Center,
        // each with its own copy of the file: without picking up the
        // others' saves, opening this one showed (and its Save wrote back
        // on top of) whatever was in the file when quickshell started.
        watchChanges: true
        onFileChanged: reload()
    }

    property int dayHour: 7
    property int dayMinute: 0
    property int nightHour: 23
    property int nightMinute: 0

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    // hyprsunset.conf declares exactly two profiles, day (identity) then
    // night (temperature) — pull their "time = H:MM" values in file order.
    function loadTimes() {
        const re = /time\s*=\s*(\d{1,2}):(\d{2})/g
        const matches = []
        let m
        while ((m = re.exec(confFile.text())) !== null) matches.push(m)
        if (matches[0]) { popup.dayHour = +matches[0][1]; popup.dayMinute = +matches[0][2] }
        if (matches[1]) { popup.nightHour = +matches[1][1]; popup.nightMinute = +matches[1][2] }
    }

    function saveTimes() {
        const times = [
            popup.pad2(popup.dayHour) + ":" + popup.pad2(popup.dayMinute),
            popup.pad2(popup.nightHour) + ":" + popup.pad2(popup.nightMinute)
        ]
        let i = 0
        confFile.setText(confFile.text().replace(/time\s*=\s*\d{1,2}:\d{2}/g, () => "time = " + times[i++]))
        popup.scheduleSaved()
    }

    // Times apply by themselves a moment after the last step (a save
    // restarts hyprsunset) -- there used to be a "Save schedule" button.
    Timer {
        id: saveTimer
        interval: 700
        onTriggered: popup.saveTimes()
    }

    // ±15 min, wrapping round midnight; an off-grid time (hand-edited
    // conf) snaps to the grid on its first step.
    function stepTime(h, m, dir) {
        const t = h * 60 + m
        const next = dir > 0 ? Math.floor(t / 15) * 15 + 15 : Math.ceil(t / 15) * 15 - 15
        const w = (next + 1440) % 1440
        return [Math.floor(w / 60), w % 60]
    }

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
                title: "Night Light"
                showBack: popup.backPopupId !== ""
                onBack: ShellState.activePopup = popup.backPopupId
                // Forces it on/off -- never touches Follow schedule below.
                Switch {
                    checked: popup.active
                    onToggled: popup.setWarm(!popup.active)
                }
            }

            // Independent of the switch above, and stored as its own
            // property rather than a shared mode enum. Changing it never
            // changes popup.active/the light itself (see
            // ShellState.setScheduleFollow) -- it only changes who gets to
            // decide going forward, so forcing on/off never knocks this off
            // the way an earlier version did.
            PageRow {
                width: popup.contentWidth
                glyph: "\u{f0150}"
                active: popup.scheduleFollow
                title: "Follow schedule"
                subtitle: "Warm from " + popup.pad2(popup.nightHour) + ":" + popup.pad2(popup.nightMinute)
                    + " to " + popup.pad2(popup.dayHour) + ":" + popup.pad2(popup.dayMinute)
                onClicked: popup.setScheduleFollow(!popup.scheduleFollow)
                Switch {
                    checked: popup.scheduleFollow
                    onToggled: popup.setScheduleFollow(!popup.scheduleFollow)
                }
            }

            // Warmth in steps of 100K.
            Column {
                width: popup.contentWidth
                spacing: 2
                SectionLabel {
                    text: "Warmth"
                }
                SliderRow {
                    width: parent.width
                    glyph: "\u{f0594}"
                    hasMore: false
                    dim: !popup.active || popup.scheduleFollow
                    // Same direction as the Night Light tile's slider.
                    value: (popup.kelvin - popup.minKelvin) / (popup.maxKelvin - popup.minKelvin)
                    valueText: popup.kelvin + "K"
                    onMoved: (v) => popup.setTemperature(Math.round((popup.minKelvin + v * (popup.maxKelvin - popup.minKelvin)) / 100) * 100)
                }
            }

            Column {
                width: popup.contentWidth
                spacing: 6
                SectionLabel {
                    text: "Schedule"
                }
                TimeRow {
                    glyph: "\u{f0594}"
                    title: "Night starts"
                    hour: popup.nightHour
                    minute: popup.nightMinute
                    onStep: (dir) => {
                        const t = popup.stepTime(popup.nightHour, popup.nightMinute, dir)
                        popup.nightHour = t[0]; popup.nightMinute = t[1]
                        saveTimer.restart()
                    }
                }
                TimeRow {
                    glyph: "\u{f0599}" // nf-md-weather_sunny
                    title: "Day starts"
                    hour: popup.dayHour
                    minute: popup.dayMinute
                    onStep: (dir) => {
                        const t = popup.stepTime(popup.dayHour, popup.dayMinute, dir)
                        popup.dayHour = t[0]; popup.dayMinute = t[1]
                        saveTimer.restart()
                    }
                }
            }
        }
    }

    component TimeRow: PageRow {
        id: tr
        property int hour: 0
        property int minute: 0
        signal step(int dir)
        width: popup.contentWidth
        clickable: false
        Text {
            anchors.verticalCenter: parent.verticalCenter
            rightPadding: 4
            text: popup.pad2(tr.hour) + ":" + popup.pad2(tr.minute)
            color: Theme.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
            font.features: { "tnum": 1 }
        }
        StepButton {
            glyph: "\u{f0374}"
            onClicked: tr.step(-1)
        }
        StepButton {
            glyph: "\u{f0415}"
            onClicked: tr.step(1)
        }
    }
}
