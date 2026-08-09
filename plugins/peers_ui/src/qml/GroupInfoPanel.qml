import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

//
// Group info — the right-pane detail for a group conversation.
//
// Port of Peers Android `src/screens/GroupInfoScreen.tsx` (header block ~:330-379,
// roster :143-210, empty copy :443-447, footer :450-460), collapsed from a pushed
// screen into a detail pane. See docs/FEATURE-INVENTORY.md §3.8.
//
// Two things this panel is deliberately honest about, because the transport is:
//
//  1. A PENDING member is an invite that MLS has not committed yet. Until the
//     commit lands they cannot read the conversation, so they are rendered dim
//     with an explicit "pending" chip — never mixed in as if they were reading
//     along. Committed members sort first for the same reason.
//  2. The core has NO leave primitive. Nothing can be told to the other members,
//     so the destructive affordance reads "Delete for me" and says out loud that
//     it is local — labelling it "Leave group" would promise a message that is
//     never sent.
//
// An empty address is a real participant whose account this device has not
// confirmed; it renders as "unknown account" and the row STAYS. Dropping it
// would under-report who is in the room.
//
// Data in through properties, actions out through signals. No backend here.
//
Rectangle {
    id: root

    // Conversation id — also the group identicon seed (Android seeds the group
    // avatar by convo.libConvoId, GroupInfoScreen.tsx:330-335).
    property string convoId: ""
    property string groupName: ""
    property string groupDescription: ""

    // JS array from backend.membersJson. Each entry:
    //   { address, label, isSelf, pending, avatarSeed }
    property var members: []

    // Counts as the backend reports them. -1 = "not reported", fall back to
    // counting the roster rather than showing a wrong number.
    property int memberCount: -1
    property int pendingMemberCount: -1

    signal addMember
    signal leaveGroup
    signal close

    color: Theme.pane

    // ── derived roster ──────────────────────────────────────────────────────
    // Committed first, then pending, each keeping backend order.
    readonly property var roster: {
        var src = members !== undefined && members !== null ? members : [];
        var committed = [];
        var waiting = [];
        for (var i = 0; i < src.length; ++i) {
            if (src[i] && src[i].pending)
                waiting.push(src[i]);
            else
                committed.push(src[i]);
        }
        return committed.concat(waiting);
    }

    readonly property int committedCount: {
        var src = members !== undefined && members !== null ? members : [];
        var n = 0;
        for (var i = 0; i < src.length; ++i)
            if (src[i] && !src[i].pending)
                ++n;
        return n;
    }
    readonly property int waitingCount: {
        var src = members !== undefined && members !== null ? members : [];
        var n = 0;
        for (var i = 0; i < src.length; ++i)
            if (src[i] && src[i].pending)
                ++n;
        return n;
    }

    readonly property int shownMemberCount: memberCount >= 0 ? memberCount : committedCount
    readonly property int shownPendingCount: pendingMemberCount >= 0 ? pendingMemberCount : waitingCount

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── title bar ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3

                Text {
                    Layout.fillWidth: true
                    text: "Group info"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Theme.radiusCard
                    color: closeHover.hovered ? Theme.panel : "transparent"

                    HoverHandler {
                        id: closeHover
                    }
                    TapHandler {
                        onTapped: root.close()
                    }

                    PeersIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: 16
                        color: closeHover.hovered ? Theme.text : Theme.textDim
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.hairline
            color: Theme.border
        }

        // ── header block ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: headerBlock.implicitHeight + Theme.space4 * 2
            color: Theme.panel

            RowLayout {
                id: headerBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                HexAvatar {
                    Layout.alignment: Qt.AlignTop
                    size: 48
                    seed: root.convoId
                    kind: "group"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space1

                    Text {
                        Layout.fillWidth: true
                        text: root.groupName !== "" ? root.groupName : "Unnamed group"
                        color: root.groupName !== "" ? Theme.text : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.titleSize
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.groupDescription !== ""
                        text: root.groupDescription
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.labelSize
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        Text {
                            text: root.shownMemberCount === 1 ? "1 member" : root.shownMemberCount + " members"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize
                        }
                        Text {
                            visible: root.shownPendingCount > 0
                            text: "· " + root.shownPendingCount + " pending"
                            color: Theme.pulse
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.hairline
            color: Theme.border
        }

        // ── roster ──────────────────────────────────────────────────────────
        // The empty state is a SIBLING of the ListView, not a child of it: a
        // visual child of a ListView is reparented to its contentItem, whose
        // height is 0 when the model is empty — an `anchors.fill: parent` empty
        // state inside a ListView therefore never shows up.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: rosterList

                anchors.fill: parent
                clip: true
                model: root.roster
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: memberRow

                    required property var modelData

                    readonly property string address: (modelData && modelData.address !== undefined) ? modelData.address : ""
                    readonly property string label: (modelData && modelData.label !== undefined) ? modelData.label : ""
                    readonly property bool isSelf: modelData ? modelData.isSelf === true : false
                    readonly property bool pending: modelData ? modelData.pending === true : false
                    readonly property string avatarSeed: (modelData && modelData.avatarSeed !== undefined && modelData.avatarSeed !== "") ? modelData.avatarSeed : address

                    // An empty address is not a broken row — it is a participant
                    // whose account this device cannot confirm.
                    readonly property string identityLine: label !== "" ? label : (address !== "" ? address : "unknown account")
                    readonly property string addressLine: address !== "" ? address : "unknown account"

                    width: ListView.view ? ListView.view.width : 0
                    implicitHeight: Math.max(Theme.minTouchTarget, rowBody.implicitHeight + Theme.space3 * 2)

                    RowLayout {
                        id: rowBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.space4
                        anchors.rightMargin: Theme.space4
                        spacing: Theme.space3

                        HexAvatar {
                            size: 32
                            seed: memberRow.avatarSeed
                            kind: "contact"
                            // Not committed yet — the roster shows it, muted.
                            opacity: memberRow.pending ? 0.55 : 1.0
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: memberRow.identityLine
                                color: memberRow.pending ? Theme.textDim : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySize
                                elide: Text.ElideMiddle
                                textFormat: Text.PlainText
                            }
                            Text {
                                Layout.fillWidth: true
                                // Hidden when it would just repeat the line above
                                // (no label AND no address).
                                visible: memberRow.addressLine !== memberRow.identityLine
                                text: memberRow.addressLine
                                color: memberRow.address === "" ? Theme.textFaint : (memberRow.pending ? Theme.textFaint : Theme.textDim)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.labelSize
                                font.italic: memberRow.address === ""
                                elide: Text.ElideMiddle
                                textFormat: Text.PlainText
                            }
                        }

                        // "You"
                        Rectangle {
                            visible: memberRow.isSelf
                            implicitWidth: selfLabel.implicitWidth + Theme.space2 * 2
                            implicitHeight: 20
                            radius: Theme.radiusPill
                            color: "transparent"
                            border.width: Theme.hairline
                            border.color: Theme.border

                            Text {
                                id: selfLabel
                                anchors.centerIn: parent
                                text: "You"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.captionSize
                            }
                        }

                        // "pending" — the invite is out, the group has not committed
                        // it, and until it does this member cannot read anything here.
                        Rectangle {
                            visible: memberRow.pending
                            implicitWidth: pendingLabel.implicitWidth + Theme.space2 * 2
                            implicitHeight: 20
                            radius: Theme.radiusPill
                            color: "transparent"
                            border.width: Theme.hairline
                            border.color: Theme.pulse

                            Text {
                                id: pendingLabel
                                anchors.centerIn: parent
                                text: "pending"
                                color: Theme.pulse
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.captionSize
                            }
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
            }

            EmptyState {
                anchors.fill: parent
                visible: rosterList.count === 0
                glyph: "groups"
                title: "No members recorded on this device yet"
                hint: "Add someone with the button below — the roster fills in as the group commits them."
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.hairline
            color: Theme.border
        }

        // ── footer ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: footer.implicitHeight + Theme.space4 * 2
            color: Theme.pane

            ColumnLayout {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space2

                // Primary — Add members.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Theme.radiusCard
                    color: addPressed.pressed ? Theme.accentPressed : (addHover.hovered ? Theme.accentHover : Theme.accent)

                    HoverHandler {
                        id: addHover
                    }
                    TapHandler {
                        id: addPressed
                        onTapped: root.addMember()
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        PeersIcon {
                            name: "userplus"
                            size: 18
                            color: Theme.onAccent
                        }
                        Text {
                            text: "Add members"
                            color: Theme.onAccent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.titleSize
                            font.weight: Font.Medium
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Adding sends an MLS Welcome; the member appears in their conversations list."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    wrapMode: Text.Wrap
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Theme.space1
                }

                // Destructive — and local-only, because that is all the core can
                // actually do. There is no leave primitive: nothing is sent to
                // the other members, so the label must not imply one.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Theme.radiusCard
                    color: leavePressed.pressed ? Theme.errorFill : "transparent"
                    border.width: Theme.hairline
                    border.color: leaveHover.hovered ? Theme.errorBorder : Theme.border

                    HoverHandler {
                        id: leaveHover
                    }
                    TapHandler {
                        id: leavePressed
                        onTapped: root.leaveGroup()
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        PeersIcon {
                            name: "trash"
                            size: 18
                            color: Theme.unread
                        }
                        Text {
                            text: "Delete for me"
                            color: Theme.unread
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.titleSize
                            font.weight: Font.Medium
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Removes the group from this device only. The others keep the conversation " + "and are not told you left."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
