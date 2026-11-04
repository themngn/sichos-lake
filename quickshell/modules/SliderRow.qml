import QtQuick

// Icon + slider + percentage (+ a chevron that opens a page): the Control
// Center's volume/brightness row, shared with its pages (Sound, Display).
Item {
    id: slider
    property string glyph: ""
    property real glyphScale: 1
    property bool dim: false
    property real value: 0
    // Top of the range (a mixer app can go past 100%).
    property real maxValue: 1
    // The range only reaches maxValue while the value is past 100%, otherwise
    // it ends at 100% (the Control Center's main page; the Sound page has the
    // full range). Kept for the whole of a drag that started above, or
    // crossing 100% would rescale the track under the pointer.
    property bool rangeFollowsValue: false
    property bool _heldAbove: false
    readonly property real rangeMax: !slider.rangeFollowsValue || slider.value > 1.005 || slider._heldAbove
        ? slider.maxValue : 1
    // Past 100%: a drag or scroll landing within 4% of it stays on it, with a
    // mark under the track. Less than the wheel's 5% step, or the wheel could
    // never leave it.
    readonly property bool snaps: slider.rangeMax > 1
    readonly property real fraction: Math.max(0, Math.min(1, slider.value / slider.rangeMax))
    // Shown instead of the percentage when the slider's range isn't 0-100%.
    property string valueText: ""
    signal moved(real v)
    signal glyphClicked()
    // Connected = shows a chevron at the end that opens a page.
    signal more()
    property bool hasMore: true

    height: Theme.controlHeight + 4

    function snapped(v) {
        const c = Math.max(0, Math.min(slider.rangeMax, v))
        return slider.snaps && Math.abs(c - 1) < 0.04 ? 1 : c
    }
    function valueAt(x) { return slider.snapped(x / track.width * slider.rangeMax) }

    Item {
        id: glyphBox
        width: 24
        height: parent.height
        Text {
            // Left-aligned like Volume.qml: the volume glyphs differ in
            // width, centering would wobble the speaker side to side.
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: slider.glyph
            color: slider.dim ? Theme.textDim : glyphArea.containsMouse ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: (Theme.fontSize + 3) * slider.glyphScale
        }
        MouseArea {
            id: glyphArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: slider.glyphClicked()
        }
    }

    Rectangle {
        id: track
        anchors.left: glyphBox.right
        anchors.leftMargin: 6
        anchors.right: pct.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.trackHeight - 2
        radius: Theme.trackRadius
        color: Theme.track
        opacity: slider.dim ? 0.5 : 1

        Rectangle {
            width: track.width * Math.min(slider.fraction, 1 / slider.rangeMax)
            height: parent.height
            radius: Theme.trackRadius
            color: Theme.text
        }
        // The part past 100%.
        Rectangle {
            visible: slider.value > 1.005 && slider.snaps
            x: track.width / slider.rangeMax
            width: track.width * slider.fraction - x
            height: parent.height
            radius: Theme.trackRadius
            color: Theme.danger
        }
        // The 100% mark, below where the knob (14px, centered on the track)
        // reaches, so it stays visible with the knob on it.
        Rectangle {
            visible: slider.snaps
            x: track.width / slider.rangeMax - width / 2
            y: track.height / 2 + 7 + 1
            width: 2
            height: 5
            radius: 1
            color: Theme.textDim
        }
        Rectangle {
            x: track.width * slider.fraction - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: "white"
        }

        MouseArea {
            // Taller than the track so it's easy to grab.
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            cursorShape: Qt.PointingHandCursor
            // In a scrolling list a drag that wanders up or down stays a drag.
            preventStealing: true
            onPressed: (mouse) => {
                slider._heldAbove = slider.value > 1.005
                slider.moved(slider.valueAt(mouse.x))
            }
            onReleased: slider._heldAbove = false
            onCanceled: slider._heldAbove = false
            onPositionChanged: (mouse) => { if (pressed) slider.moved(slider.valueAt(mouse.x)) }
            onWheel: (wheel) => slider.moved(slider.snapped(slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
        }
    }

    Rectangle {
        id: sliderMore
        visible: slider.hasMore
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: slider.hasMore ? 24 : 0
        height: 24
        radius: Theme.controlRadius
        color: sliderMoreArea.containsMouse ? Theme.hoverFill : "transparent"
        Text {
            anchors.centerIn: parent
            text: "\u{f0142}" // nf-md-chevron_right
            color: sliderMoreArea.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
        }
        MouseArea {
            id: sliderMoreArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: slider.more()
        }
    }
    Text {
        id: pct
        anchors.right: sliderMore.left
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        horizontalAlignment: Text.AlignRight
        text: slider.valueText !== "" ? slider.valueText : Math.round(slider.value * 100) + "%"
        color: Theme.textMuted
        font.family: Theme.uiFontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
