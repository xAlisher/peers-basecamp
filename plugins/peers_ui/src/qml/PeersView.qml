import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
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
    // Which message a save dialog is about. Both the bubble menu and the viewer
    // open the same dialog, so the key cannot come from either one implicitly.
    property string saveKey: ""
    // The contact whose card is being shared, "" when the picker is forwarding a
    // message instead. Both routes end at the same picker.
    property string shareAddress: ""

    // Every image currently in the thread, as the viewer's pager wants it. Built
    // on open rather than bound, so paging is stable while messages arrive.
    function imagesInThread() {
        const out = [];
        for (var i = 0; i < root.messages.length; i++) {
            const m = root.messages[i];
            const isImage = m.kind === "photo"
                            || (m.kind === "media"
                                && String(m.mime || "").indexOf("image/") === 0);
            if (isImage && String(m.dataUri || "") !== "")
                out.push({ uri: String(m.dataUri), key: String(m.key) });
        }
        return out;
    }

    function openViewer(uri, key) {
        const list = root.imagesInThread();
        var at = -1;
        for (var i = 0; i < list.length; i++)
            if (list[i].key === key) { at = i; break; }
        mediaViewer.images = list;
        mediaViewer.index = at;
        root.viewerSource = uri;
    }

    // Outcome of the last backup open, as "ok:<convos>:<messages>" or
    // "fail:<reason>". Slot returns cannot cross QtRO, so the backend reports
    // through signals and the view holds the result.
    property string lastBackup: ""

    // The message the composer is replying to ({} = not replying).
    property var replyingTo: ({})
    // The message a forward was started from.
    property var forwardSource: ({})


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
        function onCurrentConversationIdChanged() {
            root.detailsShown = false;
            root.replyingTo = ({});   // a quote key means nothing in another thread
        }
        function onError(message) { errorStrip.show(message); }
        function onToast(message) { toast.show(message); }
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
                    onShareContact: function (address) {
                        root.shareAddress = address;
                        forwardPicker.open();
                    }
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
                    // Setting `visible` here REPLACES the component's own
                    // `visible: pinKey !== ""`, so the empty-pin condition has to
                    // be restated — otherwise the bar shows with nothing in it.
                    visible: parent.parent.hasConversation && !root.detailsShown
                             && root.pinned !== undefined && root.pinned !== null
                             && root.pinned.key !== undefined && root.pinned.key !== ""
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
                        onImageClicked: function (uri, key) { root.openViewer(uri, key); }
                        onAddContact: function (address, label) {
                            if (label !== "")
                                root.call(root.backend.setContactLabel(address, label));
                            // createConversation opens the existing 1:1 when
                            // there already is one, so "Add" is idempotent.
                            root.call(root.backend.createConversation(address));
                            toast.show(label !== "" ? ("Added " + label) : "Added");
                        }
                        onViewContact: function (address, label) {
                            if (clipboard.copyText(address))
                                toast.show("Address copied");
                        }
                        onMenuRequested: function (m, sx, sy) {
                            bubbleMenu.msg = m;
                            bubbleMenu.hasLabel = root.labelFor(m.sender) !== "";
                            bubbleMenu.isGroup = root.backend ? root.backend.currentIsGroup : false;
                            // Android v1 lets only the group creator pin; we cannot
                            // determine that from the contract, so 1:1 always may and
                            // groups may not, rather than offering an action that fails.
                            bubbleMenu.canPin = root.backend ? !root.backend.currentIsGroup : false;
                            bubbleMenu.openAt(sx, sy);
                        }
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
                    replyingTo: root.replyingTo
                    onCancelReply: root.replyingTo = ({})
                    onAttach: attachDialog.open()
                    onShareLocation: locationDialog.open()
                    recording: root.backend ? root.backend.recording : false
                    recordingMs: root.backend ? root.backend.recordingMs : 0
                    onStartRecord: root.call(root.backend.startRecording())
                    onCancelRecord: root.call(root.backend.cancelRecording())
                    onSendRecord: root.call(
                        root.backend.sendRecording(root.backend.currentConversationId))
                    onSend: function (body) {
                        if (composer.isReplying) {
                            root.call(root.backend.sendReply(root.backend.currentConversationId,
                                                             body, root.replyingTo.key));
                            root.replyingTo = ({});
                        } else {
                            root.call(root.backend.sendMessage(
                                root.backend.currentConversationId, body));
                        }
                    }
                }
            }
        }
    }

    function labelFor(address) {
        if (!address)
            return "";
        for (var i = 0; i < root.contacts.length; i++) {
            if (root.contacts[i].address === address)
                return root.contacts[i].label || "";
        }
        return "";
    }

    ClipboardProxy { id: clipboard }

    // ── per-message actions ─────────────────────────────────────────────────
    BubbleActionMenu {
        id: bubbleMenu
        anchors.fill: parent

        onReact: function (emoji) {
            root.call(root.backend.reactToMessage(root.backend.currentConversationId,
                                                  msg.key, emoji));
        }
        onOpenEmojiGrid: emojiGrid.open()
        onReply: root.replyingTo = bubbleMenu.msg
        onEditLabel: {
            labelDialog.address = bubbleMenu.msg.sender || "";
            labelDialog.open(root.labelFor(bubbleMenu.msg.sender));
        }
        onCopyAddress: {
            if (clipboard.copyText(bubbleMenu.msg.sender))
                toast.show("Copied");
        }
        onForward: { root.forwardSource = bubbleMenu.msg; forwardPicker.open(); }
        onSaveMedia: { root.saveKey = bubbleMenu.msg.key; saveDialog.open(); }
        onOpenInMaps: Qt.openUrlExternally(
            "https://www.openstreetmap.org/?mlat=" + bubbleMenu.msg.lat
            + "&mlon=" + bubbleMenu.msg.lng)
        onCopyMessage: {
            // Android copies the RAW body here, not the rendered text — which is
            // why a hosted GIF copies its marker. Matching that.
            if (clipboard.copyText(bubbleMenu.msg.raw !== undefined
                                   ? bubbleMenu.msg.raw : bubbleMenu.msg.text))
                toast.show("Copied");
        }
        onSendMessageTo: root.call(root.backend.createConversation(bubbleMenu.msg.sender))
        onPin: function (on) {
            if (on)
                root.call(root.backend.pinMessage(root.backend.currentConversationId,
                                                  bubbleMenu.msg.key));
            else
                root.call(root.backend.unpinMessage(root.backend.currentConversationId));
        }
        onDeleteForMe: root.call(root.backend.deleteMessageForMe(
            root.backend.currentConversationId, bubbleMenu.msg.key))
    }

    ForwardPicker {
        id: forwardPicker
        anchors.fill: parent
        conversations: root.conversations
        // Sharing a contact is not a forward FROM anywhere, so nothing is
        // excluded; forwarding a message excludes the thread it is already in.
        excludeConvoId: root.shareAddress !== "" || !root.backend
                        ? "" : root.backend.currentConversationId
        onPicked: function (convoId) {
            if (root.shareAddress !== "") {
                const addr = root.shareAddress;
                root.shareAddress = "";
                root.call(root.backend.sendContactCard(convoId, addr));
                // Android jumps into the chat it sent the card to (#343), so the
                // user sees it land instead of guessing whether it went.
                root.call(root.backend.selectConversation(convoId));
                root.section = "chats";
            } else {
                root.call(root.backend.forwardMessage(root.backend.currentConversationId,
                                                      root.forwardSource.key, convoId));
            }
        }
        onCancelled: root.shareAddress = ""
    }

    EmojiGrid {
        id: emojiGrid
        anchors.fill: parent
        onPicked: function (emoji) {
            root.call(root.backend.reactToMessage(root.backend.currentConversationId,
                                                  bubbleMenu.msg.key, emoji));
        }
    }

    // ── full-size media ─────────────────────────────────────────────────────
    MediaViewer {
        id: mediaViewer
        anchors.fill: parent
        visible: root.viewerSource !== ""
        source: root.viewerSource
        onClosed: { root.viewerSource = ""; images = []; index = -1; }
        onSaveRequested: function (key) { root.saveKey = key; saveDialog.open(); }
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

    Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space6 * 2
    }

    // Save media to a file the user picks.
    FileDialog {
        id: saveDialog
        title: "Save media"
        fileMode: FileDialog.SaveFile
        onAccepted: root.call(root.backend.saveMedia(
            root.saveKey, selectedFile.toString().replace("file://", "")))
    }

    // Attach a file to send.
    FileDialog {
        id: attachDialog
        title: "Send a file"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images and media (*.png *.jpg *.jpeg *.gif *.webp *.mp4 *.webm *.m4a *.ogg)",
                      "All files (*)"]
        onAccepted: {
            // A plain filesystem path, never a file:// URL — sendMedia requires it.
            const p = selectedFile.toString().replace("file://", "");
            const audio = /\.(m4a|mp3|ogg|opus|wav)$/i.test(p);
            root.call(root.backend.sendMedia(root.backend.currentConversationId, p,
                                             audio ? "voice" : "media"));
        }
    }

    // Add / edit a contact label. Local only — Android says so on this screen and
    // so do we, because a label is never broadcast.
    Rectangle {
        id: labelDialog
        property string address: ""
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: false
        z: 62

        function open(existing) { labelField.text = existing || ""; visible = true; labelField.forceActiveFocus(); }
        function close() { visible = false; }
        function commit() {
            root.call(root.backend.setContactLabel(labelDialog.address, labelField.text.trim()));
            labelDialog.close();
            toast.show("Label saved");
        }

        TapHandler { onTapped: labelDialog.close() }

        Rectangle {
            anchors.centerIn: parent
            width: 420
            implicitHeight: lblCol.implicitHeight + Theme.space6 * 2
            height: implicitHeight
            radius: Theme.radiusCard
            color: Theme.panel
            border.width: Theme.hairline
            border.color: Theme.border
            TapHandler { onTapped: {} }

            ColumnLayout {
                id: lblCol
                anchors.fill: parent
                anchors.margins: Theme.space6
                spacing: Theme.space3

                Text {
                    text: "Label this contact"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: "Only you see this — it never leaves your device."
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
                    border.color: labelField.activeFocus ? Theme.accent : Theme.border
                    TextField {
                        id: labelField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        placeholderText: "e.g. Alice"
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        background: null
                        Keys.onReturnPressed: function (e) { e.accepted = true; labelDialog.commit(); }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 90; Layout.preferredHeight: 34
                        radius: Theme.radiusCard; color: "transparent"
                        border.width: Theme.hairline; border.color: Theme.border
                        Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.textDim
                               font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize }
                        TapHandler { onTapped: labelDialog.close() }
                    }
                    Rectangle {
                        Layout.preferredWidth: 90; Layout.preferredHeight: 34
                        radius: Theme.radiusCard; color: Theme.accent
                        Text { anchors.centerIn: parent; text: "Save"; color: Theme.onAccent
                               font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize }
                        TapHandler { onTapped: labelDialog.commit() }
                    }
                }
            }
        }
    }

    // Share a location. The desktop has no GPS, so the coordinates are typed —
    // inventing a position would be worse than asking for one.
    Rectangle {
        id: locationDialog
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: false
        z: 62
        function open()  { latField.text = ""; lngField.text = ""; visible = true; latField.forceActiveFocus(); }
        function close() { visible = false; }
        function commit() {
            const la = parseFloat(latField.text), ln = parseFloat(lngField.text);
            if (isNaN(la) || isNaN(ln)) { errorStrip.show("Enter a latitude and longitude."); return; }
            root.call(root.backend.sendLocation(root.backend.currentConversationId, la, ln));
            locationDialog.close();
        }
        TapHandler { onTapped: locationDialog.close() }

        Rectangle {
            anchors.centerIn: parent
            width: 420
            implicitHeight: locCol.implicitHeight + Theme.space6 * 2
            height: implicitHeight
            radius: Theme.radiusCard
            color: Theme.panel
            border.width: Theme.hairline
            border.color: Theme.border
            TapHandler { onTapped: {} }

            ColumnLayout {
                id: locCol
                anchors.fill: parent
                anchors.margins: Theme.space6
                spacing: Theme.space3

                Text { text: "Share a location"; color: Theme.text
                       font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize
                       font.weight: Font.Medium }
                Text { Layout.fillWidth: true
                       text: "This machine has no GPS, so enter the coordinates."
                       color: Theme.textDim; font.family: Theme.fontFamily
                       font.pixelSize: Theme.labelSize; wrapMode: Text.Wrap }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Theme.radiusCard
                        color: Theme.pane
                        border.width: Theme.hairline
                        border.color: latField.activeFocus ? Theme.accent : Theme.border
                        TextField {
                            id: latField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space3
                            anchors.rightMargin: Theme.space3
                            placeholderText: "Latitude"
                            placeholderTextColor: Theme.textFaint
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.codeSize
                            background: null
                            Keys.onReturnPressed: function (e) { e.accepted = true; locationDialog.commit(); }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Theme.radiusCard
                        color: Theme.pane
                        border.width: Theme.hairline
                        border.color: lngField.activeFocus ? Theme.accent : Theme.border
                        TextField {
                            id: lngField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space3
                            anchors.rightMargin: Theme.space3
                            placeholderText: "Longitude"
                            placeholderTextColor: Theme.textFaint
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.codeSize
                            background: null
                            Keys.onReturnPressed: function (e) { e.accepted = true; locationDialog.commit(); }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 90; Layout.preferredHeight: 34
                        radius: Theme.radiusCard; color: Theme.accent
                        Text { anchors.centerIn: parent; text: "Send"; color: Theme.onAccent
                               font.family: Theme.fontFamily; font.pixelSize: Theme.labelSize }
                        TapHandler { onTapped: locationDialog.commit() }
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
