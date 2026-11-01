import QtQuick
import Quickshell

// Flat, background-less module container matching waybar's `#module { padding }` styling
// (no pill background/border/radius — waybar modules carry no chrome besides padding).
// `tooltipText`: a BarTooltip under the pill on hover (see there).
Item {
    id: root

    default property alias content: layout.data
    property real horizontalPadding: 8
    property string tooltipText: ""
    // For modules that need a richer hover popup than tooltipText's plain
    // label (e.g. Language's layout list) — build your own PopupWindow and
    // bind its visibility to this instead of adding another tooltip mode here.
    readonly property alias hovered: mouseArea.containsMouse
    // false when nested inside another pill (QuickSettings): `enabled: false`
    // is not enough, Qt 6 still delivers hover to disabled items, so this
    // pill's MouseArea kept the hover (and showed its tooltip) instead of the
    // outer pill underneath it.
    property bool interactive: true

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
        visible: root.interactive
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onClicked: (mouse) => {
            tooltip.hide()
            root.clicked(mouse)
        }
        onWheel: (event) => root.wheel(event)
    }

    BarTooltip {
        id: tooltip
        target: root
        hovered: mouseArea.containsMouse
        text: root.tooltipText
    }
}
