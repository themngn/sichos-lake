import QtQuick

// Small phone badge on a notification icon's corner (like the launcher's on
// phone apps): marks a notification the sichlink daemon synced from the phone,
// so it isn't mistaken for the same app's notification on this PC (Telegram
// vs. Telegram Desktop look identical otherwise). Put it inside the icon Image.
Rectangle {
    // The daemon passes every phone notification's app icon as a PNG it keeps
    // under ~/.cache/sichlink/notification-icons/ (sichlink's notify.rs), and
    // that path is also what history entries keep -- so it identifies them
    // without a custom hint, and still does after a restart.
    property string appIcon: ""

    visible: appIcon.indexOf("/sichlink/notification-icons/") !== -1
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -3
    anchors.bottomMargin: -3
    width: 12
    height: 12
    radius: 6
    color: Theme.surfaceRaised
    border.width: 1
    border.color: Theme.surface

    HeaderIcon {
        anchors.centerIn: parent
        glyph: "\u{f011c}" // nf-md-cellphone
        inkHeight: 8
        color: Theme.text
    }
}
