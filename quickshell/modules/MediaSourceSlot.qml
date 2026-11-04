import QtQuick

// One source's place in the Control Center's list, for its whole life (a
// player's slot survives reorders, since its Repeater runs on Mpris.players),
// placed by rank: when the order changes the slots slide past each other --
// the new lead moving up while growing into the banner, the old one moving
// down while shrinking into a card. Rebuilt rows used to get stuck invisible
// when a fade-in was cut short.
Item {
    id: slot
    required property Item stack
    property int rank: -1
    property var player: null
    property var app: null
    property string artSource: ""
    readonly property int cardHeight: 72
    readonly property int gap: 6

    MediaSource {
        id: src
        player: slot.player
        app: slot.app
        artSource: slot.rank >= 0 ? slot.artSource : ""
        shown: slot.visible
    }

    readonly property bool lead: slot.rank === 0
    // A lead with no cover has nothing to fill a banner with: it stays a card.
    readonly property bool asBanner: slot.lead && src.hasArt
    visible: slot.rank >= 0
    width: slot.stack.width
    height: slot.asBanner ? banner.height : slot.cardHeight
    y: slot.rank <= 0 ? 0 : slot.stack.leadHeight + slot.gap + (slot.rank - 1) * (slot.cardHeight + slot.gap)
    // The lead slides over the others while they pass under it.
    z: slot.lead ? 1 : 0
    clip: true
    Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

    // Set by hand: a Binding with `when: slot.lead` kept the card's height for
    // a new lead (its value flips to the banner's in the same change, and that
    // update was lost), which left the old lead hidden under the new banner.
    readonly property real ownHeight: slot.asBanner ? banner.height : slot.cardHeight
    function _pushLead() { if (slot.lead) slot.stack.leadHeight = slot.ownHeight }
    onLeadChanged: slot._pushLead()
    onOwnHeightChanged: slot._pushLead()

    // The swap in 3D: on its way up a card tips its top edge toward you and
    // lifts (grows), on its way down it tips away and sinks (shrinks, darkens)
    // -- they pass like two cards being shuffled rather than sliding flat.
    // Rotation about X is perspective-projected, so the tilt reads as depth.
    transform: [
        Rotation {
            id: tilt
            axis { x: 1; y: 0; z: 0 }
            origin.x: slot.width / 2
            origin.y: slot.height / 2
            angle: 0
        },
        Scale {
            id: depth
            origin.x: slot.width / 2
            origin.y: slot.height / 2
        }
    ]
    property int _prevRank: -1
    onRankChanged: {
        if (slot._prevRank >= 0 && slot.rank >= 0 && slot.rank !== slot._prevRank)
            (slot.rank < slot._prevRank ? riseAnim : sinkAnim).restart()
        slot._prevRank = slot.rank
    }
    Component.onCompleted: {
        slot._prevRank = slot.rank
        slot._pushLead()
    }
    SequentialAnimation {
        id: riseAnim
        ParallelAnimation {
            NumberAnimation { target: tilt; property: "angle"; to: -18; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { target: depth; properties: "xScale,yScale"; to: 1.05; duration: 220; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: tilt; property: "angle"; to: 0; duration: 420; easing.type: Easing.OutBack }
            NumberAnimation { target: depth; properties: "xScale,yScale"; to: 1; duration: 420; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: sinkAnim
        ParallelAnimation {
            NumberAnimation { target: tilt; property: "angle"; to: 18; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { target: depth; properties: "xScale,yScale"; to: 0.9; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { target: shade; property: "opacity"; to: 0.45; duration: 220; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: tilt; property: "angle"; to: 0; duration: 420; easing.type: Easing.OutBack }
            NumberAnimation { target: depth; properties: "xScale,yScale"; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: shade; property: "opacity"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        }
    }

    MediaSourceBanner {
        id: banner
        width: parent.width
        source: src
        opacity: slot.asBanner ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InOutQuad } }
    }
    MediaSourceCard {
        width: parent.width
        source: src
        opacity: slot.asBanner ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InOutQuad } }
    }
    // Darkens the card while it sinks (sinkAnim).
    Rectangle {
        id: shade
        anchors.fill: parent
        radius: Theme.controlRadius
        color: "black"
        opacity: 0
        visible: opacity > 0
    }
}
