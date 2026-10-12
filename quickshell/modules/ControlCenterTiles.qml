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
        return root.pack(root._list())
    }

    // `list`: [{id, w, h}] in order.
    function pack(list) {
        const occ = []
        const free = (r, c) => !(occ[r] && occ[r][c])
        const pos = {}
        let rows = 0
        for (const t of list) {
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
                    pos[t.id] = { r: r, c: c, w: w, h: h }
                    rows = Math.max(rows, r + h)
                    placed = true
                }
            }
        }
        return { pos: pos, rows: rows }
    }
    function _list() {
        const out = []
        for (let i = 0; i < root.model.count; i++) {
            const t = root.model.get(i)
            out.push({ id: t.tileId, w: t.w, h: t.h })
        }
        return out
    }

    // The list index that makes first-fit put `id` (at size w x h) nearest
    // the grid cell (r, c) -- fractional while a tile is dragged; `ry` is
    // row height / column width so the distance is in real proportions.
    // Every candidate keeps the other tiles in their order, so the answer
    // depends only on where the tile is, not on the order earlier steps of
    // the same drag produced. The old "swap with whatever tile is under the
    // pointer" did depend on it: with tiles of different sizes a swap put
    // the pointer over another tile, which swapped back, and so on.
    // `slack` (in columns): keep the current index unless another one is
    // that much closer, so a tile halfway between two slots doesn't flicker.
    function nearestIndex(id, w, h, r, c, ry, slack) {
        const others = root._list()
        const cur = others.findIndex(t => t.id === id)
        if (cur === -1) return -1
        others.splice(cur, 1)
        const me = { id: id, w: w, h: h }
        let best = cur, bestD = Infinity, curD = Infinity
        for (let k = 0; k <= others.length; k++) {
            const cand = others.slice()
            cand.splice(k, 0, me)
            const p = root.pack(cand).pos[id]
            const d = Math.hypot((p.r - r) * ry, p.c - c)
            if (k === cur) curD = d
            if (d < bestD - 1e-6) { bestD = d; best = k }
        }
        return bestD < curD - slack ? best : cur
    }
    // Resize, keeping the tile at (r, c) -- where it was when the resize
    // started -- if any order allows it. Plain first-fit would push a tile
    // that grew past a neighbour onto the next row, away from the pointer
    // dragging its edge; refilling a hole when it shrinks does the same.
    function resizeAt(id, w, h, r, c) {
        root.setSize(id, w, h)
        root.move(id, root.nearestIndex(id, Math.max(1, Math.min(root.columns, w)),
            Math.max(1, Math.min(root.maxRows, h)), r, c, 1, 0))
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
        // `wide` is the older 1x1/2x1-only format. "link" (Phone Link) was
        // merged into "phone": it takes that place unless "phone" is there too.
        const ids = list.map(t => t.id)
        for (const t of list) {
            const id = t.id === "link" && ids.indexOf("phone") === -1 ? "phone" : t.id
            if (root.allIds.indexOf(id) !== -1 && root.indexOf(id) === -1)
                root.model.append({ tileId: id, w: t.w || (t.wide ? 2 : 1), h: t.h || 1 })
        }
        root._revision++
    }
    function _changed() {
        root._revision++
        saveTimer.restart()
    }
    property bool _saving: false
    // A drag changes the order/size many times; write the file once it
    // settles rather than on every step.
    property Timer saveTimer: Timer {
        id: saveTimer
        interval: 400
        onTriggered: {
            root._saving = true
            adapter.tiles = root._list()
        }
    }

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
