import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

//
// Per-message actions. On Android these live behind a 350 ms long-press on the
// bubble; on the desktop the same menu opens on right-click (and on a long
// press, so a touchscreen behaves the way the phone does).
//
// Item order follows BubbleActionMenu.tsx:111-235 exactly — see
// docs/FEATURE-INVENTORY.md §4.1. Rows are gated the way Android gates them, and
// where Android's gate looks like a bug the comment says so rather than quietly
// "fixing" it, because the two clients are meant to behave the same.
//
Item {
    id: root

    // The decoded message row this menu acts on.
    property var msg: ({})
    // Whether the local account may pin in this conversation. Android v1 allows
    // only the group creator; a caller that cannot determine it passes false.
    property bool canPin: false
    // Whether this conversation is a group — "Send message" only makes sense
    // there, since a 1:1 already IS that thread.
    property bool isGroup: false
    // Whether the peer already has a label, which flips Add/Edit.
    property bool hasLabel: false

    readonly property string kind: msg.kind !== undefined ? msg.kind : "text"
    readonly property bool incoming: msg.fromSelf !== true
    readonly property string peerAddress: msg.sender !== undefined ? msg.sender : ""
    readonly property bool addressKnown: incoming && peerAddress !== ""
    readonly property bool isImage: kind === "photo"
    readonly property bool isVoice: kind === "voice"
    readonly property bool isHosted: kind === "media"
    readonly property bool isLocation: kind === "location"

    signal react(string emoji)
    signal openEmojiGrid()
    signal reply()
    signal editLabel()
    signal copyAddress()
    signal forward()
    signal saveMedia()
    signal openInMaps()
    signal copyMessage()
    signal sendMessageTo()
    signal pin(bool on)
    signal deleteForMe()
    signal closed()

    anchors.fill: parent
    visible: false
    z: 50

    function openAt(x, y) {
        // Keep the card on screen when the click is near an edge.
        card.x = Math.max(Theme.space2, Math.min(x, root.width - card.width - Theme.space2));
        card.y = Math.max(Theme.space2, Math.min(y, root.height - card.height - Theme.space2));
        visible = true;
    }
    function close() { visible = false; root.closed(); }

    // Android's quick-reaction palette, in order (reactions.ts:117).
    readonly property var palette: ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    // Click-away closes. Anything inside the card stops the event.
    TapHandler { onTapped: root.close() }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }

    Rectangle {
        id: card
        width: 250
        implicitHeight: col.implicitHeight + Theme.space2 * 2
        height: implicitHeight
        radius: Theme.radiusCard
        color: Theme.panel
        border.width: Theme.hairline
        border.color: Theme.border

        TapHandler { onTapped: {} }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.space2
            spacing: 0

            // ── quick reactions, as the menu header ─────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.space1
                spacing: 0

                Repeater {
                    model: root.palette
                    delegate: Item {
                        required property string modelData
                        Layout.fillWidth: true
                        implicitHeight: 36
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            // Emoji here are CONTENT, not iconography.
                            font.pixelSize: 22
                        }
                        TapHandler {
                            onTapped: { root.close(); root.react(modelData); }
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                    }
                    TapHandler { onTapped: { root.close(); root.openEmojiGrid(); } }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: Theme.hairline; color: Theme.border }

            // ── rows, in Android's order ────────────────────────────────────
            Repeater {
                model: [
                    { key: "reply",   icon: "reply",  label: "Reply",
                      show: true, danger: false },
                    { key: "label",   icon: "userplus",
                      label: root.hasLabel ? "Edit label" : "Add label",
                      show: root.addressKnown, danger: false },
                    { key: "copyaddr", icon: "copy",  label: "Copy address",
                      show: root.addressKnown, danger: false },
                    { key: "forward", icon: "send",   label: "Forward",
                      show: true, danger: false },
                    { key: "save",    icon: "download", label: "Save to disk",
                      show: root.isImage || root.isHosted || root.isVoice, danger: false },
                    { key: "maps",    icon: "search", label: "Open in maps",
                      show: root.isLocation, danger: false },
                    // Hosted raw markers contain a decryption key and fetch
                    // capability. They remain backend-only and never reach QML.
                    { key: "copymsg", icon: "copy",
                      label: root.isLocation ? "Copy coordinates" : "Copy message",
                      show: !root.isImage && !root.isVoice && !root.isHosted, danger: false },
                    { key: "sendto",  icon: "chats",  label: "Send message",
                      show: root.incoming && root.isGroup, danger: false },
                    { key: "pin",     icon: "pin",
                      label: root.msg.pinned === true ? "Unpin" : "Pin",
                      show: root.canPin, danger: false },
                    { key: "delete",  icon: "trash",  label: "Delete for me",
                      show: true, danger: true }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.show ? 40 : 0
                    visible: modelData.show
                    color: rowHover.hovered ? Qt.lighter(Theme.panel, 1.3) : "transparent"
                    radius: 4

                    HoverHandler { id: rowHover }
                    TapHandler {
                        onTapped: {
                            root.close();
                            const k = modelData.key;
                            if (k === "reply") root.reply();
                            else if (k === "label") root.editLabel();
                            else if (k === "copyaddr") root.copyAddress();
                            else if (k === "forward") root.forward();
                            else if (k === "save") root.saveMedia();
                            else if (k === "maps") root.openInMaps();
                            else if (k === "copymsg") root.copyMessage();
                            else if (k === "sendto") root.sendMessageTo();
                            else if (k === "pin") root.pin(root.msg.pinned !== true);
                            else if (k === "delete") root.deleteForMe();
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        spacing: Theme.space3

                        PeersIcon {
                            name: modelData.icon
                            size: 18
                            color: modelData.danger ? Theme.unread : Theme.textDim
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: modelData.danger ? Theme.unread : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodySize
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
