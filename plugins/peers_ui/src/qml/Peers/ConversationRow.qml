import QtQuick
import QtQuick.Layouts

// A conversation-list row: identicon, display name, preview, timestamp.
// 64px tall, matching Peers' `layout.conversationRow`.
Rectangle {
    id: root

    required property var convo
    property bool selected: false

    signal clicked()

    implicitHeight: Theme.conversationRowHeight
    color: selected ? Theme.panel
           : (hover.hovered ? Qt.lighter(Theme.pane, 1.25) : "transparent")

    // The selected row carries an accent edge, as Peers does.
    Rectangle {
        visible: root.selected
        width: 2
        height: parent.height
        color: Theme.accent
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: root.clicked() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space3
        spacing: Theme.space3

        HexAvatar {
            size: 40
            seed: root.convo.avatarSeed !== undefined ? root.convo.avatarSeed : ""
            kind: root.convo.avatarKind !== undefined ? root.convo.avatarKind : "contact"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.convo.displayName !== undefined ? root.convo.displayName : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                // Already run through the marker codec — "📷 Photo", not a raw
                // "img1:…" string.
                text: root.convo.preview !== undefined ? root.convo.preview : ""
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.labelSize
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        Text {
            Layout.alignment: Qt.AlignTop
            visible: root.convo.lastActivityMs > 0
            text: Qt.formatDateTime(new Date(root.convo.lastActivityMs || 0), "h:mm AP")
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.hairline
        color: Theme.border
        opacity: 0.5
    }
}
