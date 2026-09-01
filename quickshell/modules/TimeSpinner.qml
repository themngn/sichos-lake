import QtQuick

// Arrow-driven HH/MM spinner used twice by SunsetPopup.qml (day/night time).
Row {
    id: spinner
    required property int value
    required property int max
    property int step: 1
    signal changed(int newValue)

    spacing: 4
    height: 30

    Text {
        width: 30
        height: 30
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: spinner.value < 10 ? "0" + spinner.value : "" + spinner.value
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        color: Theme.text
    }

    Column {
        width: 16
        height: 30

        Text {
            width: 16
            height: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "▲"
            font.pixelSize: 9
            color: upArea.containsMouse ? Theme.accent : Theme.textMuted

            MouseArea {
                id: upArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: spinner.changed((spinner.value + spinner.step) % (spinner.max + 1))
            }
        }
        Text {
            width: 16
            height: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "▼"
            font.pixelSize: 9
            color: downArea.containsMouse ? Theme.accent : Theme.textMuted

            MouseArea {
                id: downArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: spinner.changed((spinner.value - spinner.step + spinner.max + 1) % (spinner.max + 1))
            }
        }
    }
}
