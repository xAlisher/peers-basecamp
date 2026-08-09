import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

//
// This account's address, in the shape you hand to someone else.
//
// Peers' MyAddressScreen (MyAddressScreen.tsx:141-178) is a panel card holding
// a QrCard with the identicon badge in its centre, the full hex below it in
// `type.code`, and a Copy/Share row. This is that card, minus the QR encoder:
// generating a QR matrix is out of scope here, so the QR area is an honest
// placeholder until `qrAvailable` says otherwise. Never a broken or fake QR —
// a wrong QR silently sends messages to the wrong identity.
//
// Note the placeholder frame is DARK. The real QrCard ground is always white
// (colors.qrBg, QrCard.tsx:167) regardless of theme; painting the placeholder
// white would read as a rendered code that simply failed to draw.
//
Rectangle {
    id: root

    // ── data in ─────────────────────────────────────────────────────────────
    property string address: ""
    property string label: ""
    // A custom avatar (pfp1:) for the centre badge, when one is set.
    property string avatarSource: ""
    // Flip to true only once something can actually draw a scannable code into
    // the frame. Until then the card says so in words.
    property bool qrAvailable: false

    // Side of the QR frame, in px. 260 is the Android default (QrCard size).
    property int qrSize: 200

    // ── actions out ─────────────────────────────────────────────────────────
    signal copy()

    function shortAddress(a) {
        const s = a === undefined || a === null ? "" : String(a);
        return s.length <= 14 ? s : s.slice(0, 6) + "…" + s.slice(-4);
    }

    implicitWidth: 320
    implicitHeight: col.implicitHeight + Theme.space6 * 2

    radius: Theme.radiusCard
    color: Theme.panel
    border.width: Theme.hairline
    border.color: Theme.border

    // Transient "Copied" acknowledgement. Local feedback only — the actual
    // clipboard write belongs to whoever handles copy().
    property bool justCopied: false
    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: root.justCopied = false
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.space6
        spacing: Theme.space4

        // ── QR area ─────────────────────────────────────────────────────────
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.qrSize
            implicitHeight: root.qrSize
            radius: Theme.radiusCard
            color: Theme.pane
            border.width: Theme.hairline
            border.color: Theme.border

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.space3

                // The identicon sits in the centre of the code, exactly as the
                // real QrCard does (backing = total * 0.26 in module units —
                // QrCard.tsx:63-71). The ring behind it is that card's white
                // stroke, restated in panel grey for the dark placeholder.
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Math.round(root.qrSize * 0.30)
                    implicitHeight: implicitWidth
                    radius: implicitWidth * Theme.avatarRadiusRatio
                    color: Theme.panel

                    HexAvatar {
                        anchors.centerIn: parent
                        size: Math.round(root.qrSize * 0.26)
                        seed: root.address
                        kind: "contact"
                        avatarSource: root.avatarSource
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.qrAvailable
                    text: "QR coming soon"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                }
            }
        }

        // ── identity ────────────────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            text: root.label !== "" ? root.label : root.shortAddress(root.address)
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.titleSize
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        // The full hex, selectable. `type.code` (13) in the mono family —
        // address strings depend on a fixed advance to be read aloud or
        // compared by eye.
        TextEdit {
            Layout.fillWidth: true
            text: root.address
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.codeSize
            // An address has no spaces to break on, so wrap anywhere.
            wrapMode: TextEdit.WrapAnywhere
            horizontalAlignment: TextEdit.AlignHCenter
            textFormat: TextEdit.PlainText
        }

        // ── copy ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: copyRow.implicitWidth + Theme.space3 * 2
            implicitHeight: Theme.minTouchTarget
            radius: Theme.radiusCard
            color: copyHover.hovered ? Theme.panel : Theme.pane
            border.width: Theme.hairline
            border.color: root.justCopied ? Theme.accent : Theme.border

            HoverHandler { id: copyHover }
            TapHandler {
                onTapped: {
                    root.copy();
                    root.justCopied = true;
                    copiedTimer.restart();
                }
            }

            RowLayout {
                id: copyRow
                anchors.centerIn: parent
                spacing: Theme.space2

                PeersIcon {
                    name: "copy"
                    size: 16
                    color: root.justCopied ? Theme.accent : Theme.textDim
                }
                Text {
                    text: root.justCopied ? "Copied" : "Copy address"
                    color: root.justCopied ? Theme.accent : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.labelSize
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Anyone with this address can start a conversation with you."
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
