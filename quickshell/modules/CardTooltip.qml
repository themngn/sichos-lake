import QtQuick

// A hover tooltip in a popup card's window, below the hovered control: for
// icon-only controls in the Control Center (footer switches, power profile,
// edit / power buttons). BarTooltip's own window can't be used there -- the
// card is the bar's MorphPopup surface, and a window stacked beside it never
// got the pointer (the same reason ModePicker's list is drawn in-card).
//
// One per card. A control calls `hover(this, hovered)` and carries a
// `tipText` property, read live (a switch's state changes under the pointer),
// and optionally `tipHint`, a muted second line ("Right-click for settings").
Rectangle {
    id: tip
    property Item target: null
    property Item _pending: null

    function hover(item, hovered) {
        if (hovered) {
            tip._pending = item
            // Moving from one control to the next while one shows: switch at once.
            if (tip.visible) tip.showFor(item)
            else delay.restart()
        } else if (tip._pending === item || tip.target === item) {
            delay.stop()
            tip._pending = null
            tip.target = null
            tip.visible = false
        }
    }
    function showFor(item) {
        if (!item || !tip.parent) return
        tip.target = item
        const p = item.mapToItem(tip.parent, item.width / 2, item.height)
        tip.x = Math.round(Math.max(4, Math.min(tip.parent.width - tip.width - 4, p.x - tip.width / 2)))
        tip.y = Math.round(p.y + 8)
        tip.visible = tip.text !== ""
    }

    readonly property string text: tip.target && tip.target.tipText !== undefined ? tip.target.tipText : ""
    readonly property string hint: tip.target && tip.target.tipHint !== undefined ? tip.target.tipHint : ""
    // Re-centre when the text (and so the width) changes while shown.
    onTextChanged: if (tip.visible) tip.showFor(tip.target)
    onHintChanged: if (tip.visible) tip.showFor(tip.target)

    Timer {
        id: delay
        interval: 400
        onTriggered: tip.showFor(tip._pending)
    }

    z: 1000
    visible: false
    width: Math.max(label.implicitWidth, hintLabel.visible ? hintLabel.implicitWidth : 0) + 16
    height: lines.implicitHeight + 10
    radius: Theme.controlRadius
    // Solid: it can sit over the card's own rows or past its edge.
    color: Theme.surfaceRaised
    border.color: Theme.surfaceBorder
    border.width: Theme.surfaceBorderWidth

    Column {
        id: lines
        anchors.centerIn: parent
        spacing: 1
        Text {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            text: tip.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
            color: Theme.text
        }
        Text {
            id: hintLabel
            visible: tip.hint !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: tip.hint
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 3
            color: Theme.textMuted
        }
    }
}
