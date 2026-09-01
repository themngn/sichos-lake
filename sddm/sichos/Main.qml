// SichOS SDDM theme — hand-written from scratch rather than vendoring a
// third-party theme, after the vendored Sugar Candy theme (Qt5-only, `import
// QtGraphicalEffects 1.0`) turned out fundamentally incompatible with
// Fedora's Qt6-only sddm build (only sddm-greeter-qt6 is shipped; Qt5 QML
// plugins cannot load in a Qt6 QQmlEngine, confirmed live via the exact
// "module ... is not installed" error). Built entirely on SddmComponents
// (ships with the base `sddm` package itself) and QtQuick.Effects (ships
// with qt6-qtdeclarative, sddm's own hard Qt6 Quick dependency) — zero
// packages beyond what a bare `sddm` install already requires. API calls
// below (sddm.login/powerOff/reboot, userModel.lastUser, sessionModel,
// Connections{ onLoginSucceeded/onLoginFailed }) are verified against
// upstream SDDM's own reference theme (data/themes/maldives/Main.qml in the
// sddm/sddm repo), not guessed.
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#000000"

    LayoutMirroring.enabled: Qt.locale().textDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    readonly property color accent: "#698b85"
    readonly property color cardBg: "#141c1e"
    readonly property color textMuted: "#b4bbaa"
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"

    property int sessionIndex: sessionBox.index

    TextConstants { id: textConstants }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            errorMessage.color = accent
            errorMessage.text = textConstants.loginSucceeded
        }
        function onLoginFailed() {
            password.text = ""
            errorMessage.color = "#f53c3c"
            errorMessage.text = textConstants.loginFailed
        }
    }

    // Background photo, blurred full-screen (Qt6-native MultiEffect — no
    // GraphicalEffects/qt5compat needed) with a dark scrim for legibility,
    // same DimBackgroundImage-style overlay Launcher.qml itself uses.
    Image {
        id: bg
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    MultiEffect {
        anchors.fill: bg
        source: bg
        blurEnabled: true
        blur: 0.6
        blurMax: 48
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    // Clock, top-right — same "ddd dd  HH:mm" shape as quickshell's own
    // ClockWidget.qml (that one also respects a 12h/24h toggle via a
    // singleton this theme has no access to; hardcoded 24h here).
    Text {
        anchors { top: parent.top; right: parent.right; margins: 24 }
        color: "white"
        font.family: fontFamily
        font.pixelSize: 16
        text: Qt.formatDateTime(clockTimer.now, "ddd dd  HH:mm")
    }
    Timer {
        id: clockTimer
        property date now: new Date()
        interval: 1000; running: true; repeat: true
        onTriggered: now = new Date()
    }

    // Centered card — same solid #1c1c1c surface, 6px radius, accent-icon
    // header pattern as every quickshell bar popup (SunsetPopup/IdlePopup/
    // CalendarPopup/etc.).
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 320
        color: cardBg
        border.color: accent
        border.width: 1
        radius: 6
        height: column.implicitHeight + 48

        Column {
            id: column
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; margins: 24 }
            width: parent.width - 48
            spacing: 14

            Text {
                text: textConstants.welcomeText.arg(sddm.hostName)
                color: "white"
                font.family: fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: textConstants.userName; color: textMuted; font.family: fontFamily; font.pixelSize: 11 }
                TextBox {
                    id: name
                    width: parent.width; height: 32
                    color: "#262626"
                    borderColor: Qt.rgba(1, 1, 1, 0.15)
                    focusColor: accent
                    hoverColor: accent
                    textColor: "white"
                    radius: 6
                    font.family: fontFamily
                    font.pixelSize: 13
                    text: userModel.lastUser
                    KeyNavigation.backtab: rebootButton; KeyNavigation.tab: password
                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(name.text, password.text, sessionIndex)
                            event.accepted = true
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: textConstants.password; color: textMuted; font.family: fontFamily; font.pixelSize: 11 }
                PasswordBox {
                    id: password
                    width: parent.width; height: 32
                    color: "#262626"
                    borderColor: Qt.rgba(1, 1, 1, 0.15)
                    focusColor: accent
                    hoverColor: accent
                    textColor: "white"
                    radius: 6
                    font.family: fontFamily
                    font.pixelSize: 13
                    KeyNavigation.backtab: name; KeyNavigation.tab: loginButton
                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(name.text, password.text, sessionIndex)
                            event.accepted = true
                        }
                    }
                }
            }

            Text {
                id: errorMessage
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: textMuted
                font.family: fontFamily
                font.pixelSize: 11
                text: textConstants.prompt
            }

            Row {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                property int btnWidth: (column.width - 16) / 3

                Button {
                    id: loginButton
                    width: parent.btnWidth; height: 32
                    radius: 6
                    color: accent
                    activeColor: accent
                    pressedColor: "#77a29b"
                    textColor: "white"
                    font.family: fontFamily
                    text: textConstants.login
                    onClicked: sddm.login(name.text, password.text, sessionIndex)
                    KeyNavigation.backtab: password; KeyNavigation.tab: rebootButton
                }
                Button {
                    id: rebootButton
                    width: parent.btnWidth; height: 32
                    radius: 6
                    color: "#262626"
                    activeColor: accent
                    pressedColor: "#77a29b"
                    textColor: "white"
                    font.family: fontFamily
                    text: textConstants.reboot
                    onClicked: sddm.reboot()
                    KeyNavigation.backtab: loginButton; KeyNavigation.tab: shutdownButton
                }
                Button {
                    id: shutdownButton
                    width: parent.btnWidth; height: 32
                    radius: 6
                    color: "#262626"
                    activeColor: "#f53c3c"
                    pressedColor: "#a62020"
                    textColor: "white"
                    font.family: fontFamily
                    text: textConstants.shutdown
                    onClicked: sddm.powerOff()
                    KeyNavigation.backtab: rebootButton; KeyNavigation.tab: name
                }
            }
        }
    }

    // Session picker — bottom-left corner, separate from the login card
    // (the conventional login-screen placement), compact rather than a
    // full labeled field since there's only ever the plain/uwsm Hyprland
    // choice to make. Uses SessionComboBox (this dir), a local fork of
    // SddmComponents' ComboBox with its dropdown flipped to open upward —
    // the stock component's dropdown always opens downward (hardcoded, no
    // config option), which renders off-screen entirely from flush against
    // the bottom edge (confirmed live). See SessionComboBox.qml's own
    // header comment for exactly what changed.
    Row {
        anchors { left: parent.left; bottom: parent.bottom; margins: 24 }
        spacing: 8
        SessionComboBox {
            id: sessionBox
            width: 220; height: 32
            color: "#262626"
            borderColor: Qt.rgba(1, 1, 1, 0.15)
            focusColor: accent
            hoverColor: accent
            menuColor: "#262626"
            textColor: "white"
            font.family: fontFamily
            font.pixelSize: 12
            model: sessionModel
            index: sessionModel.lastIndex
        }
    }

    Component.onCompleted: {
        if (name.text === "")
            name.focus = true
        else
            password.focus = true
    }
}
