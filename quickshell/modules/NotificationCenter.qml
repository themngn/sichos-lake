import QtQuick
import Quickshell

// Bar bell icon + full-height notification history drawer, styled to match
// Launcher.qml (same dim full-screen overlay + click-outside-to-close +
// flat Theme.background/Theme.accent box) rather than the small rounded
// dropdown popups the other bar widgets use — docked to the right edge
// instead of centered, and full height instead of a fixed box size.
Pill {
    id: root

    // Set by Bar.qml to this instance's own screen/name, same pattern as
    // Weather/AiModelUsage/BluetoothIndicator -- `screen` is what the
    // PanelWindow below actually renders on, `screenName` is just the
    // string key ShellState.notificationCenterScreen compares against.
    property var screen: null
    property string screenName: ""

    readonly property int count: NotificationHistory.entries.length
    readonly property bool panelOpen: ShellState.notificationCenterScreen === root.screenName

    tooltipText: root.count > 0 ? root.count + " notification" + (root.count === 1 ? "" : "s") : "No notifications"
    onClicked: ShellState.notificationCenterScreen = root.panelOpen ? "" : root.screenName

    // Ink heights (fontTools glyf bbox, units/1000em): bell-badge 700,
    // plain bell 684 -- close enough that a shared correction covers both,
    // but kept per-state so a future glyph swap doesn't silently drift.
    function iconInkUnits() {
        return root.count > 0 ? 700 : 684
    }

    BarIcon {
        // Presence-only indicator (no count) — a number badge kept
        // leaving an awkward fixed-width gap when empty; the glyph
        // switch (plain bell -> bell-badge) plus accent color together
        // say "there's something to see" instead.
        glyph: root.count > 0 ? "󱅫" : ""
        pixelSize: Theme.barIconInkHeight * 1000 / root.iconInkUnits()
        color: root.count > 0 ? Theme.accent : Theme.text
    }

    PanelWindow {
        id: panel

        screen: root.screen
        visible: root.panelOpen
        focusable: true
        color: Qt.rgba(0, 0, 0, 0.35)

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: ShellState.notificationCenterScreen = ""
        }

        Rectangle {
            id: box
            width: 380
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Theme.background
            border.color: Theme.accent
            border.width: 4
            radius: 0

            // Swallows clicks so they don't fall through to the outer
            // click-to-close MouseArea.
            MouseArea { anchors.fill: parent }

            Column {
                id: inner
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10

                Row {
                    width: parent.width
                    height: 25

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "[ Notifications ]"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        visible: root.count > 0
                        text: "Clear All"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.accent

                        MouseArea { anchors.fill: parent; onClicked: NotificationHistory.clear() }
                    }
                }

                Text {
                    visible: root.count === 0
                    text: "No notifications"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textDim
                }

                ListView {
                    id: list
                    visible: root.count > 0
                    width: parent.width
                    height: parent.height - 35
                    clip: true
                    // NotificationHistory.entries is newest-first (add()
                    // unshifts) -- that order is load-bearing there (its
                    // burst-merge check reads entries[0] as "the most
                    // recent"). Rendering direction is independent of that:
                    // TopToBottom (the default) puts index 0 (newest) at the
                    // top with older entries stacked downward below it --
                    // folding is unaffected either way since it keys off the
                    // model's entries[0], not how the ListView paints it.
                    verticalLayoutDirection: ListView.TopToBottom
                    model: NotificationHistory.entries

                    delegate: Rectangle {
                        id: entryItem
                        required property var modelData
                        // Only entries folded by NotificationHistory.add()
                        // (count > 1) have anything to expand into -- a
                        // single-message entry's click is a no-op, only its
                        // ✕ (closeGlyph below) dismisses it.
                        property bool expanded: false
                        width: list.width
                        // 14 top (was 10 -- title/description read as too
                        // close to the top edge, especially with countBadge
                        // sitting right there too) + 10 bottom.
                        height: entryContent.height + 24
                        color: entryMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : "transparent"
                        radius: 0

                        // Width tied to box.border.width, not a matching
                        // literal, so "same width as the panel border" can't
                        // silently drift out of sync with it. entryItem sits
                        // at inner's own 15px inset (unchanged, same as the
                        // header above it), so a small leftMargin here
                        // (one border-width) still reads as a real gap of
                        // inner.anchors.leftMargin from the true panel
                        // border -- (inner.leftMargin + border.width) -
                        // border.width = inner.leftMargin exactly. Grown to
                        // match that bigger gap (see bar2/entryContent
                        // below) rather than shrinking it to match a small
                        // bar-to-bar gap -- pulling the whole list in flush
                        // against the border looked worse.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: box.border.width
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: box.border.width
                            color: Theme.accent
                        }

                        // Second, inner accent bar for a folded (count > 1)
                        // entry, hanging from countBadge's own bottom edge
                        // (below, not above it) down to the entry's bottom --
                        // same "more folded below this" / thread-connector
                        // look as the live toast's own second bar in
                        // Notifications.qml. leftMargin is bar1's own
                        // (border.width) + its width + the same
                        // inner.anchors.leftMargin gap bar1 has from the
                        // border, so this gap matches that one instead of
                        // the other way around.
                        Rectangle {
                            id: line2
                            visible: entryItem.modelData.count > 1
                            anchors.left: parent.left
                            anchors.leftMargin: box.border.width * 2 + inner.anchors.leftMargin
                            anchors.top: countBadge.bottom
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            width: box.border.width
                            color: Theme.accent
                        }

                        // Count/dropdown-state badge for a folded entry -- a
                        // square vertically centered on entryHeader (the
                        // title row), so title and badge read as the same
                        // row, with line2 (above) hanging from its bottom
                        // edge down into the body -- same "more folded below
                        // this" look as the live toast's own badge in
                        // Notifications.qml. Can't anchor straight to
                        // entryHeader.verticalCenter -- it's entryContent's
                        // child, not this Rectangle's parent/sibling, and
                        // QtQuick anchoring only allows those two (see
                        // Notifications.qml's own line2 comment for the same
                        // restriction). entryContent's 14px topMargin +
                        // half the header/badge height difference gets the
                        // same centered result via plain height reference
                        // instead, which has no such restriction.
                        Rectangle {
                            id: countBadge
                            visible: entryItem.modelData.count > 1
                            anchors.left: parent.left
                            anchors.leftMargin: line2.anchors.leftMargin
                            anchors.top: parent.top
                            anchors.topMargin: 14 + (entryHeader.height - countBadge.height) / 2
                            // Square: both sides sized to whichever of
                            // countNumber's width/height is larger, so the
                            // content (never square itself for double-digit
                            // counts) still fits without clipping instead
                            // of a squashed fit.
                            width: Math.max(countNumber.width, countNumber.height) + 8
                            height: width
                            radius: 0
                            color: Theme.accent

                            Text {
                                id: countNumber
                                anchors.centerIn: parent
                                // "" + ...: a single (never folded) entry
                                // has no `count` field at all
                                // (NotificationHistory.add() only sets one
                                // on the folded path) -- this Text still
                                // binds (and warns "Unable to assign
                                // undefined to QString" without the concat)
                                // even though the badge stays invisible for it.
                                text: "" + entryItem.modelData.count
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                font.bold: true
                                color: Theme.background
                            }
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            // Dismissing a single entry on any click here
                            // (the old behavior) meant an accidental click
                            // while just skimming history lost that record
                            // permanently -- closing is now exclusively the
                            // ✕ (closeGlyph) below, same as the live toast
                            // in Notifications.qml. A multi entry still uses
                            // the click as its expand/collapse toggle.
                            onClicked: {
                                if (entryItem.modelData.count > 1) entryItem.expanded = !entryItem.expanded
                            }
                        }

                        Column {
                            id: entryContent
                            anchors {
                                left: parent.left
                                // Multi (count > 1): countBadge's own right
                                // edge (x + width, not a fixed guess -- its
                                // width varies with the digit count and this
                                // needs to clear it whether the run is "3" or
                                // "15") + a 6px gap, so the header/body/time
                                // this margin positions (all of them, not
                                // just the header row) actually clear the
                                // badge instead of sitting under/behind it.
                                // Single: no bar2/badge to leave room for, so
                                // just bar1's leftMargin + its width + one
                                // gap -- content sits closer to the edge.
                                leftMargin: entryItem.modelData.count > 1
                                    ? countBadge.x + countBadge.width + 6
                                    : box.border.width * 2 + inner.anchors.leftMargin
                                right: parent.right
                                rightMargin: 8
                                // Explicit top instead of verticalCenter --
                                // entryItem's height (14 top + 10 bottom) is
                                // asymmetric now, which verticalCenter can't
                                // express (it'd split the padding evenly).
                                top: parent.top
                                topMargin: 14
                            }
                            // Was 4 -- too tight specifically above the
                            // description, where line2/countBadge sit right
                            // at this same boundary and made it read as even
                            // less room than it was. bar2's own topMargin
                            // above already reads this via entryContent.spacing,
                            // so the bump applies there too automatically.
                            spacing: 12

                            Row {
                                id: entryHeader
                                width: parent.width
                                spacing: 6

                                Image {
                                    id: entryIcon
                                    visible: source !== ""
                                    width: visible ? 18 : 0
                                    height: 18
                                    // No `image` field here (unlike the live toast) — history
                                    // never stores it; see the comment where NotificationHistory.add()
                                    // is called for why it can't survive being persisted anyway.
                                    // Falls back to the same bundled plain-bell asset as the
                                    // live toast in Notifications.qml, for senders that gave
                                    // no app_icon hint -- see its comment for why this is a
                                    // bundled SVG rather than a system icon-theme lookup.
                                    source: {
                                        if (!entryItem.modelData.appIcon)
                                            return Qt.resolvedUrl("../assets/notification-default.svg")
                                        return entryItem.modelData.appIcon.startsWith("/")
                                            ? "file://" + entryItem.modelData.appIcon
                                            : Quickshell.iconPath(entryItem.modelData.appIcon, true)
                                    }
                                }

                                Text {
                                    width: entryHeader.width - (entryIcon.visible ? entryIcon.width + entryHeader.spacing : 0)
                                        - closeGlyph.implicitWidth - entryHeader.spacing
                                    text: entryItem.modelData.summary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: closeGlyph
                                    // Font Awesome "times" -- was an empty
                                    // string (the PUA codepoint got lost
                                    // somewhere along the way), which is
                                    // why this rendered as nothing at all
                                    // instead of a missing-glyph box.
                                    text: ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    color: Theme.textDim

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: NotificationHistory.remove(entryItem.modelData.id)
                                    }
                                }
                            }

                            Text {
                                visible: !entryItem.expanded && entryItem.modelData.body.length > 0
                                // Column controls y, not x -- a per-child x
                                // is still free to set. Multi (count > 1)
                                // pulls back out from under countBadge's
                                // wide clearance so body/time sit tight
                                // against line2 instead of matching the
                                // title's wider indent -- computed off
                                // line2's own right edge (+6 gap) rather
                                // than a fixed guess, so it tracks if
                                // line2's position ever changes. Single has
                                // no badge to clear in the first place, so
                                // it keeps the same left edge as the title
                                // (x: 0).
                                x: entryItem.modelData.count > 1
                                    ? (line2.anchors.leftMargin + line2.width + 6) - entryContent.anchors.leftMargin
                                    : 0
                                width: parent.width
                                text: entryItem.modelData.body
                                // StyledText, not PlainText — senders like
                                // Telegram send real markup (<b>, etc.);
                                // no `elide` alongside maximumLineCount
                                // here, same reasoning as Notifications.qml's
                                // toast body (that combination on rich text
                                // is what caused its "Maximum call stack"
                                // crash).
                                textFormat: Text.StyledText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.textMuted
                            }

                            // Expanded view of a folded entry: every message
                            // from the run, oldest first. The summary/title
                            // above already names the sender/chat once, so
                            // these are just the bodies, not re-labeled per
                            // message.
                            Column {
                                visible: entryItem.expanded && entryItem.modelData.bodies !== undefined
                                // Only ever visible for a folded (count > 1)
                                // entry -- see modelData.bodies comment
                                // above -- so this always uses the
                                // pulled-in-to-line2 offset, same formula as
                                // the collapsed description/time Text above.
                                x: (line2.anchors.leftMargin + line2.width + 6) - entryContent.anchors.leftMargin
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: entryItem.modelData.bodies || []
                                    delegate: Column {
                                        id: messageItem
                                        required property var modelData
                                        required property int index
                                        width: parent.width
                                        spacing: 2

                                        Row {
                                            width: parent.width
                                            spacing: 6

                                            Text {
                                                width: parent.width - msgCloseGlyph.implicitWidth - parent.spacing
                                                text: messageItem.modelData.body
                                                textFormat: Text.StyledText
                                                wrapMode: Text.WordWrap
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 2
                                                color: Theme.textMuted
                                            }

                                            // Dismisses just this one
                                            // message out of the folded run
                                            // -- NotificationHistory.removeMessage()
                                            // collapses the entry back down
                                            // to a plain single once only
                                            // one message is left, same as
                                            // if it had never been folded.
                                            Text {
                                                id: msgCloseGlyph
                                                // Font Awesome "times", same codepoint as closeGlyph above.
                                                text: ""
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 3
                                                color: Theme.textDim

                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: NotificationHistory.removeMessage(entryItem.modelData.id, messageItem.index)
                                                }
                                            }
                                        }

                                        // Per-message time -- meaningful
                                        // here since a folded run can span
                                        // minutes, unlike the entry's own
                                        // single time row below (just the
                                        // latest message's time).
                                        Text {
                                            visible: messageItem.modelData.time !== undefined
                                            text: Qt.formatDateTime(new Date(messageItem.modelData.time), "MMM d, HH:mm")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                            color: Theme.textDim
                                        }
                                    }
                                }
                            }

                            Text {
                                // Hidden while expanded -- each message in
                                // the expanded list already shows its own
                                // time (see the per-message Text above),
                                // so this "just the latest message's time"
                                // row would be a redundant duplicate of the
                                // last one in that list.
                                visible: !entryItem.expanded
                                // Same title-aligned-for-single /
                                // pulled-in-for-multi rule as the
                                // description Text above.
                                x: entryItem.modelData.count > 1
                                    ? (line2.anchors.leftMargin + line2.width + 6) - entryContent.anchors.leftMargin
                                    : 0
                                text: Qt.formatDateTime(new Date(entryItem.modelData.time), "MMM d, HH:mm")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                color: Theme.textDim
                            }
                        }
                    }
                }
            }
        }
    }
}
