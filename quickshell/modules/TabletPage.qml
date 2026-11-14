import QtQuick
import Quickshell

// Pen tablet page of the Control Center (QuickSettings.qml, popupId
// "qs-tablet"; the Pen tablet tile opens it, so does the chevron on the
// Display page's Pen tablet row). Everything is TabletSettings, i.e.
// Hyprland's own tablet options: which display the pen draws on, keeping
// the display's proportions, how much of the tablet is used, rotation,
// pen (absolute) vs. mouse (relative) mode, the pressure range, hiding
// the cursor while drawing, and the side buttons' bindings -- each button
// row opens a list of actions in place of the page (`editing`), so the
// card never grows for it. Settings apply as they change.
MorphContent {
    id: page
    property real contentWidth: 360
    signal back()

    implicitWidth: page.contentWidth + 2 * Theme.surfacePadding
    implicitHeight: (page.editing ? chooser.implicitHeight : column.implicitHeight) + 2 * Theme.surfacePadding

    // "" = the page, "upper"/"lower" = that button's action list.
    property string editing: ""
    onShownChanged: {
        page.editing = ""
        if (page.shown) TabletSettings.refresh()
    }

    function pct(v) { return Math.round(v * 100) + "%" }

    // A Segmented when the choices fit one row (All + up to three
    // monitors), else a list.
    readonly property var outputOptions: [{ value: "", label: "All" }]
        .concat(TabletSettings.monitors.map(m => ({ value: m.name, label: m.friendly })))

    Column {
        id: chooser
        visible: page.editing !== ""
        anchors.centerIn: parent
        width: page.contentWidth
        spacing: Theme.sectionSpacing

        PageHeader {
            title: page.editing === "upper" ? "Upper button" : "Lower button"
            onBack: page.editing = ""
        }

        Column {
            width: parent.width
            spacing: 6
            Repeater {
                model: page.editing ? TabletSettings.actionsFor(page.editing) : []
                PageRow {
                    required property var modelData
                    readonly property string current: page.editing === "upper" ? TabletSettings.upperButton : TabletSettings.lowerButton
                    compact: true
                    glyph: modelData.glyph
                    title: modelData.id === "default" ? (page.editing === "upper" ? "Eraser" : "Middle click") : modelData.label
                    subtitle: modelData.id === "default" ? "What the pen does by itself" : modelData.hint
                    selected: current === modelData.id
                    active: current === modelData.id
                    onClicked: {
                        TabletSettings.setButton(page.editing, modelData.id)
                        page.editing = ""
                    }
                }
            }
        }
    }

    Column {
        id: column
        visible: page.editing === ""
        anchors.centerIn: parent
        width: page.contentWidth
        spacing: Theme.sectionSpacing

        PageHeader {
            title: "Pen tablet"
            onBack: page.back()
        }

        PageRow {
            clickable: false
            glyph: "\u{f04f7}" // nf-md-tablet
            active: TabletSettings.connected
            title: TabletSettings.tabletName || "Pen tablet"
            subtitle: [TabletSettings.connected ? (TabletSettings.bus ? "Connected · " + TabletSettings.bus : "Connected") : "Not connected",
                TabletSettings.sizeKnown ? Math.round(TabletSettings.tabletWidth) + " × " + Math.round(TabletSettings.tabletHeight) + " mm" : ""]
                .filter(t => t).join(" · ")
        }

        Column {
            width: parent.width
            spacing: 6
            SectionLabel { text: "Display" }
            Segmented {
                visible: page.outputOptions.length <= 4
                width: parent.width
                options: page.outputOptions
                current: TabletSettings.output
                onPicked: (v) => TabletSettings.setOutput(v)
            }
            Repeater {
                model: page.outputOptions.length > 4 ? page.outputOptions : []
                PageRow {
                    required property var modelData
                    compact: true
                    glyph: "\u{f0379}"
                    title: modelData.value === "" ? "All displays" : modelData.label
                    subtitle: modelData.value
                    selected: TabletSettings.output === modelData.value
                    onClicked: TabletSettings.setOutput(modelData.value)
                }
            }
        }

        Column {
            width: parent.width
            spacing: 6
            SectionLabel { text: "Area" }
            PageRow {
                glyph: "\u{f0a24}" // nf-md-aspect_ratio
                title: "Keep proportions"
                subtitle: !TabletSettings.sizeKnown ? "Tablet size unknown"
                    : TabletSettings.relative ? "Not used in mouse mode"
                    : TabletSettings.keepRatio ? "Circles stay round" : "Whole tablet, stretched"
                available: TabletSettings.sizeKnown && !TabletSettings.relative
                active: TabletSettings.keepRatio
                onClicked: TabletSettings.setKeepRatio(!TabletSettings.keepRatio)
                Switch {
                    checked: TabletSettings.keepRatio
                    onToggled: TabletSettings.setKeepRatio(!TabletSettings.keepRatio)
                }
            }
            // 30%..100% of the tablet, centred: less hand movement.
            SliderRow {
                width: parent.width
                opacity: TabletSettings.sizeKnown ? 1 : 0.45
                enabled: TabletSettings.sizeKnown
                glyph: "\u{f0a24}"
                hasMore: false
                value: (TabletSettings.area - 0.3) / 0.7
                valueText: page.pct(TabletSettings.area)
                onMoved: (v) => TabletSettings.setArea(0.3 + v * 0.7)
            }
        }

        // Side by side: one row less, which is what makes room for Buttons.
        Row {
            width: parent.width
            spacing: 10
            Column {
                width: (parent.width - 10) * 0.62
                spacing: 6
                SectionLabel { text: TabletSettings.rotation === 180 ? "Rotation · left-handed" : "Rotation" }
                Segmented {
                    width: parent.width
                    options: [{ value: 0, label: "0°" }, { value: 90, label: "90°" },
                        { value: 180, label: "180°" }, { value: 270, label: "270°" }]
                    current: TabletSettings.rotation
                    onPicked: (v) => TabletSettings.setRotation(v)
                }
            }
            Column {
                width: (parent.width - 10) * 0.38
                spacing: 6
                SectionLabel { text: "Mode" }
                Segmented {
                    width: parent.width
                    options: [{ value: false, label: "Pen" }, { value: true, label: "Mouse" }]
                    current: TabletSettings.relative
                    onPicked: (v) => TabletSettings.setRelative(v)
                }
            }
        }

        Column {
            width: parent.width
            spacing: 6
            SectionLabel { text: "Buttons" }
            Repeater {
                model: ["upper", "lower"]
                PageRow {
                    required property string modelData
                    readonly property string id_: modelData === "upper" ? TabletSettings.upperButton : TabletSettings.lowerButton
                    compact: true
                    glyph: (TabletSettings.actions.find(a => a.id === id_) || {}).glyph || "\u{f03ea}"
                    title: modelData === "upper" ? "Upper button" : "Lower button"
                    subtitle: TabletSettings.actionLabel(modelData)
                    active: id_ !== "default"
                    chevron: true
                    onClicked: page.editing = modelData
                    onMore: page.editing = modelData
                }
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Item {
                width: parent.width
                height: pressureLabel.implicitHeight
                SectionLabel {
                    id: pressureLabel
                    text: "Pressure"
                }
                Text {
                    visible: TabletSettings.pressureMin > 0 || TabletSettings.pressureMax < 1
                    anchors.right: parent.right
                    anchors.baseline: pressureLabel.baseline
                    text: "Reset"
                    color: resetArea.containsMouse ? Theme.text : Theme.textDim
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 3
                    MouseArea {
                        id: resetArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: TabletSettings.resetPressure()
                    }
                }
            }
            // libinput's pressure range: below the minimum counts as no
            // pressure, at the maximum it's full -- a lower maximum makes a
            // light hand reach full strokes.
            Text {
                text: "Full pressure at"
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
            SliderRow {
                width: parent.width
                glyph: "\u{f03ea}" // nf-md-pen
                hasMore: false
                value: (TabletSettings.pressureMax - 0.3) / 0.7
                valueText: page.pct(TabletSettings.pressureMax)
                onMoved: (v) => TabletSettings.setPressureMax(0.3 + v * 0.7)
            }
            Text {
                text: "Ignore light touches below"
                color: Theme.textMuted
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 3
            }
            SliderRow {
                width: parent.width
                glyph: "\u{f03ea}"
                hasMore: false
                value: TabletSettings.pressureMin / 0.3
                valueText: page.pct(TabletSettings.pressureMin)
                onMoved: (v) => TabletSettings.setPressureMin(v * 0.3)
            }
        }

        PageRow {
            glyph: "\u{f01c0}" // nf-md-cursor_default
            title: "Hide cursor while drawing"
            subtitle: TabletSettings.hideCursor ? "Pointer hidden near the pen" : "Off"
            active: TabletSettings.hideCursor
            onClicked: TabletSettings.setHideCursor(!TabletSettings.hideCursor)
            Switch {
                checked: TabletSettings.hideCursor
                onToggled: TabletSettings.setHideCursor(!TabletSettings.hideCursor)
            }
        }
    }
}
