import QtQuick
import Quickshell

// Flat, background-less module container matching waybar's `#module { padding }` styling
// (no pill background/border/radius — waybar modules carry no chrome besides padding).
//
// Tooltips use a Quickshell PopupWindow rather than QtQuick.Controls ToolTip: a
// layer-shell PanelWindow has no QQuickOverlay for Controls popups to parent into,
// so the stock ToolTip attached property silently never shows anything on this bar.
Item {
    id: root

    default property alias content: layout.data
    property real horizontalPadding: 8
    property string tooltipText: ""
    // For modules that need a richer hover popup than tooltipText's plain
    // label (e.g. Language's layout list) — build your own PopupWindow and
    // bind its visibility to this instead of adding another tooltip mode here.
    readonly property alias hovered: mouseArea.containsMouse

    signal clicked(var mouse)
    signal wheel(var event)

    implicitHeight: Theme.barHeight
    implicitWidth: layout.implicitWidth + horizontalPadding * 2

    Row {
        id: layout
        anchors.centerIn: parent
        spacing: 6
    }

    MouseArea {
        id: mouseArea
        z: -1
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onClicked: (mouse) => {
            tooltipDelay.stop()
            tooltipPopup.visible = false
            root.clicked(mouse)
        }
        onWheel: (event) => root.wheel(event)
        onContainsMouseChanged: {
            if (mouseArea.containsMouse && root.tooltipText.length > 0) {
                tooltipDelay.restart()
            } else {
                tooltipDelay.stop()
                tooltipPopup.visible = false
            }
        }
    }

    onTooltipTextChanged: if (root.tooltipText.length === 0) tooltipPopup.visible = false

    Timer {
        id: tooltipDelay
        interval: 400
        onTriggered: tooltipPopup.visible = true
    }

    PopupWindow {
        id: tooltipPopup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        visible: false
        implicitWidth: tooltipBg.implicitWidth
        implicitHeight: tooltipBg.implicitHeight

        Rectangle {
            id: tooltipBg
            implicitWidth: tooltipLabel.implicitWidth + 16
            implicitHeight: tooltipLabel.implicitHeight + 10
            color: "#1c1c1c"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 4

            Text {
                id: tooltipLabel
                anchors.centerIn: parent
                text: root.tooltipText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                color: Theme.text
            }
        }
    }
}
