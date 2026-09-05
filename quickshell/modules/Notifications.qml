import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Native notification popups. This project doesn't run a separate
// notification daemon (mako/dunst/swaync) — quickshell claims
// org.freedesktop.Notifications directly via NotificationServer and renders
// its own toasts here, consistent with the bar/launcher/OSDs already being
// quickshell-native rather than external processes.
PanelWindow {
    id: root

    screen: Quickshell.screens[0]
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        right: true
    }
    margins {
        top: Theme.barHeight + 10
        right: 10
    }

    implicitWidth: 340
    implicitHeight: column.height
    // Always true, not `column.height > 0`: an empty Column is already
    // zero-height and invisible, but gating visible on that binding meant
    // the window's actual layer-shell surface never grew past its initial
    // (empty) size when the first notification arrived — toggling visible
    // false-to-true doesn't retrigger a wlr-layer-shell resize the way
    // implicitHeight changing on an already-visible surface does.
    visible: true

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        actionsSupported: true
        onNotification: notification => {
            notification.tracked = true
            // Not notification.image: for a sender like Telegram that's
            // often an "image://qsimage/<id>/<gen>" reference into
            // Quickshell's own in-process image cache, valid only while
            // the live Notification object exists — persisted into
            // history, it's already a broken image the moment this
            // notification itself closes, let alone after a restart.
            NotificationHistory.add({
                notifId: notification.id,
                time: Date.now(),
                appName: notification.appName,
                appIcon: notification.appIcon,
                summary: notification.summary,
                body: notification.body,
                urgency: notification.urgency
            })
            // Connected here rather than from the toast popup delegate
            // below: that delegate only exists while the toast is on
            // screen, so a Connections{} living inside it depends on
            // Repeater's (asynchronous) delegate instantiation racing the
            // sender's D-Bus CloseNotification call. Connecting directly
            // on the notification object itself, in the same tick it
            // arrives, ties the listener to its actual D-Bus lifetime
            // instead of to how long its popup happens to be rendered.
            // Note this only ever catches a real sender-initiated
            // withdrawal while the notification is still open — once our
            // own expireTimer below calls notification.expire(), the id
            // is dead server-side (confirmed live) and a subsequent
            // CloseNotification for it is a no-op in any compliant
            // daemon, not just this one; that case is unfixable here.
            notification.closed.connect(reason => {
                if (reason === NotificationCloseReason.CloseRequested)
                    NotificationHistory.removeByNotifId(notification.id)
            })
        }
    }

    // Default display time (ms) for a notification that doesn't set its own
    // expireTimeout (-1, "use daemon default"). expireTimeout === 0 always
    // means "don't auto-close" regardless of urgency (handled where the
    // per-toast Timer is set up below), and Critical gets the same
    // treatment here — most desktop notification daemons leave critical
    // alerts up until the user dismisses them.
    function defaultTimeout(notification) {
        if (notification.urgency === NotificationUrgency.Critical) return 0
        if (notification.urgency === NotificationUrgency.Low) return 3000
        return 5000
    }

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: server.trackedNotifications

            delegate: Rectangle {
                id: toast
                required property var modelData
                readonly property var notification: modelData
                readonly property bool critical: notification.urgency === NotificationUrgency.Critical
                readonly property real timeout: notification.expireTimeout > 0
                    ? notification.expireTimeout : root.defaultTimeout(notification)
                // The spec's "default" action (activated by clicking the
                // notification itself, e.g. Claude Code's "bring the
                // terminal to front") is meant to never appear as its own
                // button — excluded by id regardless of what label it
                // carries, since Claude Code's own still showed up as an
                // empty box even after filtering purely on blank text.
                // Anything else with a blank/whitespace-only label is
                // filtered the same way for any other sender doing this.
                readonly property var visibleActions: notification.actions.filter(
                    a => a.identifier !== "default" && a.text.trim().length > 0)

                width: column.width
                height: content.height + 20
                color: Theme.background
                border.color: critical ? Theme.critical : Theme.accent
                border.width: 2

                // No onClosed -> tracked = false handler here: the server
                // already drops a closed notification (expired, dismissed,
                // CloseNotification over the bus, replaced by a same-id one)
                // out of trackedNotifications on its own. Setting tracked
                // false from inside that same closed signal reenters the
                // server while it's still tearing the notification down and
                // reliably crashed the scene graph with a JS "Maximum call
                // stack size exceeded" the moment any toast closed.
                Timer {
                    id: expireTimer
                    running: toast.timeout > 0
                    interval: toast.timeout
                    onTriggered: notification.expire()
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: expireTimer.stop()
                    onExited: { if (toast.timeout > 0) expireTimer.restart() }
                    onClicked: {
                        const defaultAction = notification.actions.find(a => a.identifier === "default")
                        if (defaultAction) defaultAction.invoke()
                        notification.dismiss()
                    }
                }

                Column {
                    id: content
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 10
                    }
                    spacing: 6

                    Row {
                        id: headerRow
                        width: parent.width
                        spacing: 8

                        Image {
                            id: appIcon
                            visible: source !== ""
                            width: visible ? 22 : 0
                            height: 22
                            source: {
                                if (notification.image) return notification.image
                                if (!notification.appIcon) return ""
                                return notification.appIcon.startsWith("/")
                                    ? "file://" + notification.appIcon
                                    : Quickshell.iconPath(notification.appIcon, true)
                            }
                        }

                        Text {
                            width: headerRow.width - (appIcon.visible ? appIcon.width + headerRow.spacing : 0)
                            text: notification.summary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        visible: notification.body.length > 0
                        width: parent.width
                        text: notification.body
                        // No `elide` on top of maximumLineCount here — that
                        // combination on a StyledText item is a known source
                        // of pathological Qt layout behavior with rich-text
                        // bodies (e.g. an <a href>). maximumLineCount alone
                        // still caps a runaway body, just without a "…".
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textMuted
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }

                    Row {
                        visible: toast.visibleActions.length > 0
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: toast.visibleActions
                            delegate: Rectangle {
                                id: actionButton
                                required property var modelData
                                width: actionText.implicitWidth + 16
                                height: actionText.implicitHeight + 8
                                color: Qt.rgba(1, 1, 1, 0.08)
                                border.color: Theme.accent
                                border.width: 1

                                Text {
                                    id: actionText
                                    anchors.centerIn: parent
                                    text: actionButton.modelData.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    color: Theme.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: actionButton.modelData.invoke()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
