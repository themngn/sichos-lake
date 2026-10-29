import QtQuick

// A section heading inside a card ("NETWORKS", "OUTPUT") -- the same small
// bold caps as the launcher's rail and list group headings, so the shell's
// sections read alike everywhere. Titles stay bold Inter at fontSize.
Text {
    color: Theme.textDim
    font.family: Theme.uiFontFamily
    font.pixelSize: Theme.fontSize - 3
    font.bold: true
    font.letterSpacing: 1
    font.capitalization: Font.AllUppercase
    bottomPadding: 4
}
