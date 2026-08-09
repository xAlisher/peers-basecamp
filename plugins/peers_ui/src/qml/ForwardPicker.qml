import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

// Pick a conversation to forward a message into. Android lists every
// conversation (ForwardPicker.tsx); so does this.
Item {
    id: root

    property var conversations: []
    // Excluded from the list — forwarding into the thread you are already in is
    // never what was meant.
    property string excludeConvoId: ""

    signal picked(string convoId)
    signal cancelled()

    anchors.fill: parent
    visible: false
    z: 60

    function open()  { visible = true; }
    function close() { visible = false; root.cancelled(); }

    readonly property var targets: conversations.filter(function (c) {
        return c && c.convoId !== root.excludeConvoId;
    })

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    TapHandler { onTapped: root.close() }

    Rectangle {
        anchors.centerIn: parent
        width: 420
        height: Math.min(root.height - Theme.space6 * 2, 460)
        radius: Theme.radiusCard
        color: Theme.panel
        border.width: Theme.hairline
        border.color: Theme.border
        TapHandler { onTapped: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space3

            Text {
                text: "Forward to"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize
                font.weight: Font.Medium
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: root.targets
                    delegate: Rectangle {
                        required property var modelData
                        width: list.width
                        height: 56
                        color: hov.hovered ? Qt.lighter(Theme.panel, 1.3) : "transparent"
                        radius: 4
                        HoverHandler { id: hov }
                        TapHandler {
                            onTapped: { root.visible = false; root.picked(modelData.convoId); }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            spacing: Theme.space3
                            HexAvatar {
                                size: 32
                                seed: modelData.avatarSeed !== undefined ? modelData.avatarSeed : ""
                                kind: modelData.avatarKind !== undefined ? modelData.avatarKind : "contact"
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.displayName !== undefined ? modelData.displayName : ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySize
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                EmptyState {
                    anchors.fill: parent
                    visible: list.count === 0
                    glyph: "chats"
                    title: "No other conversations"
                    hint: "Start one first, then you can forward into it."
                }
            }
        }
    }
}
