import QtQuick

// Segmented control shared by the Control Center pages (Display scale, HDR,
// Hotspot mode, VPN NetShield, Phone dock side...): one sunken track, the
// chosen option an accent pill that slides between them. Was an inline
// component in VpnPage/PhonePage first; the other pages used rows of
// separate bordered buttons.
// `options`: strings/numbers, or { value, label } objects; `current`
// matches a value.
Rectangle {
    id: seg
    property var options: []
    property var current
    property bool busy: false
    signal picked(var value)

    function valueOf(o) { return typeof o === "object" && o !== null ? o.value : o }
    function labelOf(o) { return typeof o === "object" && o !== null ? o.label : String(o) }

    readonly property int index: {
        for (let i = 0; i < seg.options.length; i++) if (seg.valueOf(seg.options[i]) === seg.current) return i
        return -1
    }
    readonly property real segWidth: (seg.width - 4) / Math.max(1, seg.options.length)

    width: parent ? parent.width : 180
    height: Theme.controlHeight + 4
    radius: Theme.controlRadius
    color: Theme.controlFill
    opacity: seg.busy ? 0.5 : 1

    Rectangle {
        visible: seg.index >= 0
        x: 2 + Math.max(0, seg.index) * seg.segWidth
        y: 2
        width: seg.segWidth
        height: parent.height - 4
        radius: Theme.controlRadius - 2
        color: Theme.accent
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
    Row {
        x: 2
        Repeater {
            model: seg.options
            Item {
                id: opt
                required property var modelData
                required property int index
                readonly property bool isCurrent: opt.index === seg.index
                width: seg.segWidth
                height: seg.height
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: seg.labelOf(opt.modelData)
                    color: opt.isCurrent ? Theme.textOnLight
                        : optArea.containsMouse ? Theme.text : Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: opt.isCurrent
                }
                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    enabled: !seg.busy
                    hoverEnabled: true
                    cursorShape: opt.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!opt.isCurrent) seg.picked(seg.valueOf(opt.modelData))
                }
            }
        }
    }
}
