import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: popup

    required property Item anchorItem

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"
    visible: false
    // Without an actual focus grab, HyprlandFocusGrab's "cleared" signal never
    // fires, so the popup only ever closed via re-clicking the clock.
    grabFocus: true

    property date viewDate: new Date()
    readonly property date today: new Date()

    function shiftMonth(delta) {
        popup.viewDate = new Date(popup.viewDate.getFullYear(), popup.viewDate.getMonth() + delta, 1)
    }

    function goToday() {
        popup.viewDate = new Date()
    }

    readonly property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Leading/trailing 0s pad the grid to whole weeks (Monday-first)
    readonly property var cells: {
        const year = viewDate.getFullYear()
        const month = viewDate.getMonth()
        const firstOfMonth = new Date(year, month, 1)
        const daysInMonth = new Date(year, month + 1, 0).getDate()
        const startOffset = (firstOfMonth.getDay() + 6) % 7
        const list = []
        for (let i = 0; i < startOffset; i++) list.push(0)
        for (let d = 1; d <= daysInMonth; d++) list.push(d)
        while (list.length % 7 !== 0) list.push(0)
        return list
    }

    readonly property bool viewingCurrentMonth:
        viewDate.getFullYear() === today.getFullYear() && viewDate.getMonth() === today.getMonth()

    HyprlandFocusGrab {
        id: grab
        windows: [popup]
        active: popup.visible
        onCleared: popup.visible = false
    }

    Rectangle {
        id: bg
        implicitWidth: grid.implicitWidth + 24
        implicitHeight: header.implicitHeight + grid.implicitHeight + 28
        color: "#1c1c1c"
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        radius: 6

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Row {
                id: header
                width: parent.width
                height: 20

                Text {
                    width: 24
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "<"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.text
                    MouseArea { anchors.fill: parent; onClicked: popup.shiftMonth(-1) }
                }

                Text {
                    width: parent.width - 48
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Qt.formatDate(popup.viewDate, "MMMM yyyy")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.text
                    MouseArea { anchors.fill: parent; onClicked: popup.goToday() }
                }

                Text {
                    width: 24
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ">"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.text
                    MouseArea { anchors.fill: parent; onClicked: popup.shiftMonth(1) }
                }
            }

            Grid {
                id: grid
                columns: 7
                columnSpacing: 4
                rowSpacing: 4

                Repeater {
                    model: popup.dayNames
                    delegate: Text {
                        required property string modelData
                        width: 26
                        height: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.textMuted
                    }
                }

                Repeater {
                    model: popup.cells
                    delegate: Rectangle {
                        id: cell
                        required property int modelData
                        readonly property bool isToday: popup.viewingCurrentMonth && modelData === popup.today.getDate()
                        width: 26
                        height: 26
                        radius: 13
                        color: isToday ? Theme.text : "transparent"

                        Text {
                            anchors.centerIn: parent
                            visible: cell.modelData !== 0
                            text: cell.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: cell.isToday ? "#1c1c1c" : Theme.text
                        }
                    }
                }
            }
        }
    }
}
