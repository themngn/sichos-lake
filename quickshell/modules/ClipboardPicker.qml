import QtQuick
import Quickshell
import Quickshell.Io

// SUPER+SHIFT+V: cliphist history, newest first, images as thumbnails.
// Enter copies the pick back onto the clipboard; Shift+Delete forgets it.
PickerWindow {
    id: picker
    title: "Clipboard"
    placeholder: "Search clipboard"

    property int selectedIndex: 0

    // clipboard-list.py's output: newest first, images pre-decoded to
    // thumbnail files. Re-read on every open (and after a delete); the
    // previous list stays up meanwhile, so the picker never opens empty.
    property var clipItems: []
    function refresh() {
        listProc.running = false
        listProc.running = true
    }
    Process {
        id: listProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/clipboard-list.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { picker.clipItems = JSON.parse(text) } catch (e) { picker.clipItems = [] }
            }
        }
    }

    // Every query word must appear somewhere; recency order is kept -- the
    // newest match is nearly always the one wanted.
    readonly property var filtered: {
        const words = picker.query.toLowerCase().split(/\s+/).filter(w => w)
        if (!words.length) return picker.clipItems
        return picker.clipItems.filter(c => {
            const t = c.text.toLowerCase()
            return words.every(w => t.includes(w))
        })
    }
    onQueryChanged: {
        picker.selectedIndex = 0
        list.positionViewAtBeginning()
    }
    // Keep the selection on a real row when a delete shortens the list.
    onFilteredChanged: {
        if (picker.selectedIndex >= picker.filtered.length)
            picker.selectedIndex = Math.max(0, picker.filtered.length - 1)
    }

    function move(delta) {
        picker.selectedIndex = Math.max(0, Math.min(picker.filtered.length - 1, picker.selectedIndex + delta))
        list.positionViewAtIndex(picker.selectedIndex, ListView.Contain)
    }
    function pick(item) {
        if (!item) return
        picker.close()
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "sh", item.line])
    }
    function remove(item) {
        if (!item) return
        removeProc.command = ["sh", "-c", 'printf "%s" "$1" | cliphist delete', "sh", item.line]
        removeProc.running = true
    }
    Process {
        id: removeProc
        onExited: picker.refresh()
    }

    onOpened: {
        picker.selectedIndex = 0
        list.positionViewAtBeginning()
        picker.refresh()
    }
    onAccepted: picker.pick(picker.filtered[picker.selectedIndex])
    onKeyPressed: (event) => {
        if (event.key === Qt.Key_Down) picker.move(1)
        else if (event.key === Qt.Key_Up) picker.move(-1)
        else if (event.key === Qt.Key_PageDown) picker.move(5)
        else if (event.key === Qt.Key_PageUp) picker.move(-5)
        else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) picker.remove(picker.filtered[picker.selectedIndex])
        else return
        event.accepted = true
    }

    IpcHandler {
        target: "clipboard"
        function toggle() { picker.toggle() }
        function close() { picker.close() }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: picker.filtered

        WheelHandler {
            onWheel: (event) => picker.move(event.angleDelta.y < 0 ? 1 : -1)
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isImage: !!row.modelData.image
            width: list.width
            height: row.isImage ? 84 : 44
            radius: Theme.controlRadius
            color: row.index === picker.selectedIndex ? Theme.hoverFill : "transparent"

            Row {
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    text: row.index === picker.selectedIndex ? "❯" : ""
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                }

                Rectangle {
                    visible: row.isImage
                    anchors.verticalCenter: parent.verticalCenter
                    width: thumb.paintedWidth + 2
                    height: thumb.paintedHeight + 2
                    radius: 4
                    color: Theme.controlFill
                    border.color: Theme.surfaceBorder
                    border.width: 1

                    Image {
                        id: thumb
                        anchors.centerIn: parent
                        width: 200
                        height: 68
                        source: row.isImage ? "file://" + row.modelData.image : ""
                        sourceSize.height: 136
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    // Images get their format/size caption; multi-line
                    // text clips stay one line, newlines shown as ⏎.
                    text: row.isImage ? row.modelData.info : row.modelData.text.replace(/\n/g, " ⏎ ")
                    color: row.isImage ? Theme.textDim : Theme.text
                    font.family: Theme.uiFontFamily
                    font.pixelSize: row.isImage ? Theme.fontSize - 2 : Theme.fontSize + 1
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: picker.selectedIndex = row.index
                onClicked: picker.pick(row.modelData)
            }
        }
    }

    footer: Text {
        anchors.fill: parent
        text: picker.filtered.length ? "↑↓ move  ❯ copy  shift+del remove  esc close"
            : picker.clipItems.length ? "No matches" : "Clipboard history is empty"
        color: Theme.textDim
        font.family: Theme.uiFontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
