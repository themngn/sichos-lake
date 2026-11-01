import QtQuick
import Quickshell

// A hover tooltip under a bar item: a small card after a short delay. Was
// built into Pill.qml (one per pill); split out so items inside a pill --
// tray icons, workspace buttons -- can have their own.
//
// A Quickshell PopupWindow rather than QtQuick.Controls ToolTip: a
// layer-shell PanelWindow has no QQuickOverlay for Controls popups to parent
// into, so the stock ToolTip attached property silently never shows anything
// on this bar.
//
// Not while a bar popup is open (the hub, a hover card): a tooltip popping
// up over/beside it is just noise.
PopupWindow {
    id: tip
    // The item it hangs under, and whether the pointer is on it.
    required property Item target
    property bool hovered: false
    property string text: ""

    function hide() {
        delay.stop()
        tip.visible = false
    }

    readonly property bool _want: tip.hovered && tip.text.length > 0 && ShellState.activePopup === ""
    on_WantChanged: if (tip._want) delay.restart(); else tip.hide()

    Timer {
        id: delay
        interval: 400
        onTriggered: tip.visible = true
    }

    anchor.item: tip.target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4
    color: "transparent"
    visible: false
    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight

    Rectangle {
        id: bg
        implicitWidth: label.implicitWidth + 16
        implicitHeight: label.implicitHeight + 10
        color: Theme.surfaceFor(tip.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.controlRadius

        Text {
            id: label
            anchors.centerIn: parent
            text: tip.text
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.text
        }
    }
}
