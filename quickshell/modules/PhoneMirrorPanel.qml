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

    // Matched by eye to Hyprland's `windows` spring (look_and_feel.lua),
    // which the window's own slide uses.
    readonly property int slideDuration: 320

    readonly property int tabWidth: 21

    component ControlButton: Rectangle {
        id: btn
        required property string glyph
        property string tip: ""
        // Toggle buttons (audio): lit while on, like the bar's toggle pills.
        property bool active: false
        signal activated()
        // Scaled with the card (PhoneMirrorState.controlsHeight) rather than
        // Theme.controlHeight: big touch-sized targets, like a phone nav bar.
        height: root.controlsHeight - 16
        width: height * 1.3
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
            onClicked: btn.activated()
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

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f0453}"  // nf-md-refresh
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 2
                    color: Theme.textMuted
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
        visible: PhoneMirrorState.screenOff && !PhoneMirrorState.pinPad
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

    // "Type your PIN" hint over the middle of the phone while its PIN pad is
    // up -- Android hides the pad from mirroring, so the window is just
    // black there. It takes the keyboard (exclusive) while shown, so it can
    // count digits as dots and relay them (PhoneMirrorState.pinDigit etc.);
    // the pointer still passes through (empty mask), so it can never eat a
    // tap meant for the phone.
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
        mask: Region {}
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
                    text: "The PIN pad is hidden from mirroring"
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
        // 0 = docked, 1 = fully slid out past the screen edge.
        property real slide: controls.shown ? 0 : 1
        Behavior on slide {
            NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutCubic }
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
                anchors.centerIn: parent
                spacing: 4
                ControlButton { glyph: "\u{f004d}"; onActivated: PhoneMirrorState.key(4) }    // back
                ControlButton { glyph: "\u{f0766}"; onActivated: PhoneMirrorState.key(3) }    // home
                ControlButton { glyph: "\u{f0763}"; onActivated: PhoneMirrorState.key(187) }  // recents
            }
            Row {
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
