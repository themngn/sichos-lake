import QtQuick

// "Now Playing" toast for Spotify: for a few seconds after a track change
// (or a resume) it takes the place of the workspaces in the bar's left
// section -- Bar.qml swaps the two -- and types "artist: title" in. It used
// to be its own full-width Overlay window covering the whole bar with a
// 128px cover poking out below; now it's one line, no cover, and the clock,
// toggles and right-side widgets stay visible. All the state (Spotify
// tracking, typing animation, visibility) lives in the shared
// NowPlayingState singleton, so every screen's bar stays in lockstep.
Item {
    id: root

    // Longest the line may get before it elides, set by Bar.qml so it never
    // runs into the clock/toggle row in the middle.
    property real maxWidth: 400

    readonly property string fullText: NowPlayingState.shownPrefix + NowPlayingState.shownAnimated

    function _span(t, c, bold) {
        if (t === "") return ""
        const esc = t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        return "<font color=\"" + c + "\">" + (bold ? "<b>" + esc + "</b>" : esc) + "</font>"
    }

    implicitHeight: Theme.barHeight
    implicitWidth: row.implicitWidth

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // nf-fa-spotify. Font Awesome glyphs ink ~860/1000em in the Mono
        // build (approximate, not measured into a table) -- scaled to the
        // shared bar icon height so it matches the right-side icons.
        Text {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: Theme.fontFamily
            // 1.35x the right-side icons' size: matched to them it read too
            // small beside the text.
            font.pixelSize: Theme.barIconInkHeight * 1.35 * 1000 / 860
            color: Theme.accent
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            // Width follows the typed text (so the slot grows as it types)
            // up to maxWidth, then elides.
            width: Math.min(implicitWidth, Math.max(0, root.maxWidth - icon.width - row.spacing))
            elide: Text.ElideRight
            // Artist muted, title bold in full text colour, the ": " between
            // them dim. Split by position (NowPlayingState.shownArtist is the
            // artist of the line on screen), so it works mid-animation too.
            textFormat: Text.StyledText
            text: {
                const full = root.fullText
                const n = NowPlayingState.shownArtist.length
                if (n === 0 || !full.startsWith(NowPlayingState.shownArtist.slice(0, Math.min(n, full.length))))
                    return root._span(full, Theme.text, true)
                return root._span(full.slice(0, n), Theme.textMuted, false)
                    + root._span(full.slice(n, n + 2), Theme.textDim, false)
                    + root._span(full.slice(n + 2), Theme.text, true)
            }
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.text
        }
    }
}
