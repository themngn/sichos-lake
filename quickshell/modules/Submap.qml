import QtQuick
import Quickshell.Hyprland

Pill {
    id: root
    property string submapName: ""
    visible: submapName.length > 0

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submapName = event.data
        }
    }

    Text {
        text: root.submapName
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.italic: true
        color: Theme.submap
    }
}
