import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

// Peers' empty/loading treatment: a centred glyph, a title and a quiet hint.
Item {
    id: root

    property string glyph: "chats"
    property string title: ""
    property string hint: ""

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.space6 * 2, 360)
        spacing: Theme.space3

        PeersIcon {
            Layout.alignment: Qt.AlignHCenter
            name: root.glyph
            size: 40
            color: Theme.textFaint
        }
        Text {
            Layout.fillWidth: true
            visible: root.title !== ""
            text: root.title
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: root.hint !== ""
            text: root.hint
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.labelSize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
