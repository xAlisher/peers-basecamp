import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme

// The message composer: pill input plus an accent send button.
Rectangle {
    id: root

    property string placeholder: "Message"
    property alias text: input.text
    property bool canSend: input.text.trim().length > 0

    signal send(string body)
    signal draftChanged(string body)
    signal attach()
    signal shareLocation()

    // Voice notes. `recording`/`recordingMs` mirror the backend props; the
    // composer only asks, it never owns the capture state.
    property bool recording: false
    property int recordingMs: 0
    signal startRecord()
    signal cancelRecord()
    signal sendRecord()

    function mmss(ms) {
        const total = Math.round(ms / 1000);
        const m = Math.floor(total / 60);
        const sec = total % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }
    // The message being replied to ({} = none). The banner above the input is
    // what tells the user their next send will be a reply.
    property var replyingTo: ({})
    signal cancelReply()

    readonly property bool isReplying: replyingTo !== undefined && replyingTo !== null
                                       && replyingTo.key !== undefined && replyingTo.key !== ""

    implicitHeight: (isReplying ? 40 : 0) + 56
    color: Theme.pane
    radius: Theme.radiusPill
    border.width: Theme.hairline
    border.color: Theme.border

    function submit() {
        const body = input.text.trim();
        if (body.length === 0)
            return;
        root.send(body);
        input.clear();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Reply banner — what you are replying to, with a way out.
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space2
            visible: root.isReplying
            implicitHeight: root.isReplying ? 36 : 0
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                spacing: Theme.space2

                Rectangle { Layout.preferredWidth: 2; Layout.fillHeight: true
                            Layout.topMargin: 6; Layout.bottomMargin: 6; color: Theme.accent }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Replying to " + (root.replyingTo.fromSelf ? "yourself"
                              : (root.replyingTo.senderLabel || "them"))
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.captionSize
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.replyingTo.text !== undefined ? root.replyingTo.text : ""
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.labelSize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
                PeersIcon {
                    name: "close"; size: 14; color: Theme.textDim
                    TapHandler { onTapped: root.cancelReply() }
                }
            }
        }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.space2
        Layout.rightMargin: Theme.space1
        spacing: Theme.space2

        // Attach — photos, GIFs, video, voice files. Anything over the inline
        // cap goes to Logos Storage automatically (see sendMedia).
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.recording
            width: visible ? 36 : 0; height: 36; radius: 18
            color: attachHover.hovered ? Theme.panel : "transparent"
            HoverHandler { id: attachHover }
            TapHandler { onTapped: root.attach() }
            PeersIcon { anchors.centerIn: parent; name: "plus"; size: 18; color: Theme.textDim }
        }

        // Share a location.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.recording
            width: visible ? 36 : 0; height: 36; radius: 18
            color: locHover.hovered ? Theme.panel : "transparent"
            HoverHandler { id: locHover }
            TapHandler { onTapped: root.shareLocation() }
            PeersIcon { anchors.centerIn: parent; name: "location"; size: 18; color: Theme.textDim }
        }

        // While recording, the input is replaced by a discard button, a pulsing
        // dot and the elapsed time — there is nothing to type, and leaving the
        // field there would invite typing into a message that is being spoken.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: root.recording
            width: visible ? 36 : 0; height: 36; radius: 18
            color: discardHover.hovered ? Theme.panel : "transparent"
            HoverHandler { id: discardHover }
            TapHandler { onTapped: root.cancelRecord() }
            PeersIcon { anchors.centerIn: parent; name: "trash"; size: 18; color: Theme.unread }
        }

        RowLayout {
            id: recordStrip
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            visible: root.recording
            spacing: Theme.space2

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 10; height: 10; radius: 5
                color: Theme.unread
                SequentialAnimation on opacity {
                    running: root.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 600 }
                    NumberAnimation { to: 1.0; duration: 600 }
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.mmss(root.recordingMs) + "  ·  recording"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
            }
        }

        TextArea {
            id: input
            visible: !root.recording
            Layout.fillWidth: !root.recording
            Layout.preferredWidth: root.recording ? 0 : -1
            Layout.maximumHeight: 120
            placeholderText: root.placeholder
            // Peers renders placeholders in textFaint, always.
            placeholderTextColor: Theme.textFaint
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            wrapMode: TextArea.Wrap
            background: null
            verticalAlignment: TextArea.AlignVCenter

            // Enter sends, Shift+Enter inserts a newline.
            //
            // NB: never attach `onAccepted` to a LogosTextField — a handler for
            // it hard-crashes the QML load. This is a plain TextArea and uses
            // Keys explicitly, which is the safe form either way.
            Keys.onReturnPressed: function (event) {
                if (event.modifiers & Qt.ShiftModifier) {
                    event.accepted = false;
                    return;
                }
                event.accepted = true;
                root.submit();
            }
            Keys.onEnterPressed: function (event) {
                if (event.modifiers & Qt.ShiftModifier) {
                    event.accepted = false;
                    return;
                }
                event.accepted = true;
                root.submit();
            }

            onTextChanged: root.draftChanged(text)
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 44
            height: 44
            radius: width / 2
            // Empty input offers the mic, the way Android's composer does; typing
            // turns it back into send. While recording it always sends the take.
            readonly property bool acts: root.canSend || root.recording

            color: acts ? (sendHover.hovered ? Theme.accentHover : Theme.accent) : Theme.panel

            HoverHandler { id: sendHover }
            TapHandler {
                onTapped: {
                    if (root.recording) root.sendRecord();
                    else if (root.canSend) root.submit();
                    else root.startRecord();
                }
            }

            PeersIcon {
                anchors.centerIn: parent
                name: parent.acts ? "send" : "mic"
                size: 20
                strokeWidth: 2
                color: parent.acts ? Theme.onAccent : Theme.textDim
            }
        }
    }
    }
}
