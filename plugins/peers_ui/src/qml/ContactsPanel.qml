import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "Theme.js" as Theme

//
// The middle-panel contents for the Contacts section.
//
// Peers' Contacts screen is a flat list of PEOPLE, deliberately distinct from
// the conversation list: its source is `knownContacts()` = every 1:1 peer plus
// every address seen in a group roster (ContactsScreen.tsx:1-4, :54). A contact
// therefore may have no conversation yet, which is why the primary row action
// is "start a chat" rather than "open".
//
// Data comes in through `contacts` — the parsed backend.contactsJson array,
// each entry { address, label, verified, avatar }. Nothing here talks to a
// backend; every action leaves as a signal.
//
// Android's Labeled/Seen tabs (ContactsScreen.tsx:63-72, :272-290) are NOT
// reproduced: the desktop panel shows one list and leans on search instead.
//
Item {
    id: root

    // ── data in ─────────────────────────────────────────────────────────────
    // Parsed from backend.contactsJson. Entries are read defensively — a
    // missing label or avatar is normal, not an error.
    property var contacts: []
    // This account. Used for the "this device" header row, and to keep myself
    // out of my own contact list.
    property string myAddress: ""
    property string myLabel: ""

    // ── actions out ─────────────────────────────────────────────────────────
    signal startChat(string address)
    signal removeContact(string address)
    signal setLabel(string address, string label)
    // Share this contact into a conversation as an addr1: card.
    signal shareContact(string address)

    // ── local state ─────────────────────────────────────────────────────────
    property string query: ""

    implicitWidth: 320
    implicitHeight: 480

    // Peers' short form: enough leading hex to recognise, enough trailing hex
    // to distinguish. Short strings are shown whole rather than mangled.
    function shortAddress(a) {
        const s = a === undefined || a === null ? "" : String(a);
        return s.length <= 14 ? s : s.slice(0, 6) + "…" + s.slice(-4);
    }

    function contactAddress(c) {
        return c && c.address !== undefined ? String(c.address) : "";
    }
    function contactLabel(c) {
        return c && c.label !== undefined && c.label !== null ? String(c.label) : "";
    }

    // Case-insensitive over label AND hex, matching ContactsScreen.tsx:258-271.
    // Referenced properties are named in the binding below so the filter
    // re-runs when any of them change.
    function filterContacts(list, q, mine) {
        const src = list === undefined || list === null ? [] : list;
        const needle = String(q).trim().toLowerCase();
        const out = [];
        for (var i = 0; i < src.length; ++i) {
            const c = src[i];
            const addr = contactAddress(c);
            if (addr === "" || (mine !== "" && addr === mine))
                continue;
            if (needle === "") {
                out.push(c);
                continue;
            }
            if (addr.toLowerCase().indexOf(needle) !== -1
                    || contactLabel(c).toLowerCase().indexOf(needle) !== -1)
                out.push(c);
        }
        return out;
    }

    readonly property var filtered: filterContacts(contacts, query, myAddress)
    readonly property int totalCount:
        filterContacts(contacts, "", myAddress).length

    // The VerifiedBadge seal (VerifiedBadge.tsx:24-44): a 9-lobed scalloped
    // disc on the 0 0 24 24 grid, bump radius 11.2, valley radius 8.6, centred
    // at (12,12). Sampled as one closed subpath rather than stitched arcs —
    // a Repeater of ShapePaths renders NOTHING (its delegate must be an Item),
    // so every glyph in this codebase is a single `d` string.
    function buildSealPath() {
        const lobes = 9;
        const mean = (11.2 + 8.6) / 2;
        const amp = (11.2 - 8.6) / 2;
        const steps = 144;
        var d = "";
        for (var i = 0; i < steps; ++i) {
            const t = i / steps * 2 * Math.PI;
            const r = mean + amp * Math.cos(lobes * t);
            const x = 12 + r * Math.cos(t);
            const y = 12 + r * Math.sin(t);
            d += (i === 0 ? "M" : "L") + x.toFixed(3) + " " + y.toFixed(3);
        }
        return d + "Z";
    }
    readonly property string sealPath: buildSealPath()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── this device ─────────────────────────────────────────────────────
        // Mirrors About's "this device" card (AboutScreen.tsx:156-166): avatar
        // plus short address, so my own identity is never confused with a peer.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight
            visible: root.myAddress !== ""

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                HexAvatar {
                    size: 32
                    seed: root.myAddress
                    kind: "contact"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.myLabel !== ""
                              ? root.myLabel : root.shortAddress(root.myAddress)
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "this device · " + root.shortAddress(root.myAddress)
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.hairline
            color: Theme.border
            visible: root.myAddress !== ""
        }

        // ── search ──────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 40 + Theme.space3 * 2

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.space3
                radius: Theme.radiusCard
                color: Theme.pane
                border.width: Theme.hairline
                border.color: searchField.activeFocus ? Theme.accent : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space2
                    spacing: Theme.space2

                    PeersIcon {
                        name: "search"
                        size: 16
                        color: Theme.textFaint
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search contacts…"
                        // Placeholders are ALWAYS textFaint in Peers.
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        background: null
                        padding: 0
                        verticalAlignment: TextField.AlignVCenter

                        onTextChanged: root.query = text

                        // Never `onAccepted` — Keys is the habit everywhere in
                        // this codebase. Return on a single match is a shortcut
                        // to that chat; otherwise it just swallows the key.
                        Keys.onReturnPressed: function (event) {
                            event.accepted = true;
                            if (root.filtered.length === 1)
                                root.startChat(root.contactAddress(root.filtered[0]));
                        }
                        Keys.onEnterPressed: function (event) {
                            event.accepted = true;
                            if (root.filtered.length === 1)
                                root.startChat(root.contactAddress(root.filtered[0]));
                        }
                        Keys.onEscapePressed: function (event) {
                            event.accepted = true;
                            searchField.clear();
                        }
                    }

                    PeersIcon {
                        name: "close"
                        size: 14
                        visible: searchField.text !== ""
                        color: clearHover.hovered ? Theme.text : Theme.textFaint
                        HoverHandler { id: clearHover }
                        TapHandler { onTapped: searchField.clear() }
                    }
                }
            }
        }

        // ── list ────────────────────────────────────────────────────────────
        // The ListView and its empty states are SIBLINGS inside a plain Item.
        // A visual child declared inside a ListView is reparented into its
        // contentItem, so an EmptyState there would anchor to a zero-height
        // content area precisely when count === 0 — and never draw.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    id: row

                    required property var modelData

                    readonly property string address: root.contactAddress(modelData)
                    readonly property string label: root.contactLabel(modelData)
                    readonly property bool verified: modelData
                                                     && modelData.verified === true
                    readonly property string avatar: modelData
                                                     && modelData.avatar !== undefined
                                                     && modelData.avatar !== null
                                                     ? String(modelData.avatar) : ""

                    width: list.width
                    implicitHeight: 56

                    HoverHandler { id: rowHover }
                    // Primary action: open (or create) the 1:1 with this person.
                    TapHandler { onTapped: root.startChat(row.address) }

                    Rectangle {
                        anchors.fill: parent
                        color: rowHover.hovered ? Theme.panel : "transparent"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space4
                        anchors.rightMargin: Theme.space3
                        spacing: Theme.space3

                        HexAvatar {
                            size: 32
                            seed: row.address
                            kind: "contact"
                            avatarSource: row.avatar
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                id: titleRow
                                Layout.fillWidth: true
                                spacing: Theme.space1

                                Text {
                                    // NOT fillWidth: the seal must sit against the
                                    // name (titleRow gap 4, ConversationsScreen.tsx:550),
                                    // and a fillWidth name would shove it to the far
                                    // right where it reads as a status column. A
                                    // Layout leaves its trailing slack empty when no
                                    // child fills, which is exactly what we want.
                                    Layout.maximumWidth: titleRow.width
                                                         - (seal.visible
                                                            ? seal.implicitWidth + titleRow.spacing
                                                            : 0)
                                    // Without a label the hex itself becomes the
                                    // white primary line (ChatScreen.tsx:432-438).
                                    text: row.label !== ""
                                          ? row.label : root.shortAddress(row.address)
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodySize
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                // VerifiedBadge, size 14 (ConversationsScreen.tsx:118).
                                Item {
                                    id: seal
                                    visible: row.verified
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    readonly property real s: implicitWidth / 24

                                    Shape {
                                        anchors.fill: parent
                                        antialiasing: true

                                        ShapePath {
                                            fillColor: Theme.verified
                                            strokeColor: "transparent"
                                            strokeWidth: 0
                                            scale: Qt.size(seal.s, seal.s)
                                            PathSvg { path: root.sealPath }
                                        }
                                        ShapePath {
                                            fillColor: "transparent"
                                            strokeColor: Theme.onAccent
                                            strokeWidth: 2 * seal.s
                                            capStyle: ShapePath.RoundCap
                                            joinStyle: ShapePath.RoundJoin
                                            scale: Qt.size(seal.s, seal.s)
                                            PathSvg { path: "M8.4 12.3 L11 14.8 L15.7 9.2" }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                // Only a labelled contact needs the hex sub-line —
                                // an unlabelled one already shows it above.
                                visible: row.label !== ""
                                text: root.shortAddress(row.address)
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.labelSize
                                elide: Text.ElideRight
                            }
                        }

                        // Row actions. Kept permanently in the layout and merely
                        // dimmed when idle: appearing-on-hover affordances vanish
                        // from the offscreen screenshot captures we verify with.
                        PeersIcon {
                            // No pencil glyph exists in PeersIcon; `userplus` is the
                            // closest existing contact-identity glyph. Noted in the
                            // component report rather than inventing path data.
                            name: "userplus"
                            size: 16
                            color: labelHover.hovered ? Theme.text : Theme.textFaint
                            opacity: rowHover.hovered || labelHover.hovered ? 1.0 : 0.55
                            HoverHandler { id: labelHover }
                            TapHandler {
                                onTapped: labelDialog.open(row.address, row.label)
                            }
                        }

                        PeersIcon {
                            name: "send"
                            size: 16
                            color: shareHover.hovered ? Theme.accent : Theme.textFaint
                            opacity: rowHover.hovered || shareHover.hovered ? 1.0 : 0.55
                            HoverHandler { id: shareHover }
                            TapHandler { onTapped: root.shareContact(row.address) }
                        }

                        PeersIcon {
                            name: "trash"
                            size: 16
                            color: removeHover.hovered ? Theme.unread : Theme.textFaint
                            opacity: rowHover.hovered || removeHover.hovered ? 1.0 : 0.55
                            HoverHandler { id: removeHover }
                            TapHandler { onTapped: root.removeContact(row.address) }
                        }
                    }

                    // Separator, inset past the avatar (ContactsScreen.tsx:454).
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.space4
                        height: Theme.hairline
                        color: Theme.border
                        opacity: 0.5
                    }
                }
            }

            // Two distinct empties: nothing at all, versus nothing matching.
            EmptyState {
                anchors.fill: parent
                visible: list.count === 0 && root.totalCount === 0
                glyph: "contacts"
                title: "No contacts yet"
                hint: "Anyone you chat with — or meet in a group — shows up here. Share your address to get started."
            }

            EmptyState {
                anchors.fill: parent
                visible: list.count === 0 && root.totalCount > 0
                glyph: "search"
                title: "No matches"
                hint: "No contact matches “" + root.query + "”."
            }
        }
    }

    // ── label editor ────────────────────────────────────────────────────────
    // An in-tree overlay rather than a Modal: a Modal is a separate window,
    // brings its own input problems, and does not appear in offscreen captures.
    Rectangle {
        id: labelDialog
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: false

        property string address: ""

        function open(addr, current) {
            address = addr;
            labelField.text = current;
            visible = true;
            labelField.forceActiveFocus();
            labelField.selectAll();
        }
        function close() { visible = false; address = ""; }
        function commit() {
            if (address === "")
                return;
            root.setLabel(address, labelField.text.trim());
            close();
        }

        // Swallow clicks so they never reach the list behind.
        TapHandler { onTapped: labelDialog.close() }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.space4 * 2, 380)
            implicitHeight: labelCol.implicitHeight + Theme.space6 * 2
            height: implicitHeight
            radius: Theme.radiusCard
            color: Theme.panel
            border.width: Theme.hairline
            border.color: Theme.border

            // A click inside the card must not dismiss it.
            TapHandler { onTapped: {} }

            ColumnLayout {
                id: labelCol
                anchors.fill: parent
                anchors.margins: Theme.space6
                spacing: Theme.space3

                Text {
                    text: "Label contact"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: root.shortAddress(labelDialog.address)
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.codeSize
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.minTouchTarget
                    radius: Theme.radiusCard
                    color: Theme.pane
                    border.width: Theme.hairline
                    border.color: labelField.activeFocus ? Theme.accent : Theme.border

                    TextField {
                        id: labelField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        placeholderText: "Add label (optional)"
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        background: null
                        padding: 0
                        verticalAlignment: TextField.AlignVCenter

                        Keys.onReturnPressed: function (event) {
                            event.accepted = true;
                            labelDialog.commit();
                        }
                        Keys.onEnterPressed: function (event) {
                            event.accepted = true;
                            labelDialog.commit();
                        }
                        Keys.onEscapePressed: function (event) {
                            event.accepted = true;
                            labelDialog.close();
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "A label is local to this device — it is never broadcast."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 34
                        radius: Theme.radiusCard
                        color: "transparent"
                        border.width: Theme.hairline
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.labelSize
                        }
                        TapHandler { onTapped: labelDialog.close() }
                    }
                    Rectangle {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 34
                        radius: Theme.radiusCard
                        color: saveHover.hovered ? Theme.accentHover : Theme.accent
                        HoverHandler { id: saveHover }
                        Text {
                            anchors.centerIn: parent
                            text: "Save"
                            // White on accent, never black.
                            color: Theme.onAccent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.labelSize
                        }
                        TapHandler { onTapped: labelDialog.commit() }
                    }
                }
            }
        }
    }
}
