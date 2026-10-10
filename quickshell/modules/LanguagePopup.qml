import QtQuick
import Quickshell

// Hover popup for Language.qml, listing every configured keyboard layout
// with the active one highlighted. No focus grab (unlike CalendarPopup) —
// it's hover-driven, so it should just disappear when the mouse leaves.
PopupWindow {
    id: popup

    required property Item anchorItem
    property var codes: []
    property int activeIndex: -1

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    readonly property var codeInfo: ({
        us: { flag: "🇬🇧", name: "English (US)" },
        ua: { flag: "🇺🇦", name: "Українська" },
    })

    function flagFor(code) {
        return (codeInfo[code] && codeInfo[code].flag) || code.toUpperCase()
    }
    function nameFor(code) {
        return (codeInfo[code] && codeInfo[code].name) || code.toUpperCase()
    }

    Rectangle {
        id: bg
        SurfaceAppear { target: bg; shown: popup.visible }
        implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
        implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding
        color: Theme.surface
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: popup.codes

                delegate: Rectangle {
                    id: row
                    required property string modelData
                    required property int index

                    readonly property bool active: row.index === popup.activeIndex

                    width: rowContent.implicitWidth + 16
                    height: rowContent.implicitHeight + 6
                    radius: Theme.controlRadius
                    color: row.active ? Theme.hoverFill : "transparent"

                    Row {
                        id: rowContent
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: popup.flagFor(row.modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: popup.nameFor(row.modelData)
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: row.active ? Theme.accent : Theme.text
                        }
                    }
                }
            }
        }
    }
}
