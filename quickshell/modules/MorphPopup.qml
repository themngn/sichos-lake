import QtQuick
import Quickshell

// One card shared by every hover popup on this bar: the toggle row's
// (Sunset, HDR, Idle, GameFocus, Transparency, BarSolo, Mic,
// NotificationMute), the clock's calendar, Weather, and the right-side
// widgets with hover popups (AI usage, Bluetooth, System Update, Display).
// Each widget reparents its MorphContent into `slot` and drives that
// content's `shown`; while one is open, moving to another widget slides and
// reshapes this card into the next popup (x/width/height animate, contents
// cross-fade) instead of closing one window and opening another. Click
// menus (tray, language, workspace) and the notification drawer keep their
// own windows.
//
// The window itself never moves or resizes during a morph: it spans the
// bar's full width and the tallest content's height, transparent, with its
// input region masked to the card (so the rest doesn't swallow clicks meant
// for windows underneath). Resizing/moving a Wayland popup surface per
// frame stutters; animating an item inside a fixed surface doesn't. The
// bar's blur_popups layer rule (hypr/window_rules.lua) still only blurs
// the card, since everything else in the surface is fully transparent.
PopupWindow {
    id: host

    required property var bar

    readonly property Item slot: card

    // Popup contents parented into the card (anything with `shown` and
    // `anchorItem`).
    // activeContent is kept up to date imperatively (each content's
    // shownChanged, plus the card's onChildrenChanged) rather than as a
    // binding over card.children/`shown`: as a binding it kept tripping a
    // binding-loop warning through the contents' own initialization.
    property var _contents: []
    property var _hooked: []
    function _refreshContents() {
        // anchorItem, not just `shown`: the card's own SurfaceAppear has a
        // `shown` too, and once the window opened it won as "active" (0x0).
        const list = Array.from(card.children).filter(c => c.shown !== undefined && c.anchorItem !== undefined)
        for (const c of list) {
            if (host._hooked.indexOf(c) === -1) {
                host._hooked.push(c)
                c.shownChanged.connect(host._scheduleUpdate)
            }
        }
        host._contents = list
        host._updateActive()
    }
    // Switching popups flips two contents' `shown` in one go (old -> false,
    // new -> true), but their change signals arrive one at a time in
    // creation order. Picking the active content synchronously on each one
    // could land on "none shown" in between -- closing the card and
    // re-opening it (no morph) -- whenever the old content's signal came
    // first, which made morphing work in only one direction along the bar.
    // Deferring to after both have settled sees the old -> new switch
    // directly. (Qt.callLater collapses repeat calls in the same tick.)
    function _scheduleUpdate() { Qt.callLater(host._updateActive) }
    function _updateActive() {
        host.activeContent = host._contents.find(c => c.shown === true) || null
    }

    // The content currently shown (contents fade, so more than one can be
    // visible for a moment -- `shown` is the target, not `visible`).
    property Item activeContent: null
    // Last non-null activeContent: the card keeps its geometry while closed,
    // so the next open's first frame isn't a zero-size card.
    property Item _lastContent: null

    // Tallest content, so the surface fits whichever one is open without
    // ever resizing mid-morph.
    readonly property real _maxContentHeight: Math.max(0, ...host._contents.map(c => c.implicitHeight))

    anchor.window: host.bar
    anchor.rect.x: 0
    anchor.rect.y: host.bar.height
    anchor.rect.width: host.bar.width
    anchor.rect.height: 1
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right

    implicitWidth: host.bar.width
    implicitHeight: card.y + host._maxContentHeight + 8
    color: "transparent"
    // Applied a tick after activeContent changes, not bound to it: mapping
    // the window can synchronously change hover state, which feeds back into
    // ShellState.activePopup -> a content's `shown` -> activeContent, and
    // Qt flagged that as a binding loop on `visible`.
    property bool _open: false
    function _syncOpen() { host._open = host.activeContent !== null }
    visible: host._open

    mask: Region { item: card }

    // Geometry jumps straight to the first popup on open (the card's own
    // SurfaceAppear fade/scale plays instead) and only animates between
    // popups while already open.
    property bool _morph: false
    onActiveContentChanged: {
        Qt.callLater(host._syncOpen)
        if (host.activeContent !== null) host._lastContent = host.activeContent
        if (host.activeContent === null) {
            host._morph = false
        } else if (!host._morph) {
            Qt.callLater(() => { if (host.activeContent !== null) host._morph = true })
        }
    }

    Rectangle {
        id: card
        SurfaceAppear { target: card; shown: host.visible }
        // Deferred a tick: contents reparent in here while their own
        // bindings are still initializing, and refreshing synchronously
        // re-entered activeContent mid-evaluation (binding-loop warning).
        onChildrenChanged: Qt.callLater(host._refreshContents)

        property real targetWidth: host._lastContent ? host._lastContent.implicitWidth : 0
        property real targetHeight: host._lastContent ? host._lastContent.implicitHeight : 0
        // Centered under the content's toggle (what the per-toggle
        // PopupWindows did with Edges.Bottom gravity), clamped on-screen.
        // The x/width reads of the toggle and its row are only there to
        // re-evaluate this when the toggle row's layout shifts.
        property real targetX: {
            const ai = host._lastContent ? host._lastContent.anchorItem : null
            if (!ai) return 0
            void (ai.x + ai.width + (ai.parent ? ai.parent.x + ai.parent.width : 0))
            const center = ai.mapToItem(null, ai.width / 2, 0).x
            return Math.max(8, Math.min(host.width - card.targetWidth - 8, center - card.targetWidth / 2))
        }

        x: card.targetX
        y: 4
        width: card.targetWidth
        height: card.targetHeight
        clip: true
        color: Theme.surfaceFor(host.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        Behavior on x {
            enabled: host._morph
            NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: host._morph
            NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: host._morph
            NumberAnimation { duration: Theme.morphDuration; easing.type: Easing.OutCubic }
        }
    }
}
