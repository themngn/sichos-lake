pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var apps: []
    property bool ready: false

    property Process indexer: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/list-apps.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apps = JSON.parse(text)
                } catch (e) {
                    root.apps = []
                }
                root.ready = true
            }
        }
    }

    // Re-scans .desktop files. list-apps.py only runs once at quickshell
    // startup otherwise, so anything installed afterwards (e.g. via
    // sichos-setup.sh) wouldn't show up in the launcher until a full
    // quickshell restart — Launcher.qml calls this whenever it opens instead.
    function refresh() {
        indexer.running = false
        indexer.running = true
    }

    Component.onCompleted: refresh()
}
