import QtQuick
import Quickshell

// Gaming Focus popup for GameFocusToggle.qml: On/Off switch plus the dim
// amount slider. Same MorphContent shape as SunsetPopup.qml
// (see its comment on HoverHandler vs. a background MouseArea). Reads/writes
// GameFocus directly -- it's a singleton, so there's no per-screen state to
// thread through signals the way SunsetPopup's props mirror ShellState.
MorphContent {
    id: popup
    // Set when the Control Center embeds this as one of its pages: the
    // header's back button returns there.
    property string backPopupId: ""
    // Wider when embedded, to match the Control Center card.
    property real contentWidth: Theme.togglePopupWidth



    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    Item {
        id: bg
        anchors.fill: parent

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            PageHeader {
                width: popup.contentWidth
                title: "Game Focus"
                showBack: popup.backPopupId !== ""
                onBack: ShellState.activePopup = popup.backPopupId
                Switch {
                    checked: GameFocus.enabled
                    onToggled: GameFocus.enabled = !GameFocus.enabled
                }
            }

            PageRow {
                width: popup.contentWidth
                clickable: false
                glyph: "\u{f02b4}"
                glyphInkWidth: 24
                active: GameFocus.enabled
                title: !GameFocus.enabled ? "Off" : GameFocus.dimming ? "Game focused" : "Waiting for a game"
                subtitle: !GameFocus.enabled ? "Dims the other screens while a game has focus"
                    : GameFocus.dimming ? "On " + GameFocus.gameMonitor + " · other screens dimmed"
                    : "Other screens dim once a fullscreen game has focus"
            }

            // Dim amount, 5% steps. Takes effect live on any currently
            // dimmed screen (the overlay binds straight to dimAmount).
            Column {
                width: popup.contentWidth
                spacing: 2
                SectionLabel {
                    text: "Dim other screens"
                }
                SliderRow {
                    width: parent.width
                    glyph: "\u{f00de}" // nf-md-brightness_4
                    hasMore: false
                    dim: !GameFocus.enabled
                    value: (GameFocus.dimAmount - GameFocus.minDim) / (GameFocus.maxDim - GameFocus.minDim)
                    valueText: Math.round(GameFocus.dimAmount * 100) + "%"
                    onMoved: (v) => GameFocus.setDimAmount(GameFocus.minDim + v * (GameFocus.maxDim - GameFocus.minDim))
                }
            }
        }
    }
}
