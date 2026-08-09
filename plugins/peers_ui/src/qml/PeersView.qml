import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "Theme.js" as Theme

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

    // Guarded exactly as every working local module does it. `logos` is not
    // guaranteed to exist when the view is created, and an unguarded reference
    // throws at creation time, which kills the whole view.
    readonly property var backend: (typeof logos !== "undefined" && logos.module)
                                   ? logos.module("peers_ui") : null
    readonly property bool ready: backend !== null
                                  && typeof logos !== "undefined"
                                  && logos.isViewModuleReady
                                  && logos.isViewModuleReady("peers_ui")

    // "chats" | "contacts" | "settings"
    property string section: "chats"

    // ChatStatus.Online == 2 in the .rep enum.
    readonly property bool online: backend !== null && backend.chatStatus === 2

    // Parsed once per change rather than on every delegate binding.
    property var conversations: []
    property var messages: []
    property var contacts: []
    property var members: []
    property var settings: ({})
    property var pinned: ({})

    // Whether the right pane shows the group-info detail instead of the thread.
    property bool detailsShown: false
    // The image currently open full-size, "" when the viewer is closed.
    property string viewerSource: ""

    // Outcome of the last backup open, as "ok:<convos>:<messages>" or
    // "fail:<reason>". Slot returns cannot cross QtRO, so the backend reports
    // through signals and the view holds the result.
    property string lastBackup: ""


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
        try {
            contacts = JSON.parse(backend.contactsJson || "[]");
        } catch (e) {
            contacts = [];
        }
        try {
            members = JSON.parse(backend.membersJson || "[]");
        } catch (e) {
            members = [];
        }
        try {
            settings = JSON.parse(backend.settingsJson || "{}");
        } catch (e) {
            settings = ({});
        }
        try {
            pinned = JSON.parse(backend.currentPinnedJson || "{}");
        } catch (e) {
            pinned = ({});
        }
    }

    // Every backend call goes through here so a failure always reaches the user
    // instead of vanishing. logos.watch is the only path that surfaces errors.
    function call(promise) {
        logos.watch(promise, function () {}, function (err) { errorStrip.show(String(err)); });
    }

    Connections {
        target: logos
        // Canonical signature — every working module takes (moduleName, isReady).
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "peers_ui" && isReady)
                root.reparse();
        }
    }

    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onConversationsJsonChanged() { root.reparse(); }
        function onMessagesJsonChanged() { root.reparse(); }
        function onContactsJsonChanged() { root.reparse(); }
        function onMembersJsonChanged() { root.reparse(); }
        function onSettingsJsonChanged() { root.reparse(); }
        function onCurrentPinnedJsonChanged() { root.reparse(); }
        function onCurrentConversationIdChanged() { root.detailsShown = false; }
        function onError(message) { errorStrip.show(message); }
        function onBackupOpened(address, conversationCount, messageCount) {
            root.lastBackup = "ok:" + conversationCount + ":" + messageCount;
        }
        function onBackupFailed(reason) {
            root.lastBackup = "fail:" + reason;
            errorStrip.show(reason);
        }
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
                        // New chat. Disabled until the core is Online — a
                        // create_conversation before then fails on the key-package
                        // fetch, and a button that silently does nothing is worse
                        // than one that says it isn't ready.
                        Rectangle {
                            width: 28; height: 28
                            radius: Theme.radiusCard
                            visible: root.section === "chats"
                            color: newChatHover.hovered && root.online
                                   ? Theme.accentHover
                                   : (root.online ? Theme.accent : Theme.panel)
                            HoverHandler { id: newChatHover }
                            TapHandler {
                                enabled: root.online
                                onTapped: newChatDialog.open()
                            }
                            PeersIcon {
                                anchors.centerIn: parent
                                name: "plus"
                                size: 16
                                color: root.online ? Theme.onAccent : Theme.textFaint
                            }
                        }
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: root.online ? Theme.accent : Theme.pulse
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

                ContactsPanel {
                    id: contactsPanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.section === "contacts"
                    contacts: root.contacts
                    myAddress: root.backend ? (root.backend.myAddress || "") : ""
                    myLabel: root.backend ? (root.backend.myLabel || "") : ""
                    onStartChat: function (address) { root.call(root.backend.createConversation(address)); root.section = "chats"; }
                    onRemoveContact: function (address) { root.call(root.backend.removeContact(address)); }
                    onSetLabel: function (address, label) { root.call(root.backend.setContactLabel(address, label)); }
                }

                EmptyState {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.section === "settings"
                    glyph: "settings"
                    title: "Settings"
                    hint: "Choose a setting on the right."
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
                    visible: root.section === "chats" && parent.parent.hasConversation
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
                        // Group info toggle — only meaningful for a group.
                        Rectangle {
                            Layout.rightMargin: Theme.space3
                            visible: root.backend && root.backend.currentIsGroup
                            width: 32; height: 32
                            radius: Theme.radiusCard
                            color: root.detailsShown ? Theme.panel : "transparent"
                            PeersIcon {
                                anchors.centerIn: parent
                                name: "groups"; size: 18
                                color: root.detailsShown ? Theme.accent : Theme.textDim
                            }
                            TapHandler { onTapped: root.detailsShown = !root.detailsShown }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.hairline
                    color: Theme.border
                    visible: root.section === "chats" && parent.parent.hasConversation
                }

                PinnedBar {
                    Layout.fillWidth: true
                    visible: parent.parent.hasConversation && !root.detailsShown
                    pinned: root.pinned
                    onUnpin: root.call(root.backend.unpinMessage(root.backend.currentConversationId))
                }

                ListView {
                    id: thread
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Theme.space4
                    clip: true
                    spacing: Theme.space2
                    visible: parent.parent.hasConversation && !root.detailsShown
                    model: root.messages
                    // Newest at the bottom, and stay there as messages arrive.
                    onCountChanged: positionViewAtEnd()

                    delegate: MessageBubble {
                        required property var modelData
                        width: thread.width
                        msg: modelData
                        onImageClicked: function (uri) { root.viewerSource = uri; }
                        // Folded control markers (reactions, pins, avatar
                        // broadcasts) must never occupy a bubble.
                        visible: modelData.folded !== true
                        height: visible ? implicitHeight : 0
                    }
                }

                GroupInfoPanel {
                    id: groupInfoPanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.section === "chats" && parent.parent.hasConversation && root.detailsShown
                    convoId: root.backend ? root.backend.currentConversationId : ""
                    groupName: root.backend ? (root.backend.currentDisplayName || "") : ""
                    groupDescription: root.backend ? (root.backend.currentDescription || "") : ""
                    members: root.members
                    memberCount: root.backend ? root.backend.memberCount : 0
                    pendingMemberCount: root.backend ? root.backend.pendingMemberCount : 0
                    onClose: root.detailsShown = false
                    onAddMember: addMemberDialog.open()
                    onLeaveGroup: root.call(root.backend.leaveGroup(root.backend.currentConversationId))
                }

                // The right pane in the Contacts section: your own address, for
                // sharing. Without this the pane was simply black.
                AddressCard {
                    id: addressCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Theme.space6
                    visible: root.section === "contacts"
                    address: root.backend ? (root.backend.myAddress || "") : ""
                    label: root.backend ? (root.backend.myLabel || "") : ""
                    onCopy: root.call(root.backend.copyToClipboard(root.backend.myAddress))
                }

                SettingsPanel {
                    id: settingsPanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.section === "settings"
                    settings: root.settings
                    myAddress: root.backend ? (root.backend.myAddress || "") : ""
                    deliveryPreset: "logos.test"
                    onSetSetting: function (key, jsonValue) { root.call(root.backend.setSetting(key, jsonValue)); }
                    onResetRequested: root.call(root.backend.resetIdentityAndData())
                }

                EmptyState {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.section === "chats" && !parent.parent.hasConversation
                    glyph: "chats"
                    title: "Select a conversation"
                    hint: root.backend && root.backend.myAddress
                          ? "Your address: " + root.backend.myAddress : ""
                }

                Composer {
                    id: composer
                    Layout.fillWidth: true
                    Layout.margins: Theme.space4
                    visible: root.section === "chats" && parent.parent.hasConversation && !root.detailsShown
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

    // ── full-size media ─────────────────────────────────────────────────────
    MediaViewer {
        anchors.fill: parent
        visible: root.viewerSource !== ""
        source: root.viewerSource
        onClosed: root.viewerSource = ""
    }

    // ── add a member to the current group ───────────────────────────────────
    Rectangle {
        id: addMemberDialog
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: false

        function open()  { memberField.text = ""; visible = true; memberField.forceActiveFocus(); }
        function close() { visible = false; }

        TapHandler { onTapped: addMemberDialog.close() }

        Rectangle {
            anchors.centerIn: parent
            width: 460
            implicitHeight: memberCol.implicitHeight + Theme.space6 * 2
            height: implicitHeight
            radius: Theme.radiusCard
            color: Theme.panel
            border.width: Theme.hairline
            border.color: Theme.border
            TapHandler { onTapped: {} }

            ColumnLayout {
                id: memberCol
                anchors.fill: parent
                anchors.margins: Theme.space6
                spacing: Theme.space3

                Text {
                    text: "Add a member"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: "The invite is committed and delivered asynchronously — they appear as pending until the group commits them."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.labelSize
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radiusCard
                    color: Theme.pane
                    border.width: Theme.hairline
                    border.color: memberField.activeFocus ? Theme.accent : Theme.border
                    TextField {
                        id: memberField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        placeholderText: "Peer address"
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.codeSize
                        background: null
                        Keys.onReturnPressed: function (event) { event.accepted = true; addMember(); }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 90; height: 34; radius: Theme.radiusCard
                        color: "transparent"
                        border.width: Theme.hairline
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent; text: "Cancel"
                            color: Theme.textDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize
                        }
                        TapHandler { onTapped: addMemberDialog.close() }
                    }
                    Rectangle {
                        width: 90; height: 34; radius: Theme.radiusCard
                        color: memberField.text.trim().length > 0 ? Theme.accent : Theme.pane
                        Text {
                            anchors.centerIn: parent; text: "Add"
                            color: memberField.text.trim().length > 0 ? Theme.onAccent : Theme.textFaint
                            font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize
                        }
                        TapHandler {
                            enabled: memberField.text.trim().length > 0
                            onTapped: addMember()
                        }
                    }
                }
            }
        }
    }

    function addMember() {
        const addr = memberField.text.trim();
        if (addr.length === 0 || !backend)
            return;
        call(backend.addGroupMember(backend.currentConversationId, addr));
        addMemberDialog.close();
    }

    // ── new chat ────────────────────────────────────────────────────────────
    // An in-tree overlay, not a Modal — a Modal is a separate window and brings
    // its own input problems; this is simpler and screenshot-friendly.
    Rectangle {
        id: newChatDialog
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: false

        function open()  { addressField.text = ""; visible = true; addressField.forceActiveFocus(); }
        function close() { visible = false; }

        // Swallow clicks so they don't reach the panels behind.
        TapHandler { onTapped: newChatDialog.close() }

        Rectangle {
            anchors.centerIn: parent
            width: 460
            implicitHeight: dialogCol.implicitHeight + Theme.space6 * 2
            height: implicitHeight
            radius: Theme.radiusCard
            color: Theme.panel
            border.width: Theme.hairline
            border.color: Theme.border

            // Don't let a click inside the card dismiss it.
            TapHandler { onTapped: {} }

            ColumnLayout {
                id: dialogCol
                anchors.fill: parent
                anchors.margins: Theme.space6
                spacing: Theme.space3

                Text {
                    text: "New conversation"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: "Paste the peer's address. They must be online at least once for their key package to be published."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.labelSize
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radiusCard
                    color: Theme.pane
                    border.width: Theme.hairline
                    border.color: addressField.activeFocus ? Theme.accent : Theme.border

                    TextField {
                        id: addressField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        placeholderText: "Peer address"
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.codeSize
                        background: null
                        // Never `onAccepted` — on a LogosTextField that hard-crashes
                        // the QML load, so Keys is the habit everywhere.
                        Keys.onReturnPressed: function (event) { event.accepted = true; startChat(); }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 90; height: 34; radius: Theme.radiusCard
                        color: "transparent"
                        border.width: Theme.hairline
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent; text: "Cancel"
                            color: Theme.textDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize
                        }
                        TapHandler { onTapped: newChatDialog.close() }
                    }
                    Rectangle {
                        width: 90; height: 34; radius: Theme.radiusCard
                        color: addressField.text.trim().length > 0 ? Theme.accent : Theme.pane
                        Text {
                            anchors.centerIn: parent; text: "Start"
                            color: addressField.text.trim().length > 0
                                   ? Theme.onAccent : Theme.textFaint
                            font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize
                        }
                        TapHandler {
                            enabled: addressField.text.trim().length > 0
                            onTapped: startChat()
                        }
                    }
                }
            }
        }
    }

    function startChat() {
        const addr = addressField.text.trim();
        if (addr.length === 0 || !backend)
            return;
        logos.watch(backend.createConversation(addr),
                    function () {},
                    function (err) { errorStrip.show(String(err)); });
        newChatDialog.close();
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
