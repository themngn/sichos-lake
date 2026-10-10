import QtQuick

// Open animation for a popup/menu card: a quick fade plus a slight scale-up
// from `origin` (the edge it's attached to), macOS-menu style. Drop one inside
// the card: `SurfaceAppear { target: bg; shown: popup.visible }`.
//
// Opening only. Closing stays instant: the cards live in PopupWindow/
// PanelWindow surfaces whose `visible` is bound straight to "is this popup
// open", so a close animation would mean keeping every window mapped past
// that point, i.e. reworking how each popup decides it's open.
Item {
    id: appear

    required property Item target
    property bool shown: false
    property int origin: Item.Top

    function play() {
        appear.target.transformOrigin = appear.origin
        anim.restart()
    }

    onShownChanged: {
        if (appear.shown) {
            appear.play()
        } else {
            // Reset while hidden, so the next open never shows a frame of
            // the fully-visible card before the animation starts.
            anim.stop()
            appear.target.opacity = 0
            appear.target.scale = Theme.openScaleFrom
        }
    }
    Component.onCompleted: if (appear.shown) appear.play()

    ParallelAnimation {
        id: anim
        NumberAnimation {
            target: appear.target
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.openDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: appear.target
            property: "scale"
            from: Theme.openScaleFrom
            to: 1
            duration: Theme.openDuration
            easing.type: Easing.OutCubic
        }
    }
}
