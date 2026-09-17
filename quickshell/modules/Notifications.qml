import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Native notification popups. This project doesn't run a separate
// notification daemon (mako/dunst/swaync) — quickshell claims
// org.freedesktop.Notifications directly via NotificationServer and renders
// its own toasts here, consistent with the bar/launcher/OSDs already being
// quickshell-native rather than external processes. One toast per
// notification, stacked newest-at-bottom in arrival order — no folding of
// same-app/summary runs into a single collapsible entry (that's
// NotificationHistory.qml/NotificationCenter.qml's job for the persisted
// history; a burst of live toasts is short-lived enough that stacking them
// plainly reads better than a dropdown affordance on a fast-changing list).
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

    // Real arrival time per notification id, for the toast's own time row
    // (see content's time Text below). Notification itself carries no
    // timestamp -- captured here, in onNotification, rather than in the
    // toast delegate's own Component.onCompleted, so a hot-reload's
    // lastGeneration re-announcement (a new delegate, same id) keeps
    // showing the real original arrival time instead of resetting to
    // whatever moment the reload happened to land on. Never explicitly
    // pruned -- grows by one small int->number entry per notification for
    // the life of the session, negligible even over weeks of uptime, so
    // not worth the complexity of clearing entries out as toasts close.
    property var notificationTimes: ({})

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        actionsSupported: true
        onNotification: notification => {
            notification.tracked = true

            // Real arrival time -- see root.notificationTimes' own comment
            // for why this is captured here rather than per-delegate, and
            // why lastGeneration is excluded (an existing id must keep its
            // original timestamp, not get overwritten on every reload).
            if (!notification.lastGeneration)
                root.notificationTimes[notification.id] = Date.now()

            // lastGeneration notifications are the same still-open
            // notification being re-announced after a hot-reload
            // (NotificationServer.keepOnReload, default true, re-emits
            // everything still tracked so a freshly rebuilt QML tree can
            // resync) — not a new arrival. Re-running add() for it would
            // stamp today's reload time over its real arrival time in the
            // Notification Center every time a file gets saved.
            //
            // transient is the sender explicitly saying this is a
            // throwaway status blip, not worth a persistent record --
            // GNOME and KDE both honor it the same way (popup only, never
            // logged). Still gets a toast below like anything else; only
            // the history entry is skipped.
            if (!notification.lastGeneration && !notification.transient) {
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
            }

            // Gives the sender a real window to withdraw this notification
            // (D-Bus CloseNotification — e.g. Telegram closing a message
            // notification once it's read in the app) even after its toast
            // has visually disappeared. Skipped for Critical, which never
            // auto-hides in the first place (see defaultTimeout below) and
            // so has no need of a backstop. Rooted on `root`, not the toast
            // delegate below: that delegate is destroyed the moment the
            // toast hides (or on any hot-reload), which would silently
            // cancel the grace period along with it.
            const graceTimer = notification.urgency !== NotificationUrgency.Critical
                ? graceTimerComponent.createObject(root, { notification })
                : null

            // Connected here rather than from the toast popup delegate
            // below: that delegate only exists while the toast is on
            // screen, so a Connections{} living inside it depends on
            // Repeater's (asynchronous) delegate instantiation racing the
            // sender's D-Bus CloseNotification call. Connecting directly
            // on the notification object itself, in the same tick it
            // arrives, ties the listener to its actual D-Bus lifetime
            // instead of to how long its popup happens to be rendered.
            // This is reconnected on every re-emission (including
            // lastGeneration ones) since a hot-reload tears down this
            // whole PanelWindow, and with it whatever was connected here
            // before — without reconnecting, a real withdrawal arriving
            // after even one save-triggered reload would go unnoticed.
            notification.closed.connect(reason => {
                if (reason === NotificationCloseReason.CloseRequested)
                    NotificationHistory.removeByNotifId(notification.id)
                if (graceTimer) graceTimer.destroy()
            })
        }
    }

    // See the onNotification comment above for why this exists instead of
    // just calling notification.expire() from the toast's own hide timer.
    Component {
        id: graceTimerComponent
        Timer {
            id: graceTimer
            required property var notification
            // 10 minutes: long enough to plausibly cover "glance at the
            // toast, then open the chat app a bit later and read it",
            // short enough not to accumulate live Notification objects
            // (and their images/actions) indefinitely for the far more
            // common case of a sender that never explicitly withdraws
            // (VPN connect/disconnect, battery, volume, etc.). A real
            // CloseNotification arriving after this fires is still a
            // no-op in any compliant daemon, not just this one -- that
            // residual case is unfixable here, this just shrinks it from
            // "always, past ~5s" to "only past 10 minutes".
            interval: 10 * 60 * 1000
            running: true
            onTriggered: {
                if (notification.tracked) notification.expire()
                destroy()
            }
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
                readonly property double time: root.notificationTimes[notification.id] || Date.now()
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
                // Purely a local display flag now -- see hideTimer below.
                // Defaults to already-hidden for a notification carried
                // over from before a hot-reload (lastGeneration): it's had
                // its on-screen time already (however much of it), and
                // without this every still-open notification would pop
                // back on screen the moment any quickshell file gets saved,
                // since the Repeater rebuilds this delegate from scratch
                // (confirmed live -- with the 3-5s window this used to be
                // too brief to notice, but the grace window in
                // onNotification above keeps notifications open for up to
                // 10 minutes, long enough that hitting a reload while one
                // is still pending is routine, not a corner case).
                //
                // Also starts hidden if do-not-disturb (ShellState.
                // notificationsMuted, the bar's Notification Mute toggle)
                // was on at the moment this toast was created. Deliberately
                // a one-time snapshot via Component.onCompleted below, not
                // a live binding on notificationsMuted -- a live binding
                // would un-hide (pop in) every notification that arrived
                // while muted the instant the toggle is switched back off,
                // which is a much louder surprise than the toggle is meant
                // to produce. History (NotificationHistory.add above) is
                // unaffected either way -- muting only ever skips the toast.
                property bool hidden: notification.lastGeneration
                Component.onCompleted: if (ShellState.notificationsMuted) toast.hidden = true

                width: column.width
                height: content.height + 20
                visible: !toast.hidden
                color: Theme.background
                border.color: critical ? Theme.critical : Theme.accent
                border.width: 3

                // Only ever hides the toast popup -- does not touch the
                // underlying notification (no expire()/dismiss()/tracked
                // write). That's now handled separately by the grace timer
                // in onNotification above, specifically so a real
                // CloseNotification from the sender can still arrive after
                // this toast disappears and be honored. Setting `tracked`
                // false here (the old approach) is equivalent to
                // dismiss() (confirmed against quickshell's source) and
                // would retire the id immediately, defeating that.
                Timer {
                    id: hideTimer
                    running: toast.timeout > 0
                    interval: toast.timeout
                    onTriggered: toast.hidden = true
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: hideTimer.stop()
                    onExited: { if (toast.timeout > 0) hideTimer.restart() }
                    // Dismissing here too (as this used to) made an
                    // accidental click on a notification you meant to read
                    // or act on lose it -- closing is now exclusively the
                    // ✕ button below.
                    onClicked: {
                        const defaultAction = notification.actions.find(a => a.identifier === "default")
                        if (defaultAction) defaultAction.invoke()
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
                    spacing: 10

                    Row {
                        id: headerRow
                        width: parent.width
                        spacing: 8

                        Image {
                            id: appIcon
                            visible: source !== ""
                            width: visible ? 22 : 0
                            height: 22
                            // Falls back to a bundled plain-bell asset
                            // (assets/notification-default.svg) rather than
                            // leaving the row icon-less -- senders that skip
                            // both `image` and app_icon hints (e.g. some CLI
                            // notify-send calls) otherwise collapsed this
                            // Image to 0 width and left the summary text
                            // with no visual anchor. Bundled rather than a
                            // system icon-theme lookup: Adwaita's only
                            // notification-shaped icons are a
                            // gear-badged "settings" bell
                            // (preferences-system-notifications-symbolic) or
                            // a slashed "disabled" bell -- neither reads as
                            // a plain notification icon.
                            source: {
                                if (notification.image) return notification.image
                                if (!notification.appIcon)
                                    return Qt.resolvedUrl("../assets/notification-default.svg")
                                return notification.appIcon.startsWith("/")
                                    ? "file://" + notification.appIcon
                                    : Quickshell.iconPath(notification.appIcon, true)
                            }
                        }

                        Text {
                            width: headerRow.width - (appIcon.visible ? appIcon.width + headerRow.spacing : 0)
                                - closeButton.implicitWidth - headerRow.spacing
                            text: notification.summary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.text
                            elide: Text.ElideRight
                        }

                        Text {
                            id: closeButton
                            // Font Awesome "times", same glyph
                            // NotificationCenter.qml's history rows use for
                            // their own close button -- keeps the one
                            // "this ✕ dismisses" affordance visually
                            // consistent between the live toast and history.
                            text: ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            color: Theme.textDim

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                onClicked: notification.dismiss()
                            }
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

                    // Same format/styling as NotificationCenter.qml's history
                    // rows, for the same timestamp on the live toast as it'll
                    // show once it lands in history.
                    Text {
                        text: Qt.formatDateTime(new Date(toast.time), "MMM d, HH:mm")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: Theme.textDim
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
