pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The paired phone's launcher apps, for the launcher's phone folder
// (Launcher.qml): [{package, label, icon}] from `sichlink apps`, icon being a
// PNG the daemon wrote under $XDG_RUNTIME_DIR. Asking the phone takes ~5s
// (it draws every icon), so the last answer is kept in a cache file next to
// those icons -- same lifetime -- and shown right away while a fresh one
// loads.
QtObject {
    id: root
    property var apps: []
    property bool loading: false

    property Process _proc: Process {
        command: Sichlink.cmd(["apps"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text)
                    if (Array.isArray(list)) {
                        root.apps = list
                        root._cache.setText(text)
                    }
                } catch (e) {
                    // Daemon down or the phone didn't answer: keep the last list.
                }
            }
        }
        onExited: root.loading = false
    }

    // The launcher calls this whenever the folder is opened.
    function refresh() {
        if (root._proc.running) return
        root.loading = true
        root._proc.running = true
    }

    property FileView _cache: FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sichos-phone-apps.json"
        printErrors: false
        onLoaded: {
            try {
                if (root.apps.length === 0) root.apps = JSON.parse(text())
            } catch (e) {}
        }
    }
}
