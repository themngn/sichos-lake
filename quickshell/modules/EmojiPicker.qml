import QtQuick
import Quickshell
import Quickshell.Io

// SUPER+PERIOD: Android-style emoji picker -- a grid in category sections
// with a tab strip to jump between them, Recent first, skin tones and the
// family/kiss/couple combinations behind long-press / right-click / Tab (the
// last pick remembered per emoji, like Gboard).
// The pick is typed into the focused window and copied.
PickerWindow {
    id: picker
    title: "Emoji"
    placeholder: "Search emoji"
    cardWidth: 520
    cardHeight: 600

    readonly property int cellSize: 46

    // Android's categories: Unicode's "Smileys & Emotion" and "People &
    // Body" are one tab there, and the "Component" group (bare skin-tone/
    // hair swatches) isn't pickable at all.
    readonly property var categories: [
        { id: "recent",     name: "Recently Used",     icon: "\u{f0150}", groups: [] },
        { id: "smileys",    name: "Smileys & People",  icon: "\u{f01f5}", groups: ["Smileys & Emotion", "People & Body"] },
        { id: "nature",     name: "Animals & Nature",  icon: "\u{f03e9}", groups: ["Animals & Nature"] },
        { id: "food",       name: "Food & Drink",      icon: "\u{f025a}", groups: ["Food & Drink"] },
        { id: "travel",     name: "Travel & Places",   icon: "\u{f010b}", groups: ["Travel & Places"] },
        { id: "activities", name: "Activities",        icon: "\u{f0806}", groups: ["Activities"] },
        { id: "objects",    name: "Objects",           icon: "\u{f0336}", groups: ["Objects"] },
        { id: "symbols",    name: "Symbols",           icon: "\u{f02d5}", groups: ["Symbols"] },
        { id: "flags",      name: "Flags",             icon: "\u{f023b}", groups: ["Flags"] }
    ]

    // unicode-emoji's emoji-test.txt (packages.txt), not a list vendored
    // here, so it tracks whatever Unicode version Fedora ships. Only
    // "fully-qualified" entries (the others are the same emoji minus the
    // variation selector). Like Gboard, one cell per emoji, everything else
    // behind its long-press:
    //  - Skin tones fold into `variants`: strip the tone modifiers
    //    (U+1F3FB..1F3FF) and FE0F from the code sequence and what's left is
    //    the base's key. They always follow their base in the file.
    //  - The "family: …", "kiss: …" and "couple with heart: …" compositions
    //    (26 families, 4 kiss/couple gender pairs) fold into the plain 👪/💏/
    //    💑 cell's `forms`, each form keeping its own tone variants.
    //  - Mixed-tone two-person sequences ("kiss: person, person, light skin
    //    tone, dark skin tone", "handshake: light skin tone, …") have no
    //    untoned sequence with their key -- they're built from different
    //    code points than 💏/🤝 -- so they're matched by name instead.
    property var emojiItems: []
    property var byEmoji: ({})

    // Twemoji (the preferred emoji font, fontconfig/conf.d/55-sichos-
    // twemoji.conf) only goes up to Emoji 14; anything newer it would either
    // miss or, for ZWJ sequences, split into separate glyphs (🧑‍🧑‍🧒 as three
    // heads). Those are drawn with Noto by name instead -- the fontconfig
    // rule only redirects the generic "emoji" family, not explicit Noto.
    readonly property real twemojiVersion: 14
    property var newEmoji: ({})
    function emojiFont(e) {
        return picker.newEmoji[e] ? "Noto Color Emoji" : Theme.uiFontFamily
    }
    FileView {
        id: emojiFile
        path: "/usr/share/unicode/emoji/emoji-test.txt"
        printErrors: false
        onLoaded: {
            const items = []
            const byKey = {}
            const byName = {}
            const byEmoji = {}
            const formOf = /^(family|kiss|couple with heart): /
            let group = ""
            // "1F600 ; fully-qualified # 😀 E1.0 grinning face"
            const re = /^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E([\d.]+)\s+(.+)$/
            const newEmoji = {}
            for (const l of emojiFile.text().split("\n")) {
                if (l.startsWith("# group: ")) { group = l.slice(9); continue }
                if (group === "Component") continue
                const match = re.exec(l)
                if (!match) continue
                const m = [match[0], match[1], match[2], match[4]]
                if (parseFloat(match[3]) > picker.twemojiVersion) newEmoji[m[2]] = true
                const codes = m[1].split(" ").map(c => parseInt(c, 16))
                const toned = codes.some(c => c >= 0x1F3FB && c <= 0x1F3FF)
                const key = codes.filter(c => c !== 0xFE0F && !(c >= 0x1F3FB && c <= 0x1F3FF)).join(" ")
                if (toned) {
                    const base = byKey[key] || byName[m[3].split(":")[0]]
                    if (base) base.variants.push(m[2])
                    continue
                }
                const item = { emoji: m[2], name: m[3], group: group, variants: [], forms: [] }
                byKey[key] = item
                byName[item.name] = item
                items.push(item)
            }
            // A second pass: since Emoji 15.1 the plain 👪 is listed *after*
            // its compositions, so the base isn't known yet when they're read.
            const kept = []
            for (const item of items) {
                const fm = formOf.exec(item.name)
                if (fm && byName[fm[1]]) {
                    byName[fm[1]].forms.push(item)
                    continue
                }
                byEmoji[item.emoji] = item
                kept.push(item)
            }
            picker.emojiItems = kept
            picker.newEmoji = newEmoji
            picker.byEmoji = byEmoji
        }
    }

    // Recently used (base emoji, newest first) and the last skin tone
    // picked for each emoji that has them.
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/emoji-recent.json"
        watchChanges: true
        printErrors: false
        onAdapterUpdated: writeAdapter()

        adapter: JsonAdapter {
            id: store
            property var recent: []
            property var tones: ({})
        }
    }
    function displayed(item) {
        return store.tones[item.emoji] || item.emoji
    }

    function itemsFor(cat) {
        if (cat.id === "recent")
            return store.recent.map(e => picker.byEmoji[e]).filter(e => e)
        return picker.emojiItems.filter(e => cat.groups.includes(e.group))
    }

    // The grid flattened into ListView rows: a header row per category and
    // `cols`-wide rows of cells under it (a ListView rather than one Grid,
    // so ~1900 cells aren't all instantiated up front). `cells` is every
    // emoji in display order -- selection is an index into it -- and
    // cellRow maps each back to its row for up/down movement and scrolling.
    // A search drops the sections: one run of results, best match first.
    readonly property int cols: Math.max(1, Math.floor(gridList.width / picker.cellSize))
    readonly property var layout: {
        const rows = []
        const cells = []
        const cellRow = []
        const catRow = {}
        const add = (items, cat) => {
            for (let i = 0; i < items.length; i += picker.cols) {
                const slice = items.slice(i, i + picker.cols)
                for (const it of slice) { cellRow.push(rows.length); cells.push(it) }
                rows.push({ header: "", cat: cat, start: cells.length - slice.length, cells: slice })
            }
        }
        const words = picker.query.toLowerCase().split(/\s+/).filter(w => w)
        if (words.length) {
            const results = picker.emojiItems
                .map((e, idx) => ({ e: e, idx: idx, hay: [e.name, e.group].concat(e.forms.map(f => f.name)).join(" ").toLowerCase() }))
                .filter(x => words.every(w => x.hay.includes(w)))
                .sort((a, b) => (b.e.name.toLowerCase().startsWith(words[0]) - a.e.name.toLowerCase().startsWith(words[0])) || a.idx - b.idx)
                .map(x => x.e)
            add(results, "")
        } else {
            for (const cat of picker.categories) {
                const items = picker.itemsFor(cat)
                if (!items.length) continue
                catRow[cat.id] = rows.length
                rows.push({ header: cat.name, cat: cat.id, start: -1, cells: [] })
                add(items, cat.id)
            }
        }
        return { rows: rows, cells: cells, cellRow: cellRow, catRow: catRow }
    }

    property int selectedIndex: 0
    readonly property var selected: picker.layout.cells[picker.selectedIndex] || null

    function scrollToSelected() {
        const r = picker.layout.cellRow[picker.selectedIndex]
        if (r === undefined) return
        // Bring a section's header along when moving onto its first row.
        if (r > 0 && picker.layout.rows[r - 1].header) gridList.positionViewAtIndex(r - 1, ListView.Contain)
        gridList.positionViewAtIndex(r, ListView.Contain)
    }
    function moveBy(delta) {
        const n = picker.layout.cells.length
        if (!n) return
        picker.selectedIndex = Math.max(0, Math.min(n - 1, picker.selectedIndex + delta))
        picker.scrollToSelected()
    }
    // Up/down keep the column, skipping header rows; a shorter target row
    // (a section's last) clamps to its last cell.
    function moveRow(dir) {
        const rows = picker.layout.rows
        const r = picker.layout.cellRow[picker.selectedIndex]
        if (r === undefined) return
        const col = picker.selectedIndex - rows[r].start
        let t = r + dir
        while (t >= 0 && t < rows.length && rows[t].header) t += dir
        if (t < 0 || t >= rows.length) return
        picker.selectedIndex = rows[t].start + Math.min(col, rows[t].cells.length - 1)
        picker.scrollToSelected()
    }
    function jumpTo(catId) {
        if (picker.query) picker.searchInput.text = ""
        // The cleared query re-lays out the sections first.
        Qt.callLater(() => {
            const r = picker.layout.catRow[catId]
            if (r === undefined) return
            gridList.positionViewAtIndex(r, ListView.Beginning)
            picker.selectedIndex = picker.layout.rows[r + 1].start
        })
    }
    // PageUp/PageDown: previous/next category, like swiping the tab strip.
    function jumpCategory(dir) {
        const ids = picker.categories.map(c => c.id).filter(id => picker.layout.catRow[id] !== undefined)
        const i = ids.indexOf(picker.currentCat)
        const next = ids[Math.max(0, Math.min(ids.length - 1, i + dir))]
        if (next) picker.jumpTo(next)
    }
    // Tab strip highlight follows the scroll position.
    readonly property string currentCat: {
        if (picker.query) return ""
        const y = gridList.contentY
        const idx = gridList.indexAt(4, y + 4)
        const row = picker.layout.rows[idx]
        return row ? row.cat : ""
    }

    function pick(item, variant) {
        if (!item) return
        const chosen = variant || picker.displayed(item)
        if (variant) {
            const tones = Object.assign({}, store.tones)
            if (variant === item.emoji) delete tones[item.emoji]
            else tones[item.emoji] = variant
            store.tones = tones
        }
        store.recent = [item.emoji].concat(store.recent.filter(e => e !== item.emoji)).slice(0, picker.cols * 3)
        picker.close()
        // Typed *and* copied: typing covers the usual "insert it here", the
        // copy covers windows wtype's virtual keyboard doesn't reach
        // (XWayland). The sleep lets keyboard focus return from this layer
        // surface to the app first, or wtype types into nothing.
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy; sleep 0.15; command -v wtype >/dev/null && wtype "$1"', "sh", chosen])
    }

    // ---- Long-press popover ----------------------------------------------

    // The emoji whose popover is open; its forms (bottom row, if any) and
    // the highlighted form's skin tones (above). Keyboard focus is on one
    // of the two grids at a time (toneArea).
    property var toneItem: null
    property int formIndex: 0
    property int toneIndex: 0
    property string toneArea: "tones" // "forms" | "tones"
    readonly property var toneForms: picker.toneItem && picker.toneItem.forms.length ? [picker.toneItem].concat(picker.toneItem.forms) : []
    readonly property var toneForm: picker.toneForms.length ? picker.toneForms[picker.formIndex] : picker.toneItem
    readonly property var toneChoices: picker.toneForm && picker.toneForm.variants.length ? [picker.toneForm.emoji].concat(picker.toneForm.variants) : []
    // Base + 5 tones on one row; two-person emoji (25 tone pairs) and the
    // 26 family forms wrap into a block of up to 6 columns, like Gboard.
    readonly property int formCols: Math.min(6, picker.toneForms.length)
    readonly property int toneCols: Math.min(6, picker.toneChoices.length)
    // Two-person emoji (💏, 💑, 🤝, holding hands, …) get Gboard's two-line
    // selector instead of a 5x5 block: one row of tones per person, plus an
    // untoned option. Each variant's tone modifiers, in order, give the
    // (first, second) person's tone; a single modifier (💏🏻) means both.
    // null when the form isn't two-person (or has no tones).
    function toneSeq(e) {
        const t = []
        for (const ch of e) {
            const c = ch.codePointAt(0)
            if (c >= 0x1F3FB && c <= 0x1F3FF) t.push(c - 0x1F3FB)
        }
        return t
    }
    readonly property var pairMap: {
        if (!picker.toneForm) return null
        const map = {}
        let two = false
        for (const v of picker.toneForm.variants) {
            const t = picker.toneSeq(v)
            if (t.length === 2) { two = true; map[t[0] + "," + t[1]] = v }
            else if (t.length === 1) map[t[0] + "," + t[0]] = v
        }
        return two ? map : null
    }
    // Pair mode's tone grid: 2 rows x 6 columns, column 0 the untoned
    // form (both rows), 1..5 the tones; toneIndex = row * 6 + column.
    // Moving along a row sets that person's tone, the other one stays.
    readonly property int pairCols: 6
    property int tone1: 0
    property int tone2: 0
    readonly property string pairCurrent: picker.pairMap
        ? (picker.toneIndex % picker.pairCols === 0 ? picker.toneForm.emoji : (picker.pairMap[picker.tone1 + "," + picker.tone2] || picker.toneForm.emoji))
        : ""
    onToneIndexChanged: {
        if (!picker.pairMap) return
        const col = picker.toneIndex % picker.pairCols
        if (col === 0) return
        if (picker.toneIndex < picker.pairCols) picker.tone1 = col - 1
        else picker.tone2 = col - 1
    }

    readonly property string toneCurrent: !picker.toneForm ? ""
        : picker.toneArea !== "tones" || !picker.toneChoices.length ? picker.toneForm.emoji
        : picker.pairMap ? picker.pairCurrent
        : picker.toneChoices[picker.toneIndex]
    onFormIndexChanged: picker.toneIndex = 0

    function hasChoices(item) {
        return item.variants.length > 0 || item.forms.length > 0
    }
    function openTones(item, cellItem) {
        if (!item || !picker.hasChoices(item)) return
        picker.toneItem = item
        picker.formIndex = 0
        picker.toneIndex = 0
        picker.tone1 = 0
        picker.tone2 = 0
        picker.toneArea = picker.toneForms.length ? "forms" : "tones"
        // Start on whatever the cell currently shows (the remembered pick).
        const cur = picker.displayed(item)
        const forms = picker.toneForms.length ? picker.toneForms : [item]
        for (let f = 0; f < forms.length; f++) {
            if (forms[f].emoji === cur) { picker.formIndex = f; break }
            const t = forms[f].variants.indexOf(cur)
            if (t >= 0) {
                picker.formIndex = f
                picker.toneArea = "tones"
                if (picker.pairMap) {
                    // Both rows' marks on the remembered pair, focus on the
                    // first person's.
                    const seq = picker.toneSeq(cur)
                    picker.tone1 = seq[0]
                    picker.tone2 = seq.length > 1 ? seq[1] : seq[0]
                    picker.toneIndex = picker.tone1 + 1
                } else {
                    picker.toneIndex = t + 1
                }
                break
            }
        }
        const p = cellItem.mapToItem(bodyRoot, 0, 0)
        tonePopup.anchorX = p.x + cellItem.width / 2
        tonePopup.anchorY = p.y
    }
    // Arrow keys inside the popover: within the focused grid, and across
    // the gap between them (tones sit above forms).
    function toneKey(key) {
        const inForms = picker.toneArea === "forms"
        const n = inForms ? picker.toneForms.length : picker.pairMap ? 2 * picker.pairCols : picker.toneChoices.length
        const cols = inForms ? picker.formCols : picker.pairMap ? picker.pairCols : picker.toneCols
        const idx = inForms ? picker.formIndex : picker.toneIndex
        let next = idx
        if (key === Qt.Key_Left) next = Math.max(0, idx - 1)
        else if (key === Qt.Key_Right) next = Math.min(n - 1, idx + 1)
        else if (key === Qt.Key_Up) {
            if (idx - cols >= 0) next = idx - cols
            else if (inForms && picker.toneChoices.length) { picker.toneArea = "tones"; return }
        } else if (key === Qt.Key_Down) {
            if (idx + cols < n) next = idx + cols
            else if (!inForms && picker.toneForms.length) { picker.toneArea = "forms"; return }
        }
        if (inForms) picker.formIndex = next
        else picker.toneIndex = next
    }
    function closeTones() {
        picker.toneItem = null
    }

    onQueryChanged: {
        picker.closeTones()
        picker.selectedIndex = 0
        gridList.positionViewAtBeginning()
    }
    onOpened: {
        picker.closeTones()
        picker.selectedIndex = 0
        gridList.positionViewAtBeginning()
    }
    onAccepted: {
        if (picker.toneItem) picker.pick(picker.toneItem, picker.toneCurrent)
        else picker.pick(picker.selected)
    }
    onKeyPressed: (event) => {
        if (picker.toneItem) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                picker.toneKey(event.key)
            else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab) picker.closeTones()
            else return
            event.accepted = true
            return
        }
        // Left/Right move through the grid even mid-query: the search box
        // is for a word or two, not for editing.
        if (event.key === Qt.Key_Left) picker.moveBy(-1)
        else if (event.key === Qt.Key_Right) picker.moveBy(1)
        else if (event.key === Qt.Key_Up) picker.moveRow(-1)
        else if (event.key === Qt.Key_Down) picker.moveRow(1)
        else if (event.key === Qt.Key_PageUp) picker.jumpCategory(-1)
        else if (event.key === Qt.Key_PageDown) picker.jumpCategory(1)
        else if (event.key === Qt.Key_Tab) {
            const r = gridList.itemAtIndex(picker.layout.cellRow[picker.selectedIndex])
            const cell = r ? r.cellAt(picker.selectedIndex) : null
            if (cell) picker.openTones(picker.selected, cell)
        } else return
        event.accepted = true
    }

    IpcHandler {
        target: "emoji"
        function toggle() { picker.toggle() }
        function close() { picker.close() }
    }

    Item {
        id: bodyRoot
        anchors.fill: parent

        // Tab strip, Android's row of category icons.
        Row {
            id: tabs
            width: parent.width
            height: Theme.controlHeight + 6

            Repeater {
                model: picker.categories

                Rectangle {
                    id: tab
                    required property var modelData
                    readonly property bool active: picker.currentCat === tab.modelData.id
                    readonly property bool empty: picker.layout.catRow[tab.modelData.id] === undefined && !picker.query
                    width: tabs.width / picker.categories.length
                    height: tabs.height
                    radius: Theme.controlRadius
                    color: tab.active ? Theme.selectedFill : tabMouse.containsMouse && !tab.empty ? Theme.hoverFill : "transparent"

                    HeaderIcon {
                        anchors.centerIn: parent
                        glyph: tab.modelData.icon
                        inkHeight: 16
                        inkWidth: 18
                        color: tab.active ? Theme.text : tab.empty ? Theme.textDim : Theme.textMuted
                        opacity: tab.empty ? 0.5 : 1
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (!tab.empty) picker.jumpTo(tab.modelData.id)
                    }
                }
            }
        }

        Rectangle {
            id: tabRule
            anchors.top: tabs.bottom
            anchors.topMargin: 6
            width: parent.width
            height: 1
            color: Theme.separator
        }

        ListView {
            id: gridList
            anchors {
                top: tabRule.bottom
                topMargin: 4
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            clip: true
            model: picker.layout.rows
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: picker.closeTones()

            delegate: Item {
                id: rowItem
                required property var modelData
                width: gridList.width
                height: rowItem.modelData.header ? 30 : picker.cellSize

                function cellAt(index) {
                    return cellRepeater.itemAt(index - rowItem.modelData.start)
                }

                Text {
                    visible: !!rowItem.modelData.header
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: rowItem.modelData.header
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Row {
                    Repeater {
                        id: cellRepeater
                        model: rowItem.modelData.cells

                        Rectangle {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property int cellIndex: rowItem.modelData.start + cell.index
                            readonly property bool isSelected: cell.cellIndex === picker.selectedIndex
                            width: gridList.width / picker.cols
                            height: picker.cellSize
                            radius: Theme.controlRadius
                            color: cell.isSelected ? Theme.hoverFill : "transparent"
                            border.color: cell.isSelected ? Theme.accent : "transparent"
                            border.width: 1

                            // Inter has no emoji, so Qt falls back to the
                            // fontconfig "emoji" font (Twemoji) -- see emojiFont().
                            Text {
                                anchors.centerIn: parent
                                text: picker.displayed(cell.modelData)
                                font.family: picker.emojiFont(text)
                                font.pixelSize: 28
                            }

                            // Gboard's hint that a long-press has more (tones/forms).
                            Rectangle {
                                visible: picker.hasChoices(cell.modelData)
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 4
                                width: 4
                                height: 4
                                radius: 2
                                color: Theme.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                pressAndHoldInterval: 350
                                property bool held: false
                                onEntered: if (!picker.toneItem) picker.selectedIndex = cell.cellIndex
                                onPressed: held = false
                                onPressAndHold: {
                                    held = true
                                    picker.openTones(cell.modelData, cell)
                                }
                                onClicked: (mouse) => {
                                    if (held) return
                                    if (mouse.button === Qt.RightButton) picker.openTones(cell.modelData, cell)
                                    else if (picker.toneItem) picker.closeTones()
                                    else picker.pick(cell.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: picker.layout.cells.length === 0
            anchors.centerIn: gridList
            text: picker.emojiItems.length ? "No emoji found" : "unicode-emoji isn't installed"
            color: Theme.textDim
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        // Long-press popover, floated above the pressed cell and kept
        // inside the card horizontally. Forms on the bottom row, nearest the
        // cell, so they stay put while the tone block above them resizes
        // with whichever form is highlighted; a fixed width when there are
        // forms for the same reason.
        Squircle {
            id: tonePopup
            property real anchorX: 0
            property real anchorY: 0
            visible: picker.toneItem !== null
            width: Math.max(picker.toneForms.length ? 6 * picker.cellSize : 0, popupColumn.width) + 12
            height: popupColumn.height + 12
            x: Math.max(0, Math.min(bodyRoot.width - width, anchorX - width / 2))
            y: Math.max(0, anchorY - height - 4)
            z: 10
            radius: Theme.surfaceSquircleRadius
            // Solid, not surfaceRaisedFor(): it floats over the card's own
            // content, which the compositor blur (window backdrop only)
            // can't soften -- the glass tint let the grid show through.
            color: Theme.surfaceRaised
            borderColor: Theme.surfaceBorder
            borderWidth: Theme.surfaceBorderWidth

            SurfaceAppear { target: tonePopup; shown: tonePopup.visible; origin: Item.Bottom }

            MouseArea { anchors.fill: parent }

            Column {
                id: popupColumn
                anchors.centerIn: parent
                spacing: 6

                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: picker.toneChoices.length > 0 && !picker.pairMap
                    columns: Math.max(1, picker.toneCols)

                    Repeater {
                        model: picker.toneChoices

                        Rectangle {
                            id: tone
                            required property string modelData
                            required property int index
                            readonly property bool focused: picker.toneArea === "tones" && tone.index === picker.toneIndex
                            width: picker.cellSize
                            height: picker.cellSize
                            radius: Theme.controlRadius
                            color: tone.focused ? Theme.hoverFill : "transparent"
                            border.color: tone.focused ? Theme.accent : "transparent"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: tone.modelData
                                font.family: picker.emojiFont(text)
                                font.pixelSize: 28
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: {
                                    picker.toneArea = "tones"
                                    picker.toneIndex = tone.index
                                }
                                onClicked: picker.pick(picker.toneItem, tone.modelData)
                            }
                        }
                    }
                }

                // Two-line selector (pairMap): untoned on the left, a tone
                // row per person, the resulting emoji previewed on the right.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!picker.pairMap
                    spacing: 6

                    Column {
                        Repeater {
                            model: 2

                            Row {
                                id: pairRow
                                required property int index

                                Repeater {
                                    model: picker.pairCols

                                    Rectangle {
                                        id: swatch
                                        required property int index
                                        readonly property int gridIndex: pairRow.index * picker.pairCols + swatch.index
                                        readonly property bool focused: picker.toneArea === "tones" && picker.toneIndex === swatch.gridIndex
                                        // The tone this row currently has, marked even
                                        // while focus is on the other row.
                                        readonly property bool chosen: swatch.index > 0 && picker.toneIndex % picker.pairCols !== 0
                                            && (pairRow.index === 0 ? picker.tone1 : picker.tone2) === swatch.index - 1
                                        width: picker.cellSize * 0.8
                                        height: picker.cellSize * 0.8
                                        radius: Theme.controlRadius
                                        color: swatch.focused ? Theme.hoverFill : "transparent"
                                        border.color: swatch.focused ? Theme.accent : "transparent"
                                        border.width: 1

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width * 0.55
                                            height: width
                                            radius: width / 2
                                            // Untoned = the default emoji yellow; then
                                            // Fitzpatrick 1-2 .. 6, as on the swatches
                                            // Gboard/iOS show.
                                            color: ["#FFC83D", "#F7DECE", "#F3D2A2", "#D5AB88", "#AF7E57", "#7C533E"][swatch.index]
                                            border.color: swatch.chosen ? Theme.text : Theme.surfaceBorder
                                            border.width: swatch.chosen ? 2 : 1
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: {
                                                picker.toneArea = "tones"
                                                picker.toneIndex = swatch.gridIndex
                                            }
                                            onClicked: picker.pick(picker.toneItem, picker.pairCurrent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: picker.cellSize * 1.6
                        height: picker.cellSize * 1.6
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.controlRadius
                        color: Theme.controlFill

                        Text {
                            anchors.centerIn: parent
                            text: picker.toneArea === "tones" ? picker.pairCurrent : picker.toneForm ? picker.toneForm.emoji : ""
                            font.family: picker.emojiFont(text)
                            font.pixelSize: 44
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: picker.pick(picker.toneItem, picker.toneArea === "tones" ? picker.pairCurrent : picker.toneForm.emoji)
                        }
                    }
                }

                Rectangle {
                    visible: picker.toneChoices.length > 0 && picker.toneForms.length > 0
                    width: 6 * picker.cellSize
                    height: 1
                    color: Theme.separator
                }

                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: picker.toneForms.length > 0
                    columns: Math.max(1, picker.formCols)

                    Repeater {
                        model: picker.toneForms

                        Rectangle {
                            id: form
                            required property var modelData
                            required property int index
                            readonly property bool current: form.index === picker.formIndex
                            readonly property bool focused: form.current && picker.toneArea === "forms"
                            width: picker.cellSize
                            height: picker.cellSize
                            radius: Theme.controlRadius
                            // The form whose tones are shown stays marked
                            // while focus is up in the tone block.
                            color: form.focused ? Theme.hoverFill : form.current ? Theme.controlFill : "transparent"
                            border.color: form.focused ? Theme.accent : "transparent"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: form.modelData.emoji
                                font.family: picker.emojiFont(text)
                                font.pixelSize: 28
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: {
                                    picker.formIndex = form.index
                                    picker.toneArea = "forms"
                                }
                                onClicked: picker.pick(picker.toneItem, form.modelData.emoji)
                            }
                        }
                    }
                }
            }
        }
    }

    footer: Item {
        anchors.fill: parent

        Text {
            anchors.left: parent.left
            anchors.right: hint.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: picker.toneItem ? picker.toneForm.name
                : picker.selected ? picker.selected.name : ""
            color: Theme.textMuted
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            id: hint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: picker.toneItem ? "❯ insert  esc back" : "❯ insert  tab more  esc close"
            color: Theme.textDim
            font.family: Theme.uiFontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
