import QtQuick
import "Theme.js" as Theme

// Brief confirmation ("Copied", "Forwarded", "Saved"). Android's ErrorToast is
// persistent with a manual dismiss; this is the success sibling and auto-hides,
// which is why it is a separate component rather than a mode of the error strip.
Rectangle {
    id: root
    property string message: ""
    function show(m) { message = m; hideTimer.restart(); }

    visible: message !== ""
    implicitWidth: label.implicitWidth + Theme.space4 * 2
    implicitHeight: 36
    radius: Theme.radiusPill
    color: Theme.panel
    border.width: Theme.hairline
    border.color: Theme.border
    z: 70

    Text {
        id: label
        anchors.centerIn: parent
        text: root.message
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.labelSize
    }

    Timer { id: hideTimer; interval: 1800; onTriggered: root.message = "" }
}
