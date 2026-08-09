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

    implicitHeight: 56
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

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space4
        anchors.rightMargin: Theme.space1
        spacing: Theme.space2

        TextArea {
            id: input
            Layout.fillWidth: true
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
            color: root.canSend
                   ? (sendHover.hovered ? Theme.accentHover : Theme.accent)
                   : Theme.panel

            HoverHandler { id: sendHover; enabled: root.canSend }
            TapHandler { enabled: root.canSend; onTapped: root.submit() }

            PeersIcon {
                anchors.centerIn: parent
                name: "send"
                size: 20
                strokeWidth: 2
                color: root.canSend ? Theme.onAccent : Theme.textFaint
            }
        }
    }
}
