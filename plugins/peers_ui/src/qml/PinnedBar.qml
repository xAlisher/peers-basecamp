import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

//
// The pinned-message strip that sits between a thread's header and its body.
//
// Android source: ChatScreen.tsx:1933-1972 (render) and :3108-3122 (styles) —
// fill `colors.panel`, a 1px `colors.border` bottom hairline, 16/8 padding and
// an 8px gap. The accent left edge is the reply banner's 2px accent bar
// (ChatScreen.tsx:3103, `replyBannerBar`) reused here: on a desktop pane the
// strip is wide enough that the pin glyph alone stops reading as "this belongs
// to the thread", and the accent rule is the mark Peers already uses for
// "quoted / referenced message".
//
// #309 removed the literal "Pinned" caption from the Android bar because the
// glyph carried it on a phone-width line; the sender label sits in that slot
// here, which is what the wider strip has room for.
//
// The whole strip is the jump affordance (Android scrolls the list to the
// pinned row on press); the ✕ is a separate, higher hit region so unpinning
// never also jumps.
//
Rectangle {
    id: root

    // Parsed backend.currentPinnedJson. `{}` when nothing is pinned; otherwise
    // { text, senderLabel, key }.
    property var pinned: ({})

    // v1 lets only a group's creator unpin (ChatScreen.tsx:2537-2544, and the
    // bar's own gate at :1959). The view owns that decision; the bar just
    // renders it.
    property bool canUnpin: true

    signal unpin
    signal jumpTo(string key)

    readonly property string pinKey:
        (pinned !== undefined && pinned !== null && pinned.key !== undefined)
        ? String(pinned.key) : ""
    readonly property string pinSender:
        (pinned !== undefined && pinned !== null && pinned.senderLabel !== undefined)
        ? String(pinned.senderLabel) : ""
    readonly property string pinText:
        (pinned !== undefined && pinned !== null && pinned.text !== undefined)
        ? String(pinned.text) : ""

    // Nothing pinned, nothing to show — and no residual height, so a column
    // above the thread collapses cleanly.
    visible: pinKey !== ""
    implicitHeight: visible ? content.implicitHeight + Theme.space2 * 2 : 0

    color: Theme.panel

    // Jump-to-message. Sits first so it is UNDER the ✕ hit region below;
    // a MouseArea accepts its press, so the ✕ never falls through to here.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.jumpTo(root.pinKey)
    }

    // Accent left edge.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 2
        color: Theme.accent
    }

    // Bottom hairline.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.hairline
        color: Theme.border
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.space4 + 2   // clear the accent edge
        anchors.rightMargin: Theme.space4
        anchors.topMargin: Theme.space2
        anchors.bottomMargin: Theme.space2
        spacing: Theme.space2

        // Pin glyph, size 16 accent (FEATURE-INVENTORY §"Pinned-message bar").
        // Never the 📌 emoji the Android source uses — emoji are content only.
        PeersIcon {
            name: "pin"
            size: 16
            color: Theme.accent
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.pinSender
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
            }

            Text {
                Layout.fillWidth: true
                text: root.pinText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.labelSize
                // One line, always: the strip is a pointer to the message, not
                // a second copy of it.
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText   // never render peer text as markup
            }
        }

        // Unpin. The visual is 24px so the strip keeps its Android height; the
        // hit region is a full 44 and simply overflows it vertically.
        Item {
            visible: root.canUnpin
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24

            PeersIcon {
                anchors.centerIn: parent
                name: "close"
                size: 16
                color: unpinHit.containsMouse ? Theme.text : Theme.textDim
            }

            MouseArea {
                id: unpinHit
                anchors.centerIn: parent
                width: Theme.minTouchTarget
                height: Theme.minTouchTarget
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.unpin()
            }
        }
    }
}
