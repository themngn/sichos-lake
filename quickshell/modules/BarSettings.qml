pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which optional right-side tray widgets are shown, and in what order,
// editable from the launcher's Settings > Bar Widgets folder (drag to
// reorder, click to toggle on/off). AI Model Usage defaults off on a fresh
// install; everything else here defaults on. Persisted the
// same way AutostartApps/HiddenApps are — only state that differs from the
// default is ever written to disk.
//
// Night Light and Stay Awake (SunsetToggle/IdleToggle, next to the clock)
// deliberately aren't covered here — they're a fixed pair in their own Row
// in Bar.qml, and Stay Awake already has its own toggle in the launcher's
// Toggles folder.
QtObject {
    id: root

    readonly property var widgets: [
        { id: "ai-model-usage", name: "AI Model Usage" },
        { id: "notifications", name: "Notification Center" },
        { id: "tray", name: "Tray" },
        { id: "language", name: "Keyboard Layout" },
        { id: "bluetooth", name: "Bluetooth" },
        { id: "network", name: "Network" },
        { id: "volume", name: "Volume" },
        { id: "backlight", name: "Backlight" },
        { id: "powerprofile", name: "Power Profile" },
        { id: "battery", name: "Battery" }
    ]

    function _canonId(id) {
        return id === "claude-usage" ? "ai-model-usage" : id
    }

    function isEnabled(id) {
        const c = _canonId(id)
        return adapter.disabled.indexOf(c) === -1 && adapter.disabled.indexOf("claude-usage") === -1
    }
    function enable(id) {
        const c = _canonId(id)
        adapter.disabled = adapter.disabled.filter(n => n !== c && n !== "claude-usage")
    }
    function disable(id) {
        const c = _canonId(id)
        if (root.isEnabled(c)) adapter.disabled = adapter.disabled.concat([c])
    }
    function toggle(id) {
        if (root.isEnabled(id)) root.disable(id)
        else root.enable(id)
    }

    // All widget ids in the user's chosen order — any id missing from the
    // saved order (a fresh install, or a widget added after the user's last
    // reorder) is appended at the end in its default widgets[] order.
    function orderedIds() {
        const allIds = root.widgets.map(w => w.id)
        const normalizedOrder = adapter.order.map(id => _canonId(id))
        const known = normalizedOrder.filter(id => allIds.indexOf(id) !== -1)
        const uniqueKnown = known.filter((id, index) => known.indexOf(id) === index)
        const missing = allIds.filter(id => uniqueKnown.indexOf(id) === -1)
        return uniqueKnown.concat(missing)
    }

    function moveUp(id) {
        const ids = root.orderedIds()
        const i = ids.indexOf(id)
        if (i <= 0) return
        const tmp = ids[i - 1]
        ids[i - 1] = ids[i]
        ids[i] = tmp
        adapter.order = ids
    }
    function moveDown(id) {
        const ids = root.orderedIds()
        const i = ids.indexOf(id)
        if (i === -1 || i >= ids.length - 1) return
        const tmp = ids[i + 1]
        ids[i + 1] = ids[i]
        ids[i] = tmp
        adapter.order = ids
    }

    property FileView view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/bar-settings.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: adapter
            property var disabled: ["claude-usage"]
            property var order: ["claude-usage", "tray", "language", "bluetooth", "network",
                                  "volume", "backlight", "powerprofile", "battery", "notifications"]
        }
    }
}
