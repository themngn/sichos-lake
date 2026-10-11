pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which tiles the Control Center (QuickSettings.qml) shows, in what order
// and at what size (w 1-4 columns x h 1-2 rows), edited Android-style from
// its edit mode.
// Persisted to ~/.config/quickshell/control-center.json.
//
// The live list is a ListModel, not a JS array: edit mode reorders it while
// a tile is being dragged, and a Repeater over an array rebuilds every
// delegate on each change -- destroying the very MouseArea doing the drag.
// ListModel.move() moves the existing delegates instead.
QtObject {
    id: root

    // Every tile that exists, in the order "Add tiles" lists them.
    readonly property var allIds: ["wifi", "bluetooth", "airplane", "nightlight", "silence", "micmute",
        "awake", "gamefocus", "hdr", "opaque", "phone", "powerprofile", "sound", "display",
        "update", "vpn", "stats"]
    readonly property int columns: 4
    readonly property int maxRows: 2
    readonly property var defaults: [
        { id: "wifi", w: 2, h: 1 }, { id: "bluetooth", w: 2, h: 1 },
        { id: "hdr", w: 1, h: 1 }, { id: "gamefocus", w: 2, h: 1 }, { id: "micmute", w: 1, h: 1 },
        { id: "nightlight", w: 1, h: 1 }, { id: "awake", w: 1, h: 1 }, { id: "stats", w: 2, h: 1 },
        { id: "update", w: 4, h: 1 },
        { id: "silence", w: 1, h: 1 }, { id: "opaque", w: 2, h: 1 }, { id: "phone", w: 1, h: 1 }
    ]

    property ListModel model: ListModel {}

    // First-fit placement on the 4-column grid, in list order: each tile
    // takes the first row/column where its w x h block is free.
    // {pos: {id: {r, c, w, h}}, rows}
    readonly property var layout: {
        void root._revision
        const occ = []
        const free = (r, c) => !(occ[r] && occ[r][c])
        const pos = {}
        let rows = 0
        for (let i = 0; i < root.model.count; i++) {
            const t = root.model.get(i)
            const w = Math.max(1, Math.min(root.columns, t.w)), h = Math.max(1, Math.min(root.maxRows, t.h))
            let placed = false
            for (let r = 0; !placed; r++) {
                for (let c = 0; c + w <= root.columns && !placed; c++) {
                    let fits = true
                    for (let dr = 0; dr < h && fits; dr++)
                        for (let dc = 0; dc < w && fits; dc++) fits = free(r + dr, c + dc)
                    if (!fits) continue
                    for (let dr = 0; dr < h; dr++) {
                        occ[r + dr] = occ[r + dr] || []
                        for (let dc = 0; dc < w; dc++) occ[r + dr][c + dc] = true
                    }
                    pos[t.tileId] = { r: r, c: c, w: w, h: h }
                    rows = Math.max(rows, r + h)
                    placed = true
                }
            }
        }
        return { pos: pos, rows: rows }
    }

    readonly property var unused: {
        void root._revision
        const used = []
        for (let i = 0; i < root.model.count; i++) used.push(root.model.get(i).tileId)
        return root.allIds.filter(id => used.indexOf(id) === -1)
    }
    // Bumped on every change so `unused` re-evaluates (ListModel content
    // changes don't notify a JS binding that only called get()).
    property int _revision: 0

    function indexOf(id) {
        for (let i = 0; i < root.model.count; i++) if (root.model.get(i).tileId === id) return i
        return -1
    }
    function move(id, toIndex) {
        const from = root.indexOf(id)
        if (from === -1 || toIndex < 0 || toIndex >= root.model.count || from === toIndex) return
        root.model.move(from, toIndex, 1)
        root._changed()
    }
    function setSize(id, w, h) {
        const i = root.indexOf(id)
        if (i === -1) return
        w = Math.max(1, Math.min(root.columns, w))
        h = Math.max(1, Math.min(root.maxRows, h))
        const t = root.model.get(i)
        if (t.w === w && t.h === h) return
        root.model.setProperty(i, "w", w)
        root.model.setProperty(i, "h", h)
        root._changed()
    }
    function remove(id) {
        const i = root.indexOf(id)
        if (i === -1) return
        root.model.remove(i)
        root._changed()
    }
    function add(id) {
        if (root.indexOf(id) !== -1) return
        root.model.append({ tileId: id, w: 1, h: 1 })
        root._changed()
    }
    function reset() {
        root._fill(root.defaults)
        root._changed()
    }

    function _fill(list) {
        root.model.clear()
        // `wide` is the older 1x1/2x1-only format.
        for (const t of list)
            if (root.allIds.indexOf(t.id) !== -1)
                root.model.append({ tileId: t.id, w: t.w || (t.wide ? 2 : 1), h: t.h || 1 })
        root._revision++
    }
    function _changed() {
        root._revision++
        const out = []
        for (let i = 0; i < root.model.count; i++) {
            const t = root.model.get(i)
            out.push({ id: t.tileId, w: t.w, h: t.h })
        }
        root._saving = true
        adapter.tiles = out
    }
    property bool _saving: false

    property FileView view: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/control-center.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        // Fill once from disk (or the defaults). Not on our own writes: that
        // would rebuild the model mid-drag.
        onLoaded: if (!root._saving) root._fill(adapter.tiles.length > 0 ? adapter.tiles : root.defaults)
        onLoadFailed: root._fill(root.defaults)

        adapter: JsonAdapter {
            id: adapter
            property var tiles: []
        }
    }
}
