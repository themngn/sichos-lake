pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User-created folders in the launcher's Folders menu (Launcher.qml). Only
// custom folders live here — the built-in "Games" (all installed Steam
// titles, from AppIndex's steam-tagged entries) and "Hidden" (HiddenApps)
// folders are computed on the fly there instead, since their membership is
// never manually edited through this file.
QtObject {
    id: root

    function create(name) {
        const id = "f" + Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(36)
        adapter.folders = adapter.folders.concat([{ id: id, name: name, apps: [] }])
        return id
    }
    function hasApp(id, appName) {
        const f = adapter.folders.find(f => f.id === id)
        return !!f && f.apps.indexOf(appName) !== -1
    }
    function addApp(id, appName) {
        adapter.folders = adapter.folders.map(f =>
            f.id === id && f.apps.indexOf(appName) === -1
                ? { id: f.id, name: f.name, apps: f.apps.concat([appName]) }
                : f)
    }
    function removeApp(id, appName) {
        adapter.folders = adapter.folders.map(f =>
            f.id === id ? { id: f.id, name: f.name, apps: f.apps.filter(n => n !== appName) } : f)
    }
    function toggleApp(id, appName) {
        if (root.hasApp(id, appName)) root.removeApp(id, appName)
        else root.addApp(id, appName)
    }
    function isInAnyFolder(appName) {
        return adapter.folders.some(f => f.apps.indexOf(appName) !== -1)
    }

    // An app added to a folder is hidden from the flat Apps list by
    // default (same idea as Games/Hidden) — this is the per-app override
    // that keeps it showing there too. Meaningless (and ignored by
    // Launcher.qml's appItems filter) for an app that isn't in any folder.
    function keepsInRoot(appName) {
        return adapter.keepInRoot.indexOf(appName) !== -1
    }
    function toggleKeepInRoot(appName) {
        if (root.keepsInRoot(appName)) adapter.keepInRoot = adapter.keepInRoot.filter(n => n !== appName)
        else adapter.keepInRoot = adapter.keepInRoot.concat([appName])
    }

    readonly property var folders: adapter.folders

    property FileView view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/app-folders.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property var folders: []
            property var keepInRoot: []
        }
    }
}
