import QtQuick
import Quickshell
import Quickshell.Wayland
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
//
// Toasts show on every screen at once: one NotificationServer and one set of
// grouping/visibility state here, drawn by a toast window per screen
// (Variants below). Whether a toast is hidden -- timed out, ✕, clicked,
// muted -- is shared state keyed by notification id (hideToast), so closing
// it on any screen closes it on all of them, and hovering one pauses its
// timer everywhere (hoverToast), so a copy timing out on another screen
// can't pull it out from under the one being read.
Scope {
    id: root

    // Notification ids whose toast has hidden, and how many screens'
    // copies are currently hovered per id. Plain JS maps, so
    // toastRevision is bumped on every change for the delegates' bindings.
    property var hiddenIds: ({})
    property var hoverCounts: ({})
    property int toastRevision: 0

    function isHidden(id) {
        root.toastRevision
        return root.hiddenIds[id] === true
    }
    function isHovered(id) {
        root.toastRevision
        return (root.hoverCounts[id] || 0) > 0
    }
    // The group release used to run from each delegate's onHiddenChanged;
    // with one delegate per screen it runs here, once.
    function hideToast(id) {
        if (root.hiddenIds[id] === true) return
        root.hiddenIds[id] = true
        root.releaseGroup(id)
        root.toastRevision++
    }
    function hoverToast(id, on) {
        root.hoverCounts[id] = Math.max(0, (root.hoverCounts[id] || 0) + (on ? 1 : -1))
        root.toastRevision++
    }
    function forgetToast(id) {
        delete root.hiddenIds[id]
        delete root.hoverCounts[id]
        root.toastRevision++
    }

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

    // Toast grouping: a new notification with the same app + summary +
    // urgency as a toast that's still on screen joins that toast (count
    // badge, its body listed under the earlier ones, hide timer restarted)
    // instead of stacking another near-identical toast -- same idea as
    // NotificationHistory.add()'s folding for the Notification Center, but
    // live and only while the group's toast is actually showing; anything
    // arriving after it hides starts a fresh toast. Every member stays its
    // own tracked Notification (grace timer, withdrawal, history are all
    // untouched) -- grouping only decides which delegate draws it.
    // Plain JS maps, so groupRevision is bumped on every change to make the
    // delegates' bindings re-evaluate.
    property var groupLeader: ({})   // group key -> leader id, only while its toast shows
    property var groupMembers: ({})  // leader id -> [Notification], oldest first
    property var followerOf: ({})    // member id -> leader id (never drawn on its own)
    property int groupRevision: 0

    function groupKey(n) {
        return n.appName + "\n" + n.summary + "\n" + n.urgency
    }

    function joinGroup(n) {
        const key = root.groupKey(n)
        const leaderId = root.groupLeader[key]
        if (leaderId !== undefined && root.groupMembers[leaderId]) {
            root.groupMembers[leaderId].push(n)
            root.followerOf[n.id] = leaderId
        } else {
            root.groupLeader[key] = n.id
            root.groupMembers[n.id] = [n]
        }
        root.groupRevision++
    }

    // The leader's toast hid (timeout, ✕, mute): later arrivals start a new toast.
    function releaseGroup(leaderId) {
        for (const k in root.groupLeader)
            if (root.groupLeader[k] === leaderId) delete root.groupLeader[k]
        root.groupRevision++
    }

    // A member's Notification closed (withdrawn, dismissed, grace expiry).
    function leaveGroup(id) {
        const leaderId = root.followerOf[id]
        if (leaderId !== undefined) {
            // followerOf entry deliberately kept: the delegate is about to
            // go away anyway, and clearing it would flash it on screen.
            if (root.groupMembers[leaderId])
                root.groupMembers[leaderId] = root.groupMembers[leaderId].filter(m => m.id !== id)
        } else if (root.groupMembers[id]) {
            const rest = root.groupMembers[id].filter(m => m.id !== id)
            delete root.groupMembers[id]
            let key
            for (const k in root.groupLeader)
                if (root.groupLeader[k] === id) key = k
            // Leader withdrawn while its toast is still showing (e.g. the
            // sender closed the first message once read): the oldest
            // remaining member takes over the same toast. If the toast
            // already hid, the rest just stay undrawn -- re-showing them
            // here would pop an old message up out of nowhere.
            if (key !== undefined && rest.length > 0) {
                const next = rest[0].id
                root.groupMembers[next] = rest
                delete root.followerOf[next]
                for (const m of rest.slice(1)) root.followerOf[m.id] = next
                root.groupLeader[key] = next
            } else if (key !== undefined) {
                delete root.groupLeader[key]
            }
        }
        root.groupRevision++
    }

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        actionsSupported: true
        onNotification: notification => {
            notification.tracked = true
            NotificationHistory.registerLive(notification)

            // Real arrival time -- see root.notificationTimes' own comment
            // for why this is captured here rather than per-delegate, and
            // why lastGeneration is excluded (an existing id must keep its
            // original timestamp, not get overwritten on every reload).
            if (!notification.lastGeneration) {
                root.notificationTimes[notification.id] = Date.now()
                root.joinGroup(notification)
            }

            // Starts hidden when it's a notification carried over from
            // before a hot-reload (lastGeneration -- it's had its on-screen
            // time already, however much of it; without this every
            // still-open notification would pop back on screen the moment
            // any quickshell file gets saved, since the toast delegates are
            // rebuilt from scratch, and the 10-minute grace window below
            // makes a reload while one is pending routine), or when
            // do-not-disturb (ShellState.notificationsMuted) is on as it
            // arrives. A one-time snapshot, not a live binding on
            // notificationsMuted -- a live binding would pop in every
            // notification that arrived while muted the instant the toggle
            // is switched back off. History (NotificationHistory.add below)
            // is unaffected either way -- muting only ever skips the toast.
            if (notification.lastGeneration || ShellState.notificationsMuted)
                root.hideToast(notification.id)

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
                    // Lets NotificationCenter.qml focus/launch the right app
                    // when clicked after the live notification is gone.
                    desktopEntry: notification.desktopEntry,
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
            // whole toast tree, and with it whatever was connected here
            // before — without reconnecting, a real withdrawal arriving
            // after even one save-triggered reload would go unnoticed.
            const notifId = notification.id
            notification.closed.connect(reason => {
                root.leaveGroup(notifId)
                root.forgetToast(notifId)
                NotificationHistory.unregisterLive(notifId)
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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            // Blurred behind by the "sichos-glass" layer rule (hypr/window_rules.lua).
            WlrLayershell.namespace: "sichos-glass"

            screen: win.modelData
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

            Column {
                id: column
                width: parent.width
                spacing: 8

                Repeater {
                    model: server.trackedNotifications

                    delegate: Squircle {
                        id: toast
                        required property var modelData
                        readonly property var notification: modelData
                        readonly property bool critical: notification.urgency === NotificationUrgency.Critical
                        readonly property real timeout: notification.expireTimeout > 0
                            ? notification.expireTimeout : root.defaultTimeout(notification)
                        // This toast's group (see joinGroup above): itself plus any
                        // later same-app/summary notifications folded into it.
                        // Followers are never drawn -- their leader shows them.
                        readonly property var members: {
                            root.groupRevision
                            // slice(): a fresh array each time, so a push into the
                            // shared one still registers as a change here.
                            return (root.groupMembers[notification.id] || [notification]).slice()
                        }
                        readonly property bool isFollower: {
                            root.groupRevision
                            return root.followerOf[notification.id] !== undefined
                        }
                        // Click / actions / time follow the newest message, the one
                        // the user is most likely reacting to.
                        readonly property var latest: members[members.length - 1]
                        readonly property double time: root.notificationTimes[latest.id] || Date.now()
                        // The spec's "default" action (activated by clicking the
                        // notification itself, e.g. Claude Code's "bring the
                        // terminal to front") is meant to never appear as its own
                        // button — excluded by id regardless of what label it
                        // carries, since Claude Code's own still showed up as an
                        // empty box even after filtering purely on blank text.
                        // Anything else with a blank/whitespace-only label is
                        // filtered the same way for any other sender doing this.
                        readonly property var visibleActions: latest.actions.filter(
                            a => a.identifier !== "default" && a.text.trim().length > 0)
                        // Shared across every screen's copy of this toast -- see
                        // root.hideToast and onNotification's initial-hidden
                        // comment (hot-reload carry-overs, do-not-disturb).
                        readonly property bool hidden: root.isHidden(notification.id)
                        readonly property bool hovered: root.isHovered(notification.id)
                        // A new message joining the group gets the full display time
                        // too. Keyed on this toast's own count growing, not on
                        // `members` changing -- that re-evaluates on every
                        // groupRevision bump, i.e. on any other toast's grouping
                        // change as well.
                        readonly property int memberCount: members.length
                        property int shownCount: 1
                        onMemberCountChanged: {
                            if (memberCount > shownCount && !toast.hidden && !toast.hovered && toast.timeout > 0)
                                hideTimer.restart()
                            shownCount = memberCount
                        }

                        width: column.width
                        height: content.height + 2 * Theme.cardPadding
                        visible: !toast.hidden && !toast.isFollower
                        color: Theme.surfaceFor(win.screen)
                        borderColor: critical ? Theme.critical : Theme.surfaceBorder
                        borderWidth: Theme.surfaceBorderWidth
                        radius: Theme.surfaceSquircleRadius

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
                            // Not while a follower: a member promoted to leader (see
                            // leaveGroup) then starts with its full display time.
                            // Paused while this toast is hovered on any screen;
                            // restarts from its full time when the pointer leaves,
                            // on every screen at once.
                            running: toast.timeout > 0 && !toast.isFollower && !toast.hidden && !toast.hovered
                            interval: toast.timeout
                            onTriggered: root.hideToast(notification.id)
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.hoverToast(notification.id, true)
                            onExited: root.hoverToast(notification.id, false)
                            // Dismissing here too (as this used to) made an
                            // accidental click on a notification you meant to read
                            // or act on lose it -- closing is now exclusively the
                            // ✕ button below.
                            // Like the Notification Center's click: the sender's own
                            // default action, else bring its app up; either way the
                            // toast has done its job, so it hides (the notification
                            // itself stays tracked -- history/withdrawal unaffected).
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const n = toast.latest
                                const defaultAction = n.actions.find(a => a.identifier === "default")
                                if (defaultAction) defaultAction.invoke()
                                else NotificationHistory.focusOrLaunchApp(n.desktopEntry, n.appName)
                                root.hideToast(notification.id)
                            }
                        }

                        Column {
                            id: content
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Theme.cardPadding
                            }
                            spacing: Theme.cardSpacing

                            Row {
                                id: headerRow
                                width: parent.width
                                spacing: 8

                                Image {
                                    id: appIcon
                                    visible: source !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: visible ? Theme.notificationIconSize : 0
                                    height: Theme.notificationIconSize
                                    sourceSize.width: Theme.notificationIconSize
                                    sourceSize.height: Theme.notificationIconSize
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
                                        const n = toast.latest
                                        if (n.image) return n.image
                                        if (!n.appIcon)
                                            return Qt.resolvedUrl("../assets/notification-default.svg")
                                        return n.appIcon.startsWith("/")
                                            ? "file://" + n.appIcon
                                            : Quickshell.iconPath(n.appIcon, true)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: headerRow.width - (appIcon.visible ? appIcon.width + headerRow.spacing : 0)
                                        - closeButton.implicitWidth - headerRow.spacing
                                        - (countBadge.visible ? countBadge.width + headerRow.spacing : 0)
                                    text: notification.summary
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                // How many messages this toast is showing (see joinGroup)
                                // -- same badge as NotificationCenter.qml's folded entries.
                                Rectangle {
                                    id: countBadge
                                    visible: toast.members.length > 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: countNumber.implicitHeight + 2
                                    width: Math.max(height, countNumber.implicitWidth + 10)
                                    radius: height / 2
                                    color: Theme.accent

                                    Text {
                                        id: countNumber
                                        anchors.centerIn: parent
                                        text: "" + toast.members.length
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                        font.bold: true
                                        color: Theme.textOnLight
                                    }
                                }

                                Text {
                                    id: closeButton
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Font Awesome "times", same glyph
                                    // NotificationCenter.qml's history rows use for
                                    // their own close button -- keeps the one
                                    // "this ✕ dismisses" affordance visually
                                    // consistent between the live toast and history.
                                    text: ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    color: closeArea.containsMouse ? Theme.text : Theme.textDim

                                    MouseArea {
                                        id: closeArea
                                        hoverEnabled: true
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        // Whole group: release first so dismissing the
                                        // leader doesn't promote a member back on screen.
                                        onClicked: {
                                            const all = toast.members.slice()
                                            root.releaseGroup(notification.id)
                                            for (const m of all) m.dismiss()
                                        }
                                    }
                                }
                            }

                            // One message: its body, up to 4 lines. A group: the
                            // newest 3 bodies, oldest first, 2 lines each -- enough to
                            // follow a burst of chat messages without the toast
                            // growing without bound; the rest are in the Notification
                            // Center.
                            Repeater {
                                model: toast.members.length > 1 ? toast.members.slice(-3) : []
                                delegate: Text {
                                    required property var modelData
                                    visible: modelData.body.length > 0
                                    width: content.width
                                    text: modelData.body
                                    textFormat: Text.StyledText
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.textMuted
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }

                            Text {
                                visible: toast.members.length === 1 && notification.body.length > 0
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
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textMuted
                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }

                            // Same format/styling as NotificationCenter.qml's history
                            // rows, for the same timestamp on the live toast as it'll
                            // show once it lands in history.
                            Text {
                                text: Qt.formatDateTime(new Date(toast.time), "MMM d, HH:mm")
                                font.family: Theme.uiFontFamily
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
                                        height: Theme.controlHeight
                                        color: actionArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                                        border.color: Theme.surfaceBorder
                                        border.width: 1
                                        radius: Theme.controlRadius

                                        Text {
                                            id: actionText
                                            anchors.centerIn: parent
                                            text: actionButton.modelData.text
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 1
                                            color: Theme.text
                                        }

                                        MouseArea {
                                            id: actionArea
                                            anchors.fill: parent
                                            hoverEnabled: true
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
    }
}
