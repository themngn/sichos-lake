import QtQuick
import Quickshell.Widgets

// The record beside a 1:1 cover: black grooves with the cover as its label.
// It spins while playing; on pause it slows down and slides `tuck` px behind
// the sleeve, which the parent draws on top of it, and comes back out on play.
Item {
    id: rec
    property string art: ""
    property bool playing: false
    property real tuck: -46
    property real labelSize: 24
    width: 64
    height: 64

    transform: Translate {
        x: rec.playing ? 0 : rec.tuck
        Behavior on x { NumberAnimation { duration: 480; easing.type: Easing.InOutCubic } }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#111111"
    }
    // Only the label turns: grooves are round, so turning them would show
    // nothing and cost a repaint per frame.
    Repeater {
        model: Math.floor((rec.width - rec.labelSize) / 6)
        delegate: Rectangle {
            required property int index
            anchors.centerIn: parent
            width: rec.labelSize + 6 * (index + 1)
            height: width
            radius: width / 2
            color: "transparent"
            border.color: "#232323"
            border.width: 1
        }
    }
    ClippingRectangle {
        id: label
        anchors.centerIn: parent
        width: rec.labelSize
        height: rec.labelSize
        radius: width / 2
        color: "#111111"
        Image {
            anchors.fill: parent
            source: rec.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            sourceSize.height: 112
        }
    }

    // Started by hand so a stop keeps the angle it reached (`from` and `to`
    // as bindings would chase the running rotation).
    readonly property bool spinning: rec.playing && rec.visible
    onSpinningChanged: rec._sync()
    Component.onCompleted: rec._sync()
    function _sync() {
        if (rec.spinning) {
            slowDown.stop()
            spin.from = label.rotation % 360
            spin.to = spin.from + 360
            spin.restart()
        } else if (spin.running) {
            spin.stop()
            slowDown.to = label.rotation + 80
            slowDown.restart()
        }
    }
    NumberAnimation { id: spin; target: label; property: "rotation"; duration: 3600; loops: Animation.Infinite }
    NumberAnimation { id: slowDown; target: label; property: "rotation"; duration: 480; easing.type: Easing.OutCubic }
}
