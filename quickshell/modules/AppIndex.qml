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

    Component.onCompleted: indexer.running = true
}
