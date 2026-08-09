import QtQuick
import "Theme.js" as Theme

//
// Full-pane image viewer.
//
// Android source: MediaViewer.tsx — overlay `zIndex/elevation 1000`, black
// ground, a 40×40 radius-20 `rgba(0,0,0,0.45)` close circle, loading text in
// `rgba(255,255,255,0.6)` at 15px (DESIGN-SPEC §5.12).
//
// SCOPE: fit-to-view only. The Android viewer's pinch-zoom, double-tap zoom,
// swipe-to-dismiss and swipe-to-page are gesture-handler/reanimated work with
// no honest desktop equivalent here, so they are deliberately absent rather
// than faked. Close is the ✕ or Escape.
//
Rectangle {
    id: root

    // A bounded data: URI handed over by the backend — this never touches the
    // filesystem or the network.
    property string source: ""

    signal closed

    z: 1000
    color: Qt.rgba(0, 0, 0, 0.9)

    // Escape closes. The overlay has to actually hold focus for that to fire,
    // and it has to take focus back whenever it is re-shown.
    focus: visible
    Keys.onEscapePressed: function (event) {
        event.accepted = true;
        root.closed();
    }
    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }
    Component.onCompleted: {
        if (visible)
            forceActiveFocus();
    }

    // Swallows every click so the thread underneath stays inert while the
    // viewer is up. It does NOT dismiss: on Android a tap toggles the chrome
    // rather than closing, and a click-anywhere-to-close would fire on the
    // image itself.
    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    Image {
        id: photo
        anchors.fill: parent
        anchors.margins: Theme.space6
        source: root.source
        fillMode: Image.PreserveAspectFit
        // Fit-to-view, centred, never cropped.
        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter
        asynchronous: true
        // A peer-supplied image must not be able to blow up memory through its
        // declared dimensions. Both axes set + PreserveAspectFit = decode
        // scaled to fit inside this box, aspect kept.
        sourceSize.width: 1600
        sourceSize.height: 1600
    }

    Text {
        anchors.centerIn: parent
        visible: photo.status === Image.Loading || photo.status === Image.Error
                 || root.source === ""
        text: photo.status === Image.Error ? "media unavailable"
              : (root.source === "" ? "no media" : "loading…")
        color: Qt.rgba(1, 1, 1, 0.6)
        font.family: Theme.fontFamily
        font.pixelSize: 15
    }

    // Close circle, top-right. Android puts it at top 44 to clear the status
    // bar; there is no status bar in a Basecamp pane, so it sits on the normal
    // 16px inset.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.space4
        width: 40
        height: 40
        radius: 20
        color: closeHit.containsMouse ? Qt.rgba(0, 0, 0, 0.65)
                                      : Qt.rgba(0, 0, 0, 0.45)

        PeersIcon {
            anchors.centerIn: parent
            name: "close"
            size: 22
            color: Theme.text
        }

        MouseArea {
            id: closeHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closed()
        }
    }
}
