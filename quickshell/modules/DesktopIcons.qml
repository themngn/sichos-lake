pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AppIcons.js" as AppIcons

// Builds a window-class -> icon-theme-name lookup by scanning installed
// .desktop files for their StartupWMClass (or falling back to the desktop
// file's own basename), so most apps get a correct icon automatically
// without needing a hand-maintained map.
QtObject {
    id: root

    property var wmClassMap: ({})
    property var baseNameMap: ({})
    // Same keys, the .desktop Name= instead of Icon= (PowerMenu's
    // "waiting for apps to close" list shows "Telegram", not
    // "org.telegram.desktop").
    property var wmClassNames: ({})
    property var baseNames: ({})
    property bool ready: false

    readonly property string _indexScript: `
shopt -s nullglob
for f in /usr/share/applications/*.desktop /usr/local/share/applications/*.desktop \
         "$HOME"/.local/share/applications/*.desktop \
         /var/lib/flatpak/exports/share/applications/*.desktop \
         "$HOME"/.local/share/flatpak/exports/share/applications/*.desktop; do
  base="$(basename "$f" .desktop)"
  icon="$(awk -F= '/^Icon=/{print $2; exit}' "$f")"
  wmclass="$(awk -F= '/^StartupWMClass=/{print $2; exit}' "$f")"
  name="$(awk -F= '/^Name=/{print $2; exit}' "$f")"
  printf '%s\x1f%s\x1f%s\x1f%s\n' "$base" "$wmclass" "$icon" "$name"
  # Steam generates a per-game .desktop file (Icon=steam_icon_<appid>) with
  # no StartupWMClass at all, but the game's actual runtime window class is
  # always steam_app_<appid> — derive that mapping directly from the icon
  # name instead of leaving it to fall through to a generic exe icon.
  case "$icon" in
    steam_icon_*)
      printf '%s\x1f%s\x1f%s\n' "$base" "steam_app_\${icon#steam_icon_}" "$icon"
      ;;
  esac
done
`

    property Process indexer: Process {
        command: ["bash", "-c", root._indexScript]
        stdout: StdioCollector {
            onStreamFinished: root._parseIndex(text)
        }
    }

    function _parseIndex(text) {
        const wmMap = {}
        const baseMap = {}
        const wmNames = {}
        const baseNames = {}
        const lines = text.split("\n")
        for (const line of lines) {
            if (!line) continue
            const parts = line.split("")
            if (parts.length < 3) continue
            const base = parts[0].toLowerCase()
            const wmclass = parts[1].toLowerCase()
            const icon = parts[2]
            const name = parts[3] || ""
            if (name) {
                if (base && !baseNames[base]) baseNames[base] = name
                if (wmclass && !wmNames[wmclass]) wmNames[wmclass] = name
            }
            if (!icon) continue
            if (base) baseMap[base] = icon
            if (wmclass) wmMap[wmclass] = icon
        }
        root.wmClassMap = wmMap
        root.baseNameMap = baseMap
        root.wmClassNames = wmNames
        root.baseNames = baseNames
        root.ready = true
    }

    function iconNameForClass(cls) {
        if (!cls) return ""
        const key = cls.toLowerCase()

        if (root.wmClassMap[key]) return root.wmClassMap[key]
        if (root.baseNameMap[key]) return root.baseNameMap[key]
        if (AppIcons.classIconMap[key]) return AppIcons.classIconMap[key]

        // reverse-DNS style classes (org.mozilla.firefox) - try the last segment
        const lastDot = key.lastIndexOf(".")
        if (lastDot >= 0) {
            const tail = key.substring(lastDot + 1)
            if (root.wmClassMap[tail]) return root.wmClassMap[tail]
            if (root.baseNameMap[tail]) return root.baseNameMap[tail]
        }

        return key
    }

    // Display name for a window class, same lookup order as
    // iconNameForClass; the class itself when no .desktop file matches.
    function nameForClass(cls) {
        if (!cls) return ""
        const key = cls.toLowerCase()
        const tail = key.substring(key.lastIndexOf(".") + 1)
        return root.wmClassNames[key] || root.baseNames[key]
            || root.wmClassNames[tail] || root.baseNames[tail] || cls
    }

    function iconPathForClass(cls) {
        const name = iconNameForClass(cls)
        if (!name) return ""

        let path = Quickshell.iconPath(name)
        if (path) return path

        if (cls && cls.toLowerCase() !== name) {
            path = Quickshell.iconPath(cls.toLowerCase())
            if (path) return path
        }

        return Quickshell.iconPath("application-x-executable")
    }

    Component.onCompleted: indexer.running = true
}
