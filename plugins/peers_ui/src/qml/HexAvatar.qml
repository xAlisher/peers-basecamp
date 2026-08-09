import QtQuick
import "Identicon.js" as Identicon
import "Theme.js" as Theme

//
// The Peers identicon: a 5x5 left-right-symmetric grid of FLUSH squares (no
// gaps, no rounding on the cells) inside a rounded square on the canvas ground.
//
// "Hex" is the hex identity string used as the seed, not the shape — this is a
// rounded SQUARE, radius 22% of the side, not a circle and not a hexagon.
//
// The algorithm lives in Identicon.js and is proven byte-identical to Peers
// Android by tests/identicon-equivalence.mjs. Nothing here re-derives it.
//
// Cells overlap by 0.5px deliberately: it is the anti-alias seam guard the
// Android renderer uses, and without it hairline gaps appear between cells.
//
Item {
    id: root

    // The identity to render. Peer address for a 1:1, shared convo id for a
    // group, own address for your own avatar.
    property string seed: ""
    // "contact" or "group". Both resolve to the orange ramp — Peers colours by
    // TRANSPORT, and desktop has only the Logos transport.
    property string kind: "contact"
    // A custom avatar (pfp1:) overrides the identicon entirely when set.
    property string avatarSource: ""

    property int size: 40

    implicitWidth: size
    implicitHeight: size

    readonly property var cells: Identicon.identiconCells(seed, kind)
    readonly property real cell: size / 5

    Rectangle {
        id: ground
        anchors.fill: parent
        radius: root.size * Theme.avatarRadiusRatio
        color: Theme.canvas
        clip: true

        Repeater {
            model: root.avatarSource === "" ? root.cells : []
            delegate: Rectangle {
                required property var modelData
                x: modelData.x * root.cell
                y: modelData.y * root.cell
                width: root.cell + 0.5
                height: root.cell + 0.5
                color: modelData.fill
            }
        }

        Image {
            anchors.fill: parent
            visible: root.avatarSource !== ""
            source: root.avatarSource
            fillMode: Image.PreserveAspectCrop
            // A custom avatar is peer-supplied; never let it run away with
            // memory because of a declared size.
            sourceSize.width: root.size * 2
            sourceSize.height: root.size * 2
            asynchronous: true
            cache: true
        }
    }
}
