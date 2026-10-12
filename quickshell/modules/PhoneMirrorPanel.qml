import QtQuick
import Quickshell
import Quickshell.Wayland

// Per-screen companion surfaces for the phone mirror's scrcpy window (see
// PhoneMirrorState.qml / scripts/phone-mirror.sh), shown only on the screen
// the mirror was opened on:
//   - a loading card in the window's exact spot while scrcpy connects,
//   - the controls card docked under the window,
//   - when collapsed, a thin tab on the screen edge where the controls were.
// The window itself is a real Hyprland window (scrcpy needs one to forward
// input), so these only line up with it by sharing the same gap/height math.
Scope {
    id: root
    required property var modelData
    readonly property ShellScreen screen: modelData

    readonly property bool here: PhoneMirrorState.screenName === root.screen.name
    // Docked to the left monitor edge instead of the right (the controls
    // card's swap button); every surface here mirrors its anchoring.
    readonly property bool left: PhoneMirrorState.side === "left"
    readonly property int gap: PhoneMirrorState.gap
    readonly property int controlsHeight: PhoneMirrorState.controlsHeight
    readonly property int phoneHeight: root.screen.height - Theme.barHeight - root.controlsHeight - root.gap * 3
    readonly property int phoneWidth: Math.round(root.phoneHeight * PhoneMirrorState.aspect)

    // The phone window's slide duration (phone-mirror.sh SMOOTH_MOVE, 3.2ds);
    // the controls card matches it and the tab waits most of it out.
    readonly property int slideDuration: 320

    readonly property int tabWidth: 21

    // Nine button slots on the controls card (2 left, 5 centre, 2 right). The
    // card is only as wide as the phone -- ~494px on a 1200px-tall screen --
    // so buttons narrow from their 1.3:1 shape to fit: 4px spacing inside the
    // groups, >=10px between them, the card's (60-44)/2 edge margin.
    readonly property int buttonWidth: Math.floor((root.phoneWidth - 6 * 4 - 2 * 10 - 2 * 8) / 9)

    component ControlButton: Rectangle {
        id: btn
        required property string glyph
        property string tip: ""
        // Toggle buttons (audio): lit while on, like the bar's toggle pills.
        property bool active: false
        // Long press, for buttons that have one (power: the phone's power menu).
        property bool holdable: false
        signal activated()
        signal held()
        // Scaled with the card (PhoneMirrorState.controlsHeight) rather than
        // Theme.controlHeight: big touch-sized targets, like a phone nav bar.
        height: root.controlsHeight - 16
        width: Math.min(height * 1.3, root.buttonWidth)
        radius: Theme.controlRadius
        color: btnMouse.pressed || btn.active ? Theme.selectedFill : btnMouse.containsMouse ? Theme.hoverFill : "transparent"

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(btn.height * 0.55)
            color: Theme.text
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            property bool wasHeld: false
            onPressed: wasHeld = false
            onPressAndHold: if (btn.holdable) { wasHeld = true; btn.held() }
            onClicked: if (!wasHeld) btn.activated()
        }
    }

    // Thin vertical line between button groups. y is set by hand: Row only
    // lays children out horizontally.
    component Divider: Rectangle {
        width: 1
        height: Math.round((root.controlsHeight - 16) * 0.5)
        y: Math.round((root.controlsHeight - 16 - height) / 2)
        color: Theme.separator
    }

    // The phone's volume rocker: one button slot, up on top, down below,
    // holdable; the mouse wheel over it works too (one step per notch -- each keyevent is
    // its own ~0.3s adb round trip, see phone-mirror.sh).
    component VolumeRocker: Item {
        height: root.controlsHeight - 16
        width: Math.min(height * 1.3, root.buttonWidth)
        Column {
            anchors.fill: parent
            Repeater {
                model: [{ glyph: "\u{f075d}", code: 24 }, { glyph: "\u{f075e}", code: 25 }] // nf-md-volume_plus / _minus
                Rectangle {
                    id: half
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: parent.height / 2
                    // Rounded only on the outer corners: one button, split.
                    topLeftRadius: half.index === 0 ? Theme.controlRadius : 0
                    topRightRadius: half.index === 0 ? Theme.controlRadius : 0
                    bottomLeftRadius: half.index === 1 ? Theme.controlRadius : 0
                    bottomRightRadius: half.index === 1 ? Theme.controlRadius : 0
                    color: halfMouse.pressed ? Theme.selectedFill : halfMouse.containsMouse ? Theme.hoverFill : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: half.modelData.glyph
                        font.family: Theme.fontFamily
                        // Nudged toward the middle: the two halves read as one rocker.
                        anchors.verticalCenterOffset: half.index === 0 ? 2 : -2
                        font.pixelSize: Math.round(parent.height * 0.85)
                        color: Theme.text
                    }
                    // Click = one step; hold = repeat until released.
                    MouseArea {
                        id: halfMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        pressAndHoldInterval: 350
                        property bool repeating: false
                        onPressed: repeating = false
                        onPressAndHold: {
                            repeating = true
                            PhoneMirrorState.startKeyRepeat(half.modelData.code)
                        }
                        onReleased: if (repeating) PhoneMirrorState.stopKeyRepeat()
                        onCanceled: if (repeating) PhoneMirrorState.stopKeyRepeat()
                        onClicked: if (!repeating) PhoneMirrorState.key(half.modelData.code)
                    }
                }
            }
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y !== 0) PhoneMirrorState.key(event.angleDelta.y > 0 ? 24 : 25)
            }
        }
    }

    PanelWindow {
        id: placeholder
        screen: root.screen
        visible: PhoneMirrorState.loading && root.here
        color: "transparent"
        // Blurred behind by the "sichos-glass" layer rule, like the OSDs.
        WlrLayershell.namespace: "sichos-glass"
        // Positioned against the whole screen (bar included), same
        // coordinates the script's Hyprland rules use.
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors { top: true; right: !root.left; left: root.left }
        margins.top: Theme.barHeight + root.gap
        margins.right: root.gap
        margins.left: root.gap
        implicitWidth: root.phoneWidth
        implicitHeight: root.phoneHeight

        Squircle {
            id: placeholderCard
            anchors.fill: parent
            radius: Theme.surfaceSquircleRadius
            color: Theme.surfaceFor(placeholder.screen)
            borderColor: Theme.surfaceBorder
            borderWidth: Theme.surfaceBorderWidth

            SurfaceAppear { target: placeholderCard; shown: placeholder.visible; origin: root.left ? Item.Left : Item.Right }

            Column {
                anchors.centerIn: parent
                spacing: Theme.sectionSpacing

                // HeaderIcon centers the glyph's ink in a square box, so it
                // spins around the arrows' middle -- a plain Text spun around
                // its line box, which sits off the ink (Nerd Font glyphs ride
                // the baseline), and wobbled.
                HeaderIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: undefined
                    glyph: "\u{f0453}"  // nf-md-refresh
                    color: Theme.textMuted
                    inkHeight: Theme.fontSize * 1.6
                    width: inkHeight
                    height: inkHeight
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                        running: placeholder.visible
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Connecting to phone…"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textMuted
                }
            }
        }
    }

    // Screen-off cover: while the phone's screen is off the mirror is just
    // black, so this covers it (and catches the click -- unlike the PIN
    // hint, whose clicks must reach the phone) with a "click to wake" card.
    PanelWindow {
        id: wakeCover
        screen: root.screen
        visible: PhoneMirrorState.screenOff && !PhoneMirrorState.pinPad && !PhoneMirrorState.unlocking
            && PhoneMirrorState.open && !PhoneMirrorState.collapsed && root.here
        color: "transparent"
        WlrLayershell.namespace: "sichos-glass"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors { top: true; right: !root.left; left: root.left }
        margins.top: Theme.barHeight + root.gap
        margins.right: root.gap
        margins.left: root.gap
        implicitWidth: root.phoneWidth
        implicitHeight: root.phoneHeight

        MouseArea {
            id: wakeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PhoneMirrorState.wake()
        }

        Squircle {
            id: wakeCard
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.surfacePadding * 2, wakeCol.implicitWidth + Theme.surfacePadding * 2)
            height: wakeCol.implicitHeight + Theme.surfacePadding * 2
            radius: Theme.surfaceSquircleRadius
            color: wakeMouse.containsMouse ? Theme.surfaceRaisedFor(wakeCover.screen) : Theme.surfaceFor(wakeCover.screen)
            borderColor: Theme.surfaceBorder
            borderWidth: Theme.surfaceBorderWidth

            SurfaceAppear { target: wakeCard; shown: wakeCover.visible }

            Column {
                id: wakeCol
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f0425}"  // nf-md-power
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 2
                    color: Theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Screen is off"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Click to wake"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                    color: Theme.textMuted
                }
            }
        }
    }

    // Lock-screen cover: while phone-mirror.sh's wake loop is unlocking the
    // phone (PhoneMirrorState.unlocking), the whole phone is covered so the
    // lock screen never shows in the mirror -- the screen appears only once
    // it's unlocked. Opaque (the glass surface let the lock screen show
    // through) and click-catching, unlike the PIN hint. Same shape as the
    // scrcpy window (rounding 14 / power 3 there; the squircle at the surface
    // radius matches it) and its 1px border.
    //
    // While locked, four PIN dots fill one after another; once unlocked the
    // lock pops open and the cover slides up off the phone, revealing it
    // underneath (the window stays mapped until that's done). If the PIN pad
    // takes over instead (no saved PIN, or it was rejected), it just hides.
    PanelWindow {
        id: lockCover
        screen: root.screen
        readonly property bool wanted: PhoneMirrorState.unlocking && !PhoneMirrorState.pinPad
            && PhoneMirrorState.open && !PhoneMirrorState.collapsed && root.here
        property bool opening: false
        visible: lockCover.wanted || lockCover.opening
        onWantedChanged: {
            if (lockCover.wanted) {
                openAnim.stop()
                lockCover.opening = false
                coverCard.y = 0
                coverCard.opacity = 1
                lockIcon.scale = 1
            } else if (!PhoneMirrorState.unlocking && !PhoneMirrorState.pinPad
                       && PhoneMirrorState.open && !PhoneMirrorState.collapsed) {
                // Unlocked: play the reveal instead of vanishing.
                lockCover.opening = true
                openAnim.restart()
            }
        }
        color: "transparent"
        WlrLayershell.namespace: "sichos-glass"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors { top: true; right: !root.left; left: root.left }
        margins.top: Theme.barHeight + root.gap
        margins.right: root.gap
        margins.left: root.gap
        implicitWidth: root.phoneWidth
        implicitHeight: root.phoneHeight
        // Clicks pass to the phone again as soon as the reveal starts.
        mask: Region { item: lockCover.opening ? null : coverCard }

        Item {
            anchors.fill: parent
            clip: true

            Squircle {
                id: coverCard
                width: parent.width
                height: parent.height
                radius: Theme.surfaceSquircleRadius
                color: Theme.surface
                borderColor: Theme.surfaceBorder
                borderWidth: Theme.surfaceBorderWidth

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.sectionSpacing

                    HeaderIcon {
                        id: lockIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: undefined
                        glyph: lockCover.opening ? "\u{f033f}" : "\u{f033e}"  // lock-open / lock
                        color: lockCover.opening ? Theme.success : Theme.text
                        inkHeight: Theme.fontSize * 2.4
                        width: inkHeight
                        height: inkHeight
                        // A gentle bob while it works on the PIN (a Translate:
                        // the Column owns y).
                        transform: Translate { id: bob }
                        SequentialAnimation {
                            running: lockCover.wanted
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) bob.y = 0
                            NumberAnimation { target: bob; property: "y"; from: 0; to: -4; duration: 450; easing.type: Easing.InOutSine }
                            NumberAnimation { target: bob; property: "y"; from: -4; to: 0; duration: 450; easing.type: Easing.InOutSine }
                        }
                    }
                    Row {
                        id: pinDots
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        // 0..4 dots filled, stepping while locked; all four
                        // on unlock.
                        property int filled: 0
                        Timer {
                            running: lockCover.wanted
                            repeat: true
                            interval: 140
                            onTriggered: pinDots.filled = (pinDots.filled + 1) % 6
                            onRunningChanged: if (running) pinDots.filled = 0
                        }
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                width: 8; height: 8; radius: 4
                                readonly property bool on: lockCover.opening || index < pinDots.filled
                                color: on ? (lockCover.opening ? Theme.success : Theme.text) : "transparent"
                                border.width: 1
                                border.color: lockCover.opening ? Theme.success : Theme.textMuted
                                scale: on ? 1 : 0.8
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: lockCover.opening ? "Unlocked" : PhoneMirrorState.pinSaved ? "Unlocking…" : "Waking…"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }
        }

        SequentialAnimation {
            id: openAnim
            // Pop: the open lock overshoots a little and settles.
            NumberAnimation { target: lockIcon; property: "scale"; from: 1; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: lockIcon; property: "scale"; to: 1; duration: 110; easing.type: Easing.OutBack }
            // Then the cover lifts away like a curtain. Same curve as the
            // phone window's own slides (easeOutQuint).
            ParallelAnimation {
                NumberAnimation {
                    target: coverCard; property: "y"; to: -lockCover.height; duration: 320
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
                }
                NumberAnimation { target: coverCard; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InQuad }
            }
            ScriptAction { script: lockCover.opening = false }
        }
    }

    // "Type your PIN" hint over the middle of the phone while its PIN pad is
    // up -- Android hides the pad from mirroring, so the window is just
    // black there. It takes the keyboard (exclusive) while shown, so it can
    // count digits as dots and relay them (PhoneMirrorState.pinDigit etc.);
    // the pointer still passes through (the mask is only the "Remember"
    // checkbox), so it can never eat a tap meant for the phone.
    PanelWindow {
        id: pinHint
        screen: root.screen
        visible: PhoneMirrorState.pinPad && PhoneMirrorState.open && !PhoneMirrorState.collapsed && root.here
        color: "transparent"
        WlrLayershell.namespace: "sichos-glass"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors { top: true; right: !root.left; left: root.left }
        margins.top: Theme.barHeight + root.gap
        margins.right: root.gap
        margins.left: root.gap
        implicitWidth: root.phoneWidth
        implicitHeight: root.phoneHeight
        mask: Region { item: rememberBox }
        WlrLayershell.keyboardFocus: pinHint.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: (event) => {
                if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
                    PhoneMirrorState.pinDigit(event.key - Qt.Key_0)
                else if (event.key === Qt.Key_Backspace)
                    PhoneMirrorState.pinBackspace()
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    PhoneMirrorState.pinEnter()
                event.accepted = true
            }
        }

        Squircle {
            id: pinCard
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.surfacePadding * 2, pinCol.implicitWidth + Theme.surfacePadding * 2)
            height: pinCol.implicitHeight + Theme.surfacePadding * 2
            radius: Theme.surfaceSquircleRadius
            color: Theme.surfaceFor(pinHint.screen)
            borderColor: Theme.surfaceBorder
            borderWidth: Theme.surfaceBorderWidth

            SurfaceAppear { target: pinCard; shown: pinHint.visible }

            Column {
                id: pinCol
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f033e}"  // nf-md-lock
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 2
                    color: Theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Type your PIN, then press Enter"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: PhoneMirrorState.pinLength === 0
                    text: PhoneMirrorState.pinRejected ? "The saved PIN didn't work and was forgotten"
                        : "The PIN pad is hidden from mirroring"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                    color: Theme.textMuted
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: PhoneMirrorState.pinLength > 0
                    height: Theme.fontSize - 3
                    spacing: 6
                    Repeater {
                        model: PhoneMirrorState.pinLength
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Theme.text
                        }
                    }
                }
                // Saves the PIN (only once it unlocks the phone); from then
                // on the mirror unlocks by itself.
                Item {
                    id: rememberBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: rememberText.implicitWidth
                    height: rememberText.implicitHeight + 4
                    Text {
                        id: rememberText
                        anchors.bottom: parent.bottom
                        text: (PhoneMirrorState.rememberPin ? "\u{f0132}  " : "\u{f0131}  ") + "Remember on this PC"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: rememberArea.containsMouse || PhoneMirrorState.rememberPin ? Theme.text : Theme.textMuted
                    }
                    MouseArea {
                        id: rememberArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PhoneMirrorState.rememberPin = !PhoneMirrorState.rememberPin
                    }
                }
            }
        }
    }

    // Controls card. The window spans from the card's docked spot to the
    // screen edge, so the card can slide out past the edge in step with the
    // phone window on collapse (and back in on expand/open) and simply be
    // cut off by the surface bounds; the window unmaps once it's fully out.
    PanelWindow {
        id: controls
        screen: root.screen
        readonly property bool shown: PhoneMirrorState.open && !PhoneMirrorState.collapsed && root.here
        // 0 = docked, 1 = fully slid out past the screen edge. Same curve
        // and duration as the phone window's own slide (phone-mirror.sh's
        // SMOOTH_MOVE: easeOutQuint over 320ms), so the two move together.
        property real slide: controls.shown ? 0 : 1
        Behavior on slide {
            NumberAnimation {
                duration: root.slideDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
            }
        }
        visible: controls.shown || controls.slide < 1
        color: "transparent"
        WlrLayershell.namespace: "sichos-glass"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true; right: !root.left; left: root.left }
        margins.bottom: root.gap
        implicitWidth: root.phoneWidth + root.gap
        implicitHeight: root.controlsHeight

        Squircle {
            id: controlsCard
            width: root.phoneWidth
            height: parent.height
            x: root.left ? root.gap - controls.slide * controls.width
                         : controls.slide * controls.width
            radius: Theme.surfaceSquircleRadius
            color: Theme.surfaceFor(controls.screen)
            borderColor: Theme.surfaceBorder
            borderWidth: Theme.surfaceBorderWidth

            Row {
                id: leftGroup
                anchors { left: parent.left; leftMargin: (parent.height - height) / 2; verticalCenter: parent.verticalCenter }
                spacing: 4
                // The outermost buttons trade places with the side: collapse
                // always sits at the screen edge it collapses into, the
                // side swap (nf-md-swap_horizontal) at the opposite end.
                ControlButton {
                    glyph: root.left ? "\u{f0141}" : "\u{f04e1}"  // nf-md-chevron_left / swap
                    onActivated: root.left ? PhoneMirrorState.collapse() : PhoneMirrorState.toggleSide()
                }
                ControlButton {
                    // nf-md-volume_high / nf-md-volume_off
                    glyph: PhoneMirrorState.audio ? "\u{f057e}" : "\u{f0581}"
                    active: PhoneMirrorState.audio
                    onActivated: PhoneMirrorState.setAudio(!PhoneMirrorState.audio)
                }
            }
            Row {
                id: centerGroup
                anchors.centerIn: parent
                spacing: 4
                VolumeRocker {}
                Divider {}
                ControlButton { glyph: "\u{f004d}"; onActivated: PhoneMirrorState.key(4) }    // back
                ControlButton { glyph: "\u{f0766}"; onActivated: PhoneMirrorState.key(3) }    // home
                ControlButton { glyph: "\u{f0763}"; onActivated: PhoneMirrorState.key(187) }  // recents
                Divider {}
                ControlButton {
                    glyph: "\u{f0425}"  // nf-md-power
                    holdable: true
                    onActivated: PhoneMirrorState.key(26)  // screen on/off
                    onHeld: PhoneMirrorState.key(26, true) // power menu
                }
            }
            // Dividers between the side groups and the centre one, halfway
            // across whatever gap the card's width leaves.
            Divider {
                x: Math.round((leftGroup.x + leftGroup.width + centerGroup.x) / 2)
                y: Math.round((parent.height - height) / 2)
            }
            Divider {
                x: Math.round((centerGroup.x + centerGroup.width + rightGroup.x) / 2)
                y: Math.round((parent.height - height) / 2)
            }
            Row {
                id: rightGroup
                anchors { right: parent.right; rightMargin: (parent.height - height) / 2; verticalCenter: parent.verticalCenter }
                spacing: 4
                ControlButton {
                    glyph: "\u{f0156}"  // nf-md-close
                    onActivated: PhoneMirrorState.close()
                }
                ControlButton {
                    glyph: root.left ? "\u{f04e1}" : "\u{f0142}"  // swap / nf-md-chevron_right
                    onActivated: root.left ? PhoneMirrorState.toggleSide() : PhoneMirrorState.collapse()
                }
            }
        }
    }

    // Collapsed tab: a thin strip on the screen edge at the controls card's
    // height and position. Slides in once the window has slid away, and out
    // immediately on expand. The card is wider than the window by its
    // radius so only its inner corners are rounded -- the outer ones sit
    // past the screen edge.
    PanelWindow {
        id: tab
        screen: root.screen
        readonly property bool wanted: PhoneMirrorState.open && PhoneMirrorState.collapsed && root.here
        property bool shown: false
        onWantedChanged: {
            if (tab.wanted) tabDelay.restart()
            else { tabDelay.stop(); tab.shown = false }
        }
        Timer {
            id: tabDelay
            interval: root.slideDuration - 100
            onTriggered: tab.shown = true
        }
        property real slide: tab.shown ? 0 : 1
        Behavior on slide {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        visible: tab.shown || tab.slide < 1
        color: "transparent"
        WlrLayershell.namespace: "sichos-glass"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true; right: !root.left; left: root.left }
        margins.bottom: root.gap
        implicitWidth: root.tabWidth
        implicitHeight: root.controlsHeight

        Squircle {
            id: tabCard
            width: root.tabWidth + radius
            height: parent.height
            x: root.left ? -radius - tab.slide * root.tabWidth : tab.slide * root.tabWidth
            radius: Math.min(Theme.surfaceSquircleRadius, root.tabWidth)
            color: tabMouse.containsMouse ? Theme.surfaceRaised : Theme.surfaceFor(tab.screen)
            borderColor: Theme.surfaceBorder
            borderWidth: Theme.surfaceBorderWidth

            Text {
                x: root.left ? tabCard.radius + (root.tabWidth - width) / 2 - 1
                             : (root.tabWidth - width) / 2 + 1
                anchors.verticalCenter: parent.verticalCenter
                // Points inward, the way it expands.
                text: root.left ? "\u{f0142}" : "\u{f0141}"  // nf-md-chevron_right/left
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
                color: tabMouse.containsMouse ? Theme.text : Theme.textMuted
            }
        }
        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: PhoneMirrorState.expand()
        }
    }
}
