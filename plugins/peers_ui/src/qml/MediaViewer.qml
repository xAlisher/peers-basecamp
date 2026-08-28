import QtQuick
import "Theme.js" as Theme

//
// Full-pane image viewer.
//
// Android source: MediaViewer.tsx — overlay `zIndex/elevation 1000`, black
// ground, a 40×40 radius-20 `rgba(0,0,0,0.45)` close circle, loading text in
// `rgba(255,255,255,0.6)` at 15px (DESIGN-SPEC §5.12).
//
// Android's gestures are translated to their desktop equivalents rather than
// dropped: pinch-zoom becomes the wheel, double-tap zoom becomes double-click,
// swipe-to-page becomes the arrow keys and the on-screen chevrons. Close is the
// ✕ or Escape. Swipe-to-dismiss has no desktop equivalent and is not faked.
//
Rectangle {
    id: root

    // A bounded data: URI handed over by the backend — this never touches the
    // filesystem or the network.
    property string source: ""
    // GIFs must keep animating in the full-pane viewer. Plain photos continue to
    // use Image so they retain the cheaper asynchronous decode path.
    property bool animated: false
    property int decodeWidth: 0
    property int decodeHeight: 0

    // Every image in the conversation, as [{ uri, key }], so the viewer can page
    // the way Android's pager does. `index` selects one; with no list the viewer
    // falls back to the single `source` it was handed.
    property var images: []
    property int index: -1

    readonly property bool paged: index >= 0 && index < images.length
    readonly property string current: paged ? images[index].uri : source
    readonly property string currentKey: paged ? images[index].key : ""
    readonly property bool currentAnimated: paged ? images[index].animated === true : animated
    readonly property int currentDecodeWidth: paged ? Number(images[index].decodeWidth || 0)
                                                    : decodeWidth
    readonly property int currentDecodeHeight: paged ? Number(images[index].decodeHeight || 0)
                                                     : decodeHeight
    readonly property int currentStatus: currentAnimated ? animation.status : photo.status

    signal closed
    // The caller owns the file dialog and the backend call; the viewer only says
    // which message the user asked to save.
    signal saveRequested(string messageKey)

    function next()  { if (paged && index < images.length - 1) { index++; resetZoom(); } }
    function prev()  { if (paged && index > 0)                 { index--; resetZoom(); } }
    function resetZoom() { zoom = 1.0; panX = 0; panY = 0; }

    // 1.0 is fit-to-view. Bounded so a stray wheel spin cannot lose the image.
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0

    z: 1000
    color: Qt.rgba(0, 0, 0, 0.9)

    // Escape closes. The overlay has to actually hold focus for that to fire,
    // and it has to take focus back whenever it is re-shown.
    focus: visible
    Keys.onEscapePressed: function (event) {
        event.accepted = true;
        root.closed();
    }
    Keys.onLeftPressed:  function (event) { event.accepted = true; root.prev(); }
    Keys.onRightPressed: function (event) { event.accepted = true; root.next(); }
    onCurrentChanged: resetZoom()
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
        acceptedButtons: Qt.LeftButton
        cursorShape: root.zoom > 1.0
                     ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                     : Qt.ArrowCursor
        onClicked: root.forceActiveFocus()
        // Double-click toggles between fit and 2x, as double-tap does on Android.
        onDoubleClicked: {
            if (root.zoom > 1.0) root.resetZoom();
            else root.zoom = 2.0;
        }
        // Drag pans, but only when there is something to pan to.
        property real pressX: 0
        property real pressY: 0
        property real originX: 0
        property real originY: 0
        onPressed: function (mouse) {
            pressX = mouse.x; pressY = mouse.y;
            originX = root.panX; originY = root.panY;
        }
        onPositionChanged: function (mouse) {
            if (!pressed || root.zoom <= 1.0)
                return;
            root.panX = originX + (mouse.x - pressX);
            root.panY = originY + (mouse.y - pressY);
        }

        WheelHandler {
            // Wheel zooms about the centre. 1.0 is fit; below that the image
            // would float in dead space, so that is the floor.
            onWheel: function (event) {
                root.zoom = Math.max(1.0, Math.min(6.0,
                    root.zoom * (event.angleDelta.y > 0 ? 1.15 : 1 / 1.15)));
                if (root.zoom === 1.0) { root.panX = 0; root.panY = 0; }
            }
        }
    }

    AnimatedImage {
        id: animation
        objectName: root.objectName + "-animation"
        anchors.fill: parent
        anchors.margins: Theme.space6
        visible: root.currentAnimated
        source: visible && root.currentDecodeWidth > 0 && root.currentDecodeHeight > 0
                ? root.current : ""
        fillMode: Image.PreserveAspectFit
        scale: root.zoom
        transformOrigin: Item.Center
        x: root.panX
        y: root.panY
        playing: visible
        cache: false
        // Both axes come from the actual local GIF header and are bounded before
        // QML receives a source. This preserves ratio without an unbounded axis.
        sourceSize.width: root.currentDecodeWidth
        sourceSize.height: root.currentDecodeHeight
        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter
        Behavior on scale { NumberAnimation { duration: 90 } }
    }

    Image {
        id: photo
        anchors.fill: parent
        anchors.margins: Theme.space6
        visible: !root.currentAnimated
        source: visible ? root.current : ""
        fillMode: Image.PreserveAspectFit
        scale: root.zoom
        transformOrigin: Item.Center
        x: root.panX
        y: root.panY
        Behavior on scale { NumberAnimation { duration: 90 } }
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
        visible: root.currentStatus === Image.Loading || root.currentStatus === Image.Error
                 || root.current === ""
        text: root.currentStatus === Image.Error ? "media unavailable"
              : (root.current === "" ? "no media" : "loading…")
        // Android spec is rgba(255,255,255,0.6); expressed as the text token at
        // 60% so the colour still comes from Theme. The overlay ground is always
        // black, so this stays legible without a second palette.
        color: Theme.text
        opacity: 0.6
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

    // Save, beside the close circle. Only offered when the viewer knows WHICH
    // message it is showing — saving needs the message, not the pixels.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.space4
        anchors.rightMargin: Theme.space4 + 40 + Theme.space2
        visible: root.currentKey !== ""
        width: 40
        height: 40
        radius: 20
        color: saveHit.containsMouse ? Qt.rgba(0, 0, 0, 0.65) : Qt.rgba(0, 0, 0, 0.45)

        PeersIcon { anchors.centerIn: parent; name: "download"; size: 20; color: Theme.text }

        MouseArea {
            id: saveHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.saveRequested(root.currentKey)
        }
    }

    // Paging chevrons, shown only when there is somewhere to page to.
    Repeater {
        model: [{ back: true }, { back: false }]
        delegate: Rectangle {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: modelData.back ? parent.left : undefined
            anchors.right: modelData.back ? undefined : parent.right
            anchors.margins: Theme.space4
            visible: root.paged
                     && (modelData.back ? root.index > 0
                                        : root.index < root.images.length - 1)
            width: 40
            height: 40
            radius: 20
            color: pageHit.containsMouse ? Qt.rgba(0, 0, 0, 0.65) : Qt.rgba(0, 0, 0, 0.45)

            PeersIcon {
                anchors.centerIn: parent
                name: "back"
                size: 22
                color: Theme.text
                rotation: modelData.back ? 0 : 180
            }

            MouseArea {
                id: pageHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.back ? root.prev() : root.next()
            }
        }
    }

    // Position, so paging has a sense of place.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space4
        visible: root.paged && root.images.length > 1
        text: (root.index + 1) + " / " + root.images.length
              + (root.zoom > 1.0 ? "   ·   " + Math.round(root.zoom * 100) + "%" : "")
        color: Theme.text
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.labelSize
    }
}
