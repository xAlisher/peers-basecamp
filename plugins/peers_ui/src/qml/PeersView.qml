import QtQuick
import QtQuick.Layouts

import Peers

//
// Peers — entry view (metadata.json "view").
//
// THE ONE LINE THAT MATTERS: `logos.module("peers_ui")`. Without it every
// backend call is a silent no-op while the UI renders perfectly, which is the
// single most expensive mistake available in this codebase. `logos.callModule`
// does NOT reach universal cores — the QtRO replica is the only path.
//
// Layout is the Status-desktop three-panel skeleton wearing the Peers skin
// (ADR 0005): nav rail · list · detail.
//
Rectangle {
    id: root

    implicitWidth: 1100
    implicitHeight: 720
    color: Theme.canvas

    readonly property var backend: logos.module("peers_ui")
    readonly property bool ready: logos.isViewModuleReady("peers_ui")

    // "chats" | "contacts" | "settings"
    property string section: "chats"

    // Parsed once per change rather than on every delegate binding.
    property var conversations: []
    property var messages: []

    function reparse() {
        if (!backend)
            return;
        try {
            conversations = JSON.parse(backend.conversationsJson || "[]");
        } catch (e) {
            conversations = [];
        }
        try {
            messages = JSON.parse(backend.messagesJson || "[]");
        } catch (e) {
            messages = [];
        }
    }

    Connections {
        target: logos
        function onViewModuleReadyChanged() {
            if (root.ready)
                root.reparse();
        }
    }

    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onConversationsJsonChanged() { root.reparse(); }
        function onMessagesJsonChanged() { root.reparse(); }
        function onError(message) { errorStrip.show(message); }
        function onSendFailed(conversationId, content) {
            // Hand the text back rather than losing it.
            composer.text = content;
        }
    }

    Component.onCompleted: reparse()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── left: nav rail ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 72
            color: Theme.pane

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Theme.space4
                anchors.bottomMargin: Theme.space4
                spacing: Theme.space2

                Repeater {
                    model: [
                        { key: "chats", glyph: "chats" },
                        { key: "contacts", glyph: "contacts" },
                        { key: "settings", glyph: "settings" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.alignment: Qt.AlignHCenter
                        width: 44
                        height: 44
                        radius: Theme.radiusCard
                        color: root.section === modelData.key ? Theme.panel : "transparent"

                        PeersIcon {
                            anchors.centerIn: parent
                            name: modelData.glyph
                            size: 22
                            color: root.section === modelData.key ? Theme.accent : Theme.textDim
                        }
                        TapHandler { onTapped: root.section = modelData.key }
                    }
                }

                Item { Layout.fillHeight: true }

                // Your own identity.
                HexAvatar {
                    Layout.alignment: Qt.AlignHCenter
                    size: 36
                    seed: root.backend ? (root.backend.myAddress || "") : ""
                    kind: "contact"
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.backend ? (root.backend.myLabel || "") : ""
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                }
            }
        }

        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: Theme.hairline; color: Theme.border }

        // ── middle: list ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 320
            color: Theme.pane

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Header with the connection state — honest about what it is.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.headerHeight
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space4
                        anchors.rightMargin: Theme.space3
                        Text {
                            Layout.fillWidth: true
                            text: root.section === "chats" ? "peers"
                                  : (root.section === "contacts" ? "Contacts" : "Settings")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.brandSize
                            font.weight: Font.Bold
                        }
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: root.backend && root.backend.chatStatus === 2
                                   ? Theme.accent : Theme.pulse
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairline; color: Theme.border }

                ListView {
                    id: convoList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    visible: root.section === "chats"
                    model: root.conversations

                    delegate: ConversationRow {
                        required property var modelData
                        width: convoList.width
                        convo: modelData
                        selected: root.backend
                                  && root.backend.currentConversationId === modelData.convoId
                        onClicked: root.backend.selectConversation(modelData.convoId)
                    }

                    EmptyState {
                        anchors.fill: parent
                        visible: convoList.count === 0
                        glyph: "chats"
                        title: "No conversations yet"
                        hint: "Share your address so someone can reach you, or start one from Contacts."
                    }
                }

                EmptyState {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.section !== "chats"
                    glyph: root.section === "contacts" ? "contacts" : "settings"
                    title: root.section === "contacts" ? "Contacts" : "Settings"
                    hint: "Not wired up yet."
                }
            }
        }

        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: Theme.hairline; color: Theme.border }

        // ── right: detail ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            color: Theme.canvas

            readonly property bool hasConversation:
                root.backend && root.backend.currentConversationId !== ""

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Thread header
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.headerHeight
                    visible: parent.parent.hasConversation
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space4
                        spacing: Theme.space3
                        HexAvatar {
                            size: 32
                            seed: root.backend ? root.backend.currentConversationId : ""
                            kind: root.backend && root.backend.currentIsGroup ? "group" : "contact"
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.backend ? (root.backend.currentDisplayName || "") : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.titleSize
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.hairline
                    color: Theme.border
                    visible: parent.parent.hasConversation
                }

                ListView {
                    id: thread
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Theme.space4
                    clip: true
                    spacing: Theme.space2
                    visible: parent.parent.hasConversation
                    model: root.messages
                    // Newest at the bottom, and stay there as messages arrive.
                    onCountChanged: positionViewAtEnd()

                    delegate: MessageBubble {
                        required property var modelData
                        width: thread.width
                        msg: modelData
                        // Folded control markers (reactions, pins, avatar
                        // broadcasts) must never occupy a bubble.
                        visible: modelData.folded !== true
                        height: visible ? implicitHeight : 0
                    }
                }

                EmptyState {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !parent.parent.hasConversation
                    glyph: "chats"
                    title: "Select a conversation"
                    hint: root.backend && root.backend.myAddress
                          ? "Your address: " + root.backend.myAddress : ""
                }

                Composer {
                    id: composer
                    Layout.fillWidth: true
                    Layout.margins: Theme.space4
                    visible: parent.parent.hasConversation
                    placeholder: root.backend
                                 ? "Message " + (root.backend.currentDisplayName || "")
                                 : "Message"
                    onSend: function (body) {
                        logos.watch(
                            root.backend.sendMessage(root.backend.currentConversationId, body),
                            function () {},
                            function (err) { errorStrip.show(String(err)); });
                    }
                }
            }
        }
    }

    // ── error strip ─────────────────────────────────────────────────────────
    Rectangle {
        id: errorStrip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: visible ? 36 : 0
        visible: message !== ""
        color: Theme.errorFill
        border.width: Theme.hairline
        border.color: Theme.errorBorder

        property string message: ""
        function show(m) { message = m; hideTimer.restart(); }

        Timer { id: hideTimer; interval: 6000; onTriggered: errorStrip.message = "" }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space4
            anchors.rightMargin: Theme.space2
            Text {
                Layout.fillWidth: true
                text: errorStrip.message
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.labelSize
                elide: Text.ElideRight
            }
            PeersIcon {
                name: "close"
                size: 16
                color: Theme.textDim
                TapHandler { onTapped: errorStrip.message = "" }
            }
        }
    }
}
