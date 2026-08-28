import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Pill {
    id: root
    property string layoutName: "??"

    visible: layoutName !== "??"

    tooltipText: root.layoutName

    Process {
        id: proc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const kbs = data.keyboards || []
                    const kb = kbs.find((k) => k.main) || kbs[0]
                    if (kb) root.layoutName = kb.active_keymap
                } catch (e) {
                    // ignore malformed output
                }
            }
        }
    }

    function refresh() { proc.running = true }
    Component.onCompleted: refresh()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") root.refresh()
        }
    }

    onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "current", "next"])

    Text {
        text: {
            const n = root.layoutName.toLowerCase()
            if (n.includes("ukrain")) return "🇺🇦"
            if (n.includes("english") || n.includes("us")) return "🇬🇧"
            return root.layoutName.substring(0, 2).toUpperCase()
        }
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }
}
