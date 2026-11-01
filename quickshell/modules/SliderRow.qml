import QtQuick

// Icon + slider + percentage (+ a chevron that opens a page): the Control
// Center's volume/brightness row, shared with its pages (Sound, Display).
Item {
    id: slider
    property string glyph: ""
    property real glyphScale: 1
    property bool dim: false
    property real value: 0
    // Shown instead of the percentage when the slider's range isn't 0-100%.
    property string valueText: ""
    signal moved(real v)
    signal glyphClicked()
    // Connected = shows a chevron at the end that opens a page.
    signal more()
    property bool hasMore: true

    height: Theme.controlHeight + 4

    function valueAt(x) { return Math.max(0, Math.min(1, x / track.width)) }

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
            width: track.width * Math.max(0, Math.min(1, slider.value))
            height: parent.height
            radius: Theme.trackRadius
            color: Theme.text
        }
        Rectangle {
            x: track.width * Math.max(0, Math.min(1, slider.value)) - width / 2
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
            onPressed: (mouse) => slider.moved(slider.valueAt(mouse.x))
            onPositionChanged: (mouse) => { if (pressed) slider.moved(slider.valueAt(mouse.x)) }
            onWheel: (wheel) => slider.moved(Math.max(0, Math.min(1, slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
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
