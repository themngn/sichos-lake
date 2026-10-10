import QtQuick

// Base for a bar popup's content, rendered inside the bar's one MorphPopup
// card instead of its own window. The owning widget assigns this to a
// property (not a child -- Pill's default property would lay it out inside
// the pill), sets `parent: root.popupHost` (the card, from Bar.qml) and
// drives `shown`; the card sizes itself to this item's implicit size, lines
// up under anchorItem, and cross-fades between contents.
Item {
    required property Item anchorItem
    property bool shown: false

    anchors.top: parent ? parent.top : undefined
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    opacity: shown ? 1 : 0
    visible: opacity > 0
    // Outgoing content clears out quickly so the two don't read as a
    // jumble mid-morph; the incoming one fades in over the full open time.
    Behavior on opacity {
        NumberAnimation { duration: shown ? Theme.openDuration : 70; easing.type: Easing.OutCubic }
    }
}
