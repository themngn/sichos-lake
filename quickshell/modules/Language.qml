import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Pill {
    id: root
    property string layoutName: "??"
    // "us,ua" -> ["us", "ua"], plus which index is currently active — both
    // needed by LanguagePopup to render the full list with the active one
    // highlighted, rather than just the single active_keymap name.
    property var layoutCodes: []
    property int activeIndex: -1

    visible: layoutName !== "??"

    Process {
        id: proc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const kbs = data.keyboards || []
                    const kb = kbs.find((k) => k.main) || kbs[0]
                    if (kb) {
                        root.layoutName = kb.active_keymap
                        root.layoutCodes = (kb.layout || "").split(",").filter(c => c.length > 0)
                        root.activeIndex = kb.active_layout_index
                    }
                } catch (e) {
                    // ignore malformed output
                }
            }
        }
    }

    LanguagePopup {
        anchorItem: root
        visible: root.hovered
        codes: root.layoutCodes
        activeIndex: root.activeIndex
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

    BarIcon {
        glyph: {
            const n = root.layoutName.toLowerCase()
            if (n.includes("ukrain")) return "🇺🇦"
            if (n.includes("english") || n.includes("us")) return "🇬🇧"
            return root.layoutName.substring(0, 2).toUpperCase()
        }
        // Not a Nerd Font glyph (flag emoji / plain text), so no ink-height
        // correction -- fixed box width alone is enough for even spacing.
        pixelSize: Theme.fontSize * Theme.barIconScale
        color: Theme.text
    }
}
