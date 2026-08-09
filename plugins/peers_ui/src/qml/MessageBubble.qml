import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

//
// A Peers message bubble.
//
// Own messages are accent-filled with WHITE text — the Android source comment
// is explicit that it is never black. Peer messages are #1F1F1F. Both use a
// uniform 8px radius; Peers does not do the tail-corner trick.
//
// Peers has NO delivered or read receipts (ChatScreen.tsx:3). The only states
// are pending, failed and sent — do not add a tick this app never had.
//
Item {
    id: root

    // One decoded row from messagesJson. Never a raw wire body: the
    // content-marker codec has already run in the backend.
    required property var msg

    readonly property bool own: msg.fromSelf === true
    readonly property string kind: msg.kind !== undefined ? msg.kind : "text"
    readonly property bool failed: msg.state === "failed"
    readonly property bool pending: msg.state === "pending"
    readonly property var reactions: msg.reactions !== undefined ? msg.reactions : []
    // The amplitude bars measured when the note was recorded (voice notes only).
    readonly property var waveform: msg.waveform !== undefined ? msg.waveform : []

    function mmss(ms) {
        const total = Math.round(ms / 1000);
        const m = Math.floor(total / 60);
        const sec = total % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    // Raised when the user taps an inline photo, so the view can open the
    // full-size viewer. The bubble itself stays presentational.
    signal imageClicked(string uri, string messageKey)

    // Right-click, or a long press so a touchscreen behaves like the phone.
    // Coordinates are scene-relative so the menu can place itself.
    signal menuRequested(var msg, real sceneX, real sceneY)

    implicitHeight: rowLayout.implicitHeight
    implicitWidth: parent ? parent.width : 0

    RowLayout {
        id: rowLayout
        width: parent.width
        spacing: Theme.space2
        layoutDirection: root.own ? Qt.RightToLeft : Qt.LeftToRight

        // Sender identicon, peer messages only — own messages need no
        // attribution.
        HexAvatar {
            visible: !root.own
            size: 28
            seed: root.msg.sender !== undefined ? root.msg.sender : ""
            kind: "contact"
            Layout.alignment: Qt.AlignBottom
        }

        // Android opens this menu on a 350 ms long-press; desktop adds right-click.
        TapHandler {
            acceptedButtons: Qt.RightButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: function (evt) {
                const p = bubble.mapToItem(null, evt.position.x, evt.position.y);
                root.menuRequested(root.msg, p.x, p.y);
            }
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            longPressThreshold: 0.35
            onLongPressed: {
                const p = bubble.mapToItem(null, 0, 0);
                root.menuRequested(root.msg, p.x, p.y);
            }
        }

        Rectangle {
            id: bubble
            Layout.maximumWidth: rowLayout.width * Theme.bubbleMaxWidthRatio
            Layout.preferredWidth: content.implicitWidth + Theme.space3 * 2
            implicitHeight: content.implicitHeight + Theme.space2 * 2
            Layout.preferredHeight: implicitHeight

            radius: Theme.radiusBubble
            color: root.own ? Theme.bubbleOwn : Theme.bubblePeer
            // A failed send is outlined, not recoloured — the text must stay
            // readable while the user decides whether to resend.
            border.width: root.failed ? Theme.hairline : 0
            border.color: Theme.unread
            opacity: root.pending ? 0.55 : 1.0

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: Theme.space2
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                spacing: 2

                // Quoted message, for a reply.
                //
                // This shows `quotedText` — the text of the message being
                // replied to, resolved by the backend from the reply marker's
                // target key. It is NOT `msg.text`, which is the reply's own
                // body; binding that here makes the quote echo the reply, which
                // is what shipped until a screenshot caught it.
                Rectangle {
                    visible: root.kind === "reply"
                    Layout.fillWidth: true
                    implicitHeight: quotedCol.implicitHeight + Theme.space1 * 2
                    color: Qt.rgba(0, 0, 0, 0.22)
                    radius: 4

                    ColumnLayout {
                        id: quotedCol
                        anchors.fill: parent
                        anchors.margins: Theme.space1
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.msg.quotedSender !== undefined ? root.msg.quotedSender : ""
                            color: root.own ? Theme.bubbleOwnText : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.msg.quotedText !== undefined ? root.msg.quotedText : ""
                            color: root.own ? Theme.bubbleOwnText : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.labelSize
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Inline photo. The backend hands over a bounded data: URI, so
                // nothing here touches the filesystem or the network.
                // An animated GIF needs AnimatedImage; a plain Image shows only
                // the first frame. QtMultimedia is not available in the host, so
                // video and voice open externally instead (below).
                AnimatedImage {
                    id: gif
                    visible: root.msg.mime !== undefined
                             && String(root.msg.mime) === "image/gif"
                             && source !== ""
                    source: root.msg.dataUri !== undefined ? root.msg.dataUri : ""
                    Layout.preferredWidth: Math.min(implicitWidth, 320)
                    Layout.preferredHeight: implicitWidth > 0
                                            ? Layout.preferredWidth * (implicitHeight / implicitWidth)
                                            : 0
                    fillMode: Image.PreserveAspectFit
                    playing: true
                    cache: true
                }

                Image {
                    id: photo
                    // Inline photos and fetched hosted media render the same way;
                    // hosted media only has a source once the fetch completes.
                    visible: (root.kind === "photo" || root.kind === "media")
                             && source !== "" && !gif.visible
                    source: root.msg.dataUri !== undefined ? root.msg.dataUri : ""
                    Layout.preferredWidth: Math.min(implicitWidth, 320)
                    Layout.preferredHeight: implicitWidth > 0
                                            ? Layout.preferredWidth * (implicitHeight / implicitWidth)
                                            : 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // A peer-supplied image must not be able to blow up memory
                    // through its declared dimensions.
                    sourceSize.width: 640

                    TapHandler {
                        enabled: photo.visible
                        onTapped: root.imageClicked(photo.source, String(root.msg.key || ""))
                    }
                }

                Text {
                    Layout.fillWidth: true
                    // A photo's caption is its text; with no caption the label
                    // would just repeat the picture. A voice note's text is the
                    // conversation-list preview ("🎤 Voice message"), which the
                    // waveform and duration already say — Android's VoiceBubble
                    // shows no such line either.
                    visible: !photo.visible && !gif.visible && root.kind !== "voice"
                    text: root.msg.text !== undefined ? root.msg.text : ""
                    color: root.own ? Theme.bubbleOwnText : Theme.bubblePeerText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText   // never render peer text as markup
                }

                // The recorded waveform, exactly as Android draws it: the bars
                // measured at capture time, not a decorative animation. Bars are
                // 0..100 with the loudest at 100 (VoiceBubble.tsx).
                Row {
                    visible: root.kind === "voice" && root.waveform.length > 0
                    spacing: 2
                    Repeater {
                        model: root.waveform
                        delegate: Rectangle {
                            required property int modelData
                            width: 3
                            radius: 1.5
                            // A floor of 2px so a silent bar is still a bar and
                            // the strip does not develop gaps.
                            height: Math.max(2, Math.round(modelData / 100 * 28))
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.own ? Theme.bubbleOwnText : Theme.accent
                            opacity: root.own ? 0.85 : 0.9
                        }
                    }
                }

                // Video and voice: the host has no QtMultimedia, so offer to open
                // the decrypted file in the desktop's own player rather than
                // pretending to play it inline.
                Rectangle {
                    Layout.fillWidth: true
                    visible: (root.kind === "voice"
                              || (root.kind === "media"
                                  && String(root.msg.mime || "").indexOf("video") === 0))
                             && String(root.msg.localPath || "") !== ""
                    implicitHeight: 36
                    radius: Theme.radiusCard
                    color: root.own ? Qt.rgba(0, 0, 0, 0.22) : Theme.panel
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space2
                        PeersIcon {
                            name: "play"; size: 14
                            color: root.own ? Theme.bubbleOwnText : Theme.accent
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.kind === "voice"
                                  ? "Play voice note  ·  " + root.mmss(root.msg.durationMs || 0)
                                  : "Play video"
                            color: root.own ? Theme.bubbleOwnText : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.labelSize
                        }
                    }
                    TapHandler {
                        onTapped: Qt.openUrlExternally("file://" + root.msg.localPath)
                    }
                }

                // A shared location: the coordinates, tappable through to a map.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.kind === "location"
                    implicitHeight: 44
                    radius: Theme.radiusCard
                    color: root.own ? Qt.rgba(0, 0, 0, 0.22) : Theme.panel
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space2
                        PeersIcon { name: "search"; size: 16; color: Theme.accent }
                        Text {
                            Layout.fillWidth: true
                            text: root.msg.lat !== undefined
                                  ? Number(root.msg.lat).toFixed(5) + ", " + Number(root.msg.lng).toFixed(5)
                                  : ""
                            color: root.own ? Theme.bubbleOwnText : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.codeSize
                        }
                    }
                    TapHandler {
                        onTapped: Qt.openUrlExternally(
                            "https://www.openstreetmap.org/?mlat=" + root.msg.lat
                            + "&mlon=" + root.msg.lng + "#map=16/" + root.msg.lat + "/" + root.msg.lng)
                    }
                }

                // Hosted media still downloading. Without this the bubble looks
                // like a plain text message saying "Photo" until the fetch lands.
                Text {
                    Layout.fillWidth: true
                    visible: root.kind === "media" && !photo.visible
                    text: "Downloading\u2026"
                    color: root.own ? Qt.rgba(1, 1, 1, 0.75) : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                }

                // Reaction pills. Emoji here are CONTENT (a user picked them),
                // not iconography — the never-emoji-as-icon rule doesn't apply.
                Flow {
                    Layout.fillWidth: true
                    visible: root.reactions.length > 0
                    spacing: Theme.space1

                    Repeater {
                        model: root.reactions
                        delegate: Rectangle {
                            required property var modelData
                            height: 20
                            width: pill.implicitWidth + Theme.space2
                            radius: Theme.radiusPill
                            color: root.own ? Qt.rgba(0, 0, 0, 0.22) : Theme.panel
                            border.width: modelData.mine ? Theme.hairline : 0
                            border.color: Theme.accent

                            Row {
                                id: pill
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: modelData.emoji
                                    font.pixelSize: Theme.captionSize
                                }
                                Text {
                                    // Peers only shows a count when it's > 1.
                                    visible: modelData.count > 1
                                    text: modelData.count
                                    color: root.own ? Theme.bubbleOwnText : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.captionSize
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.failed ? "failed" : Qt.formatDateTime(
                              new Date(root.msg.timestampMs !== undefined
                                       ? root.msg.timestampMs : 0), "h:mm AP")
                    color: root.failed ? Theme.unread
                           : (root.own ? Qt.rgba(1, 1, 1, 0.75) : Theme.textDim)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                }
            }
        }

        Item { Layout.fillWidth: true }
    }
}
