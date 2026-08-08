import QtQuick
import QtQuick.Layouts

//
// A Peers message bubble.
//
// Own messages are accent-filled with WHITE text — the Android source comment
// is explicit that it is never black. Peer messages are #1F1F1F. Both use a
// uniform 8px radius; Peers does not do the tail-corner trick.
//
// Peers has NO delivered or read receipts (ChatScreen.tsx:3). The only states
// are pending, failed and sent — do not add a tick this app never had.
//
Item {
    id: root

    // One decoded row from messagesJson. Never a raw wire body: the
    // content-marker codec has already run in the backend.
    required property var msg

    readonly property bool own: msg.fromSelf === true
    readonly property string kind: msg.kind !== undefined ? msg.kind : "text"
    readonly property bool failed: msg.state === "failed"
    readonly property bool pending: msg.state === "pending"

    implicitHeight: rowLayout.implicitHeight
    implicitWidth: parent ? parent.width : 0

    RowLayout {
        id: rowLayout
        width: parent.width
        spacing: Theme.space2
        layoutDirection: root.own ? Qt.RightToLeft : Qt.LeftToRight

        // Sender identicon, peer messages only — own messages need no
        // attribution.
        HexAvatar {
            visible: !root.own
            size: 28
            seed: root.msg.sender !== undefined ? root.msg.sender : ""
            kind: "contact"
            Layout.alignment: Qt.AlignBottom
        }

        Rectangle {
            id: bubble
            Layout.maximumWidth: rowLayout.width * Theme.bubbleMaxWidthRatio
            Layout.preferredWidth: content.implicitWidth + Theme.space3 * 2
            implicitHeight: content.implicitHeight + Theme.space2 * 2
            Layout.preferredHeight: implicitHeight

            radius: Theme.radiusBubble
            color: root.own ? Theme.bubbleOwn : Theme.bubblePeer
            // A failed send is outlined, not recoloured — the text must stay
            // readable while the user decides whether to resend.
            border.width: root.failed ? Theme.hairline : 0
            border.color: Theme.unread
            opacity: root.pending ? 0.55 : 1.0

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: Theme.space2
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                spacing: 2

                // Quoted message, for a reply.
                Rectangle {
                    visible: root.kind === "reply"
                    Layout.fillWidth: true
                    implicitHeight: quoted.implicitHeight + Theme.space1 * 2
                    color: Qt.rgba(0, 0, 0, 0.22)
                    radius: 4
                    Text {
                        id: quoted
                        anchors.fill: parent
                        anchors.margins: Theme.space1
                        text: root.msg.text !== undefined ? root.msg.text : ""
                        color: root.own ? Theme.bubbleOwnText : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.labelSize
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.msg.text !== undefined ? root.msg.text : ""
                    color: root.own ? Theme.bubbleOwnText : Theme.bubblePeerText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText   // never render peer text as markup
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.failed ? "failed" : Qt.formatDateTime(
                              new Date(root.msg.timestampMs !== undefined
                                       ? root.msg.timestampMs : 0), "h:mm AP")
                    color: root.failed ? Theme.unread
                           : (root.own ? Qt.rgba(1, 1, 1, 0.75) : Theme.textDim)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                }
            }
        }

        Item { Layout.fillWidth: true }
    }
}
