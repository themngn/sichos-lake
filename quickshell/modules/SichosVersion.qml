pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which SichOS version this machine runs, for the Control Center's Version
// tile: `update.sh info` (one JSON line) from the repo checkout that deploys
// it. The deployed config doesn't know where that checkout is; update.sh
// records it in ~/.local/state/sichos/repo on every run. Re-read when
// update.sh pokes the "sichosversion" IPC target after a deploy (FileView
// can't see its stamps change: they're replaced by rename), and every 30s
// while the Control Center is open -- that run also refreshes origin if the
// last fetch is over 10 minutes old, for the "behind origin" count.
QtObject {
    id: root

    // update.sh info's fields, all strings (see cmd_info); null until read
    property var info: null
    readonly property bool known: info !== null && info.deployed !== ""
    readonly property string repo: _repoFile.text().trim()

    readonly property bool pinned: known && info.pinned !== ""
    readonly property int behindHead: known ? Number(info.behind_head) || 0 : 0
    readonly property int behindOrigin: known ? Number(info.behind) || 0 : 0
    readonly property int aheadOrigin: known ? Number(info.ahead) || 0 : 0
    readonly property int dirty: known ? Number(info.dirty) || 0 : 0
    readonly property int conflicts: known ? Number(info.conflicts) || 0 : 0
    readonly property int systemPending: known ? Number(info.system_pending) || 0 : 0
    readonly property bool hooks: known && info.hooks === "1"
    // Uncommitted files deployed by `update.sh try`
    readonly property int live: known ? Number(info.live) || 0 : 0
    // The deployed commit isn't what the checkout is on: pinned, or a deploy
    // failed / hooks are off
    readonly property bool offHead: known && info.deployed !== info.head
    // What to call the deployed version: a tag on it, the pin, else the branch
    readonly property string name: !known ? "" : info.tag || info.pinned || (offHead ? info.deployed_branches.split(" ")[0] : info.branch) || "detached"
    // Things worth a look, in the order the tile shows them
    readonly property var flags: !known ? [] : [
        root.pinned ? "pinned" : root.offHead ? (root.behindHead > 0 ? root.behindHead + " behind HEAD" : "not HEAD") : "",
        root.live > 0 ? root.live + " uncommitted live" : "",
        root.behindOrigin > 0 ? root.behindOrigin + " to pull" : "",
        root.aheadOrigin > 0 ? root.aheadOrigin + " to push" : "",
        root.conflicts > 0 ? root.conflicts + (root.conflicts === 1 ? " parked edit" : " parked edits") : "",
        root.systemPending > 0 ? root.systemPending + " system" : "",
        !root.hooks ? "auto-update off" : ""
    ].filter(t => t !== "")

    // "5 min ago" for an ISO time
    function ago(iso) {
        if (!iso) return ""
        const s = Math.max(0, (Date.now() - Date.parse(iso)) / 1000)
        if (s < 60) return "just now"
        if (s < 3600) return Math.floor(s / 60) + " min ago"
        if (s < 86400) return Math.floor(s / 3600) + " h ago"
        const d = Math.floor(s / 86400)
        return d === 1 ? "yesterday" : d + " days ago"
    }

    property bool _again: false
    function refresh(fetch) {
        if (root.repo === "") return
        // A poke while a run is going (e.g. right after a deploy) runs once more after it
        if (root._proc.running) { root._again = true; return }
        root._proc.command = [root.repo + "/update.sh", "info"].concat(fetch ? ["--fetch"] : [])
        root._proc.running = true
    }

    // update.sh status + recent commits in a terminal: the full picture
    function openDetails() {
        if (root.repo === "") return
        Quickshell.execDetached(["kitty", "--hold", "--directory", root.repo, "sh", "-c",
            "./update.sh status; echo; ./update.sh list 12"])
    }

    readonly property bool _open: ShellState.activePopup === "quicksettings"

    property FileView _repoFile: FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/sichos/repo"
        printErrors: false
        onLoaded: root.refresh(false)
    }

    property Process _proc: Process {
        onExited: if (root._again) { root._again = false; root.refresh(false) }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.info = JSON.parse(text) } catch (e) { }
            }
        }
    }

    property Timer _poll: Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: root._open
        onTriggered: root.refresh(true)
    }

    property IpcHandler _ipc: IpcHandler {
        target: "sichosversion"
        function refresh(): void {
            root._repoFile.reload()
            root.refresh(false)
        }
    }
}
