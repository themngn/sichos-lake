import QtQuick
import Quickshell

// One notification-history entry as a card, laid out exactly like the live
// toast (Notifications.qml) -- icon + bold summary + close in the header,
// body, then time -- so a notification looks the same before and after it
// lands in history. Used by the hub's notifications column (Hub.qml);
// `activated` is a click on the card (the caller runs
// NotificationHistory.activate and closes itself).
Rectangle {
    id: entryItem
    // A NotificationHistory entry.
    property var entry: ({})
    signal activated()
    // A folded run (count > 1: same app + summary, see
    // NotificationHistory.add()) lists each message's body
    // separately, each with its own close, instead of one body.
    readonly property bool expanded: entryItem.entry.count > 1
    // A phone notification's app (sichlink keeps its icon as
    // <package>.png, see PhoneBadge.qml), for the mute button.
    readonly property string phonePackage: {
        const m = (entryItem.entry.appIcon || "").match(/\/sichlink\/notification-icons\/([^/]+)\.png$/)
        return m ? m[1] : ""
    }
    readonly property bool phoneMuted: entryItem.phonePackage !== ""
        && Sichlink.notifApps.some(a => a.package === entryItem.phonePackage && a.muted)
    height: entryContent.height + 2 * Theme.cardPadding
    color: entryMouse.containsMouse ? Theme.hoverFill : Theme.controlFill
    border.color: Theme.surfaceBorder
    border.width: Theme.surfaceBorderWidth
    radius: Theme.controlRadius

    MouseArea {
        id: entryMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: entryItem.activated()
    }

    Column {
        id: entryContent
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.cardPadding
        }
        spacing: Theme.cardSpacing

        Row {
            id: entryHeader
            width: parent.width
            spacing: 8

            Image {
                id: entryIcon
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.notificationIconSize
                height: Theme.notificationIconSize
                sourceSize.width: width
                sourceSize.height: height
                source: {
                    if (!entryItem.entry.appIcon)
                        return Qt.resolvedUrl("../assets/notification-default.svg")
                    return entryItem.entry.appIcon.startsWith("/")
                        ? "file://" + entryItem.entry.appIcon
                        : Quickshell.iconPath(entryItem.entry.appIcon, true)
                }

                PhoneBadge { appIcon: entryItem.entry.appIcon || "" }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: entryHeader.width - entryIcon.width - closeGlyph.implicitWidth
                    - (countBadge.visible ? countBadge.width + entryHeader.spacing : 0)
                    - (muteGlyph.visible ? muteGlyph.implicitWidth + entryHeader.spacing : 0)
                    - 2 * entryHeader.spacing
                text: entryItem.entry.summary
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
            }

            // How many messages are folded into this entry.
            Rectangle {
                id: countBadge
                visible: entryItem.expanded
                anchors.verticalCenter: parent.verticalCenter
                height: countNumber.implicitHeight + 2
                width: Math.max(height, countNumber.implicitWidth + 10)
                radius: height / 2
                color: Theme.accent

                Text {
                    id: countNumber
                    anchors.centerIn: parent
                    // "" + ...: a single (never folded) entry has
                    // no `count` field at all (NotificationHistory.add()
                    // only sets one on the folded path) -- this Text
                    // still binds (and warns "Unable to assign
                    // undefined to QString" without the concat) even
                    // though the badge stays invisible for it.
                    text: "" + entryItem.entry.count
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                    color: Theme.textOnLight
                }
            }

            // Phone notifications: stop (or resume) this app's
            // notifications coming from the phone -- the phone's own
            // list, the same one its app and the Phone page edit.
            Text {
                id: muteGlyph
                visible: entryItem.phonePackage !== "" && !!Sichlink.phone
                anchors.verticalCenter: parent.verticalCenter
                text: entryItem.phoneMuted ? "\u{f009a}" : "\u{f009b}" // nf-md-bell / bell_off
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                color: muteArea.containsMouse ? Theme.text : Theme.textDim

                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Sichlink.muteApp(entryItem.phonePackage, !entryItem.phoneMuted)
                }
            }

            Text {
                id: closeGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                color: closeArea.containsMouse ? Theme.text : Theme.textDim

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onClicked: NotificationHistory.remove(entryItem.entry.id)
                }
            }
        }

        Text {
            visible: !entryItem.expanded && entryItem.entry.body.length > 0
            width: parent.width
            text: entryItem.entry.body
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            // No elide on top of maximumLineCount -- see the
            // same Text in Notifications.qml for why.
            maximumLineCount: 4
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.textMuted
        }

        Column {
            visible: entryItem.expanded && entryItem.entry.bodies !== undefined
            width: parent.width
            spacing: Theme.cardSpacing

            Repeater {
                model: entryItem.entry.bodies || []
                delegate: Row {
                    id: messageItem
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width - msgCloseGlyph.implicitWidth - parent.spacing
                        text: messageItem.modelData.body
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                    }

                    Text {
                        id: msgCloseGlyph
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: msgCloseArea.containsMouse ? Theme.text : Theme.textDim

                        MouseArea {
                            id: msgCloseArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            onClicked: NotificationHistory.removeMessage(entryItem.entry.id, messageItem.index)
                        }
                    }
                }
            }
        }

        Text {
            text: Qt.formatDateTime(new Date(entryItem.expanded
                ? entryItem.entry.bodies[0].time
                : entryItem.entry.time), "MMM d, HH:mm")
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
            color: Theme.textDim
        }
    }
}
