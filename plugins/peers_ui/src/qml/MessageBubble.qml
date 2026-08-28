import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "MessageLayout.js" as MessageLayout

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

    // Briefly outlined after the pinned bar jumps here.
    property bool highlighted: false
    // True while this message's audio is playing, so the row offers to stop it.
    property bool playing: false

    readonly property bool own: msg.fromSelf === true
    readonly property string kind: msg.kind !== undefined ? msg.kind : "text"
    readonly property bool failed: msg.state === "failed"
    readonly property bool pending: msg.state === "pending"
    readonly property string statusText: pending ? "sending\u2026"
                                                 : (failed ? "failed" : Qt.formatDateTime(
                                                        new Date(msg.timestampMs !== undefined
                                                                 ? msg.timestampMs : 0), "HH:mm"))
    readonly property var reactions: msg.reactions !== undefined ? msg.reactions : []
    // The amplitude bars measured when the note was recorded (voice notes only).
    readonly property var waveform: msg.waveform !== undefined ? msg.waveform : []
    readonly property string senderLabel: msg.senderLabel !== undefined ? msg.senderLabel : ""
    readonly property string senderHex: msg.senderHex !== undefined ? msg.senderHex : ""
    // A label was actually set — otherwise senderLabel IS the hex and printing
    // both would say the same thing twice.
    readonly property bool senderNamed: senderLabel !== "" && senderLabel !== senderHex
    readonly property real maxBubbleWidth: Math.floor(width * MessageLayout.bubbleMaxRatio)
    readonly property var mediaSize: MessageLayout.fitMedia(msg.width || 0, msg.height || 0)
    readonly property real displayMediaWidth: Math.min(mediaSize.width,
                                                       Math.max(1, maxBubbleWidth - Theme.space1))
    readonly property real displayMediaHeight: Math.max(1,
        Math.round(mediaSize.height * displayMediaWidth / Math.max(1, mediaSize.width)))
    readonly property real maxVoiceWaveWidth: MessageLayout.voiceWaveWidth(width)
    readonly property var voiceBars: MessageLayout.downsampleWaveform(waveform,
                                                                      maxVoiceWaveWidth)
    readonly property real voiceWaveWidth: Math.min(maxVoiceWaveWidth,
        Math.max(Math.min(MessageLayout.voiceMinWave, maxVoiceWaveWidth),
                 voiceBars.length * (MessageLayout.voiceBarWidth
                                     + MessageLayout.voiceBarGap)
                 - MessageLayout.voiceBarGap))
    readonly property bool imageMessage: kind === "photo"
                                         || (kind === "media"
                                             && String(msg.mime || "").indexOf("image/") === 0)
    readonly property bool gifMessage: imageMessage && String(msg.mime || "") === "image/gif"
    readonly property bool videoMessage: kind === "media"
                                         && String(msg.mime || "").indexOf("video/") === 0
    readonly property bool mediaFrame: imageMessage || videoMessage
    readonly property string mediaError: String(msg.mediaError || "")
    readonly property bool compactVoice: maxBubbleWidth < 180
    readonly property bool voiceReady: String(msg.localPath || "") !== ""
    readonly property real desiredBubbleWidth: mediaFrame
        ? Math.min(maxBubbleWidth, displayMediaWidth + Theme.space1)
        : (kind === "voice"
           ? Math.min(maxBubbleWidth, voiceWaveWidth + MessageLayout.voiceReserved)
           : (kind === "reply" ? Math.min(maxBubbleWidth, 240)
              : (kind === "contact" ? Math.min(maxBubbleWidth, 260)
                 : (kind === "location" ? Math.min(maxBubbleWidth, 260)
                    : (kind === "media" ? Math.min(maxBubbleWidth, 220)
                       : Math.min(maxBubbleWidth,
                                  Math.max(48, bodyMetrics.advanceWidth + Theme.space3 * 2)))))))

    TextMetrics {
        id: bodyMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        text: root.msg.text !== undefined ? String(root.msg.text) : ""
    }
    TextMetrics {
        id: statusMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        text: root.statusText
    }

    // The label is user-supplied text going into a StyledText, so it has to be
    // escaped — a peer's label is not markup.
    function escapeHtml(t) {
        return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function mmss(ms) {
        const total = Math.round(ms / 1000);
        const m = Math.floor(total / 60);
        const sec = total % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    // Raised when the user taps an inline photo, so the view can open the
    // full-size viewer. The bubble itself stays presentational.
    signal imageClicked(string uri, string messageKey)
    // A shared contact card's two actions (AddressCard.tsx): start/open the 1:1
    // with them, or look at the address itself.
    // Play/open an attachment. Qt.openUrlExternally is a silent no-op in the
    // Basecamp QML sandbox, so this has to go through the backend.
    signal openMedia(string messageKey)
    signal openExternal(string url)
    signal addContact(string address, string label)
    signal viewContact(string address, string label)

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

        // Who sent this. Android draws it above every INCOMING bubble, 1:1 and
        // group alike (resolveAttribution): the local label in the primary
        // colour, the short hex dimmed beside it, or just the hex when the peer
        // has no label. In a busy group an unattributed bubble is unreadable.
        ColumnLayout {
            spacing: 2
            Layout.preferredWidth: Math.max(root.desiredBubbleWidth, statusMetrics.advanceWidth)
            Layout.maximumWidth: Math.max(root.maxBubbleWidth, statusMetrics.advanceWidth)

            RowLayout {
                visible: !root.own && root.senderHex !== ""
                Layout.fillWidth: true
                spacing: Theme.space1

                HexAvatar {
                    id: attributionAvatar
                    size: 16
                    seed: root.msg.sender !== undefined ? root.msg.sender : ""
                    kind: "contact"
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: root.senderNamed
                          ? ("<font color=\"" + Theme.text + "\">" + root.escapeHtml(root.senderLabel)
                             + "</font> <font color=\"" + Theme.textDim + "\">" + root.senderHex
                             + "</font>")
                          : ("<font color=\"" + Theme.text + "\">" + root.senderHex + "</font>")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

        Rectangle {
            id: bubble
            Layout.maximumWidth: root.maxBubbleWidth
            Layout.preferredWidth: root.desiredBubbleWidth
            Layout.alignment: root.own ? Qt.AlignRight : Qt.AlignLeft
            implicitHeight: content.implicitHeight
                            + (root.mediaFrame ? 4 : Theme.space2 * 2)
            Layout.preferredHeight: implicitHeight

            radius: Theme.radiusBubble
            clip: true
            color: root.own ? Theme.bubbleOwn : Theme.bubblePeer
            // A failed send is outlined, not recoloured — the text must stay
            // readable while the user decides whether to resend.
            border.width: root.failed || root.highlighted ? Theme.hairline : 0
            border.color: root.failed ? Theme.unread : Theme.accent
            Behavior on border.width { NumberAnimation { duration: 150 } }
            opacity: root.pending ? 0.55 : 1.0

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: root.mediaFrame ? 2 : Theme.space2
                anchors.leftMargin: root.mediaFrame ? 2 : Theme.space3
                anchors.rightMargin: root.mediaFrame ? 2 : Theme.space3
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
                        TextEdit {
                            objectName: root.objectName + "-quote-body"
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, font.pixelSize * 2.5)
                            text: root.msg.quotedText !== undefined ? root.msg.quotedText : ""
                            color: root.own ? Theme.bubbleOwnText : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.labelSize
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.onAccent
                            padding: 0
                            clip: true
                        }
                    }
                }

                // Inline photo. The backend hands over a bounded data: URI, so
                // nothing here touches the filesystem or the network.
                // An animated GIF needs AnimatedImage; a plain Image shows only
                // the first frame. QtMultimedia is not available in the host, so
                // video and voice open externally instead (below).
                // One stable frame owns the image, GIF and status overlay. Making
                // these siblings in the ColumnLayout doubles the row height while
                // a decoder is loading.
                Item {
                    visible: root.imageMessage
                    Layout.preferredWidth: visible ? root.displayMediaWidth : 0
                    Layout.preferredHeight: visible ? root.displayMediaHeight : 0
                    Layout.maximumWidth: visible ? root.displayMediaWidth : 0
                    Layout.maximumHeight: visible ? root.displayMediaHeight : 0

                    AnimatedImage {
                        id: gif
                        anchors.fill: parent
                        visible: root.gifMessage && String(source) !== ""
                        source: root.msg.imageUri !== undefined ? root.msg.imageUri : ""
                        fillMode: Image.PreserveAspectCrop
                        playing: true
                        // Bound decoded frame dimensions and avoid retaining every
                        // hostile/oversized animation in the global image cache.
                        sourceSize.width: Number(root.msg.gifDecodeWidth || 0)
                        sourceSize.height: Number(root.msg.gifDecodeHeight || 0)
                        cache: false

                    }

                    Image {
                        id: photo
                        anchors.fill: parent
                        // Inline photos and fetched hosted media render the same way;
                        // hosted media only has a source once the fetch completes.
                        visible: !root.gifMessage && String(source) !== ""
                        source: root.msg.imageUri !== undefined ? root.msg.imageUri : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 640

                    }

                    // One stable handler opens either the static or animated
                    // renderer without duplicating interaction behavior.
                    TapHandler {
                        enabled: String(root.msg.imageUri || "") !== ""
                                 && (root.gifMessage ? gif.status === Image.Ready
                                                     : photo.status === Image.Ready)
                        onTapped: root.imageClicked(String(root.msg.imageUri || ""),
                                                    String(root.msg.key || ""))
                    }

                    Rectangle {
                        readonly property bool decodeFailed:
                            (root.gifMessage && gif.status === Image.Error)
                            || (!root.gifMessage && photo.status === Image.Error)
                        readonly property bool decoderBusy:
                            (root.gifMessage && gif.status === Image.Loading)
                            || (!root.gifMessage && photo.status === Image.Loading)
                        anchors.fill: parent
                        visible: String(root.msg.imageUri || "") === ""
                                 || root.mediaError !== "" || decodeFailed || decoderBusy
                        radius: Theme.radiusCard - 2
                        color: Qt.rgba(0, 0, 0, 0.18)
                        Text {
                            anchors.centerIn: parent
                            text: root.mediaError !== "" || parent.decodeFailed
                                  ? "Media unavailable" : "Downloading\u2026"
                            color: root.own ? Qt.rgba(1, 1, 1, 0.75) : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize
                        }
                    }
                }

                // A shared contact (addr1:) is a real, visible message on both
                // sides — identicon, the label that travelled (else the short
                // hex), the hex, and two actions. AddressCard.tsx.
                ColumnLayout {
                    visible: root.kind === "contact"
                    Layout.fillWidth: true
                    spacing: Theme.space3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space3

                        HexAvatar {
                            size: 40
                            seed: String(root.msg.address || "")
                            kind: "contact"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: String(root.msg.label || "").length > 0
                                      ? String(root.msg.label)
                                      : String(root.msg.address || "").slice(0, 8)
                                color: root.own ? Theme.bubbleOwnText : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.titleSize
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Text {
                                Layout.fillWidth: true
                                text: String(root.msg.address || "").slice(0, 8)
                                color: root.own ? Qt.rgba(1, 1, 1, 0.75) : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.labelSize
                                elide: Text.ElideRight
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space3

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: Theme.radiusCard
                            color: addHover.hovered ? Theme.accentHover : Theme.accent
                            HoverHandler { id: addHover }
                            TapHandler {
                                onTapped: root.addContact(String(root.msg.address || ""),
                                                          String(root.msg.label || ""))
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "Add"
                                color: Theme.onAccent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.labelSize
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: Theme.radiusCard
                            color: "transparent"
                            border.width: Theme.hairline
                            border.color: Theme.accent
                            HoverHandler { id: viewHover }
                            TapHandler {
                                onTapped: root.viewContact(String(root.msg.address || ""),
                                                           String(root.msg.label || ""))
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "View"
                                color: viewHover.hovered ? Theme.accentHover : Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.labelSize
                            }
                        }
                    }
                }

                TextEdit {
                    objectName: root.objectName + "-body"
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    // A photo's caption is its text; with no caption the label
                    // would just repeat the picture. A voice note's text is the
                    // conversation-list preview ("🎤 Voice message"), which the
                    // waveform and duration already say — Android's VoiceBubble
                    // shows no such line either.
                    // Generic hosted files have no richer delegate; keep their
                    // caption/fallback visible rather than emitting an empty bubble.
                    visible: root.kind === "text" || root.kind === "reply"
                             || (root.kind === "media"
                                 && !root.imageMessage && !root.videoMessage)
                    text: root.msg.text !== undefined ? root.msg.text : ""
                    color: root.own ? Theme.bubbleOwnText : Theme.bubblePeerText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText   // never render peer text as markup
                    readOnly: true
                    selectByMouse: true
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    padding: 0
                }

                // Android's compact VoiceBubble: play, bounded waveform, duration
                // in one row. Long recordings are downsampled rather than pushing
                // the bubble off-screen; short notes stay compact.
                RowLayout {
                    visible: root.kind === "voice"
                    Layout.preferredWidth: root.desiredBubbleWidth - Theme.space3 * 2
                    Layout.preferredHeight: 32
                    spacing: root.compactVoice ? Theme.space1 : Theme.space2

                    Item {
                        Layout.preferredWidth: root.compactVoice ? 24 : 32
                        Layout.preferredHeight: 32
                        Accessible.role: Accessible.Button
                        Accessible.name: root.playing ? "Stop voice message" : "Play voice message"
                        Accessible.ignored: !root.voiceReady
                        PeersIcon {
                            anchors.centerIn: parent
                            name: root.playing ? "close" : "play"
                            size: 16
                            color: root.own ? Theme.bubbleOwnText : Theme.text
                            opacity: root.voiceReady ? 1 : 0.45
                        }
                        TapHandler {
                            enabled: root.voiceReady
                            onTapped: root.openMedia(String(root.msg.key || ""))
                        }
                    }
                    Row {
                        Layout.preferredWidth: root.voiceWaveWidth
                        Layout.preferredHeight: 24
                        spacing: MessageLayout.voiceBarGap
                        clip: true
                        Repeater {
                            model: root.voiceBars
                            delegate: Rectangle {
                                required property real modelData
                                width: MessageLayout.voiceBarWidth
                                radius: 1
                                height: Math.max(3,
                                                 Math.round(Math.min(100, modelData)
                                                            / 100 * 22))
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.own ? Theme.bubbleOwnText : Theme.text
                                opacity: 0.85
                            }
                        }
                    }
                    Text {
                        text: root.mmss(root.msg.durationMs || 0)
                        color: root.own ? Theme.bubbleOwnText : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.captionSize
                    }
                }

                // Video playback remains in the backend because the Basecamp
                // host does not ship QtMultimedia. Preserve the declared frame
                // and use Android's centered play badge.
                Rectangle {
                    objectName: root.objectName + "-video-play"
                    visible: root.videoMessage
                    enabled: String(root.msg.localPath || "") !== ""
                    Layout.preferredWidth: visible ? root.displayMediaWidth : 0
                    Layout.preferredHeight: visible ? root.displayMediaHeight : 0
                    radius: Theme.radiusCard - 2
                    color: Qt.rgba(0, 0, 0, 0.28)
                    Accessible.role: Accessible.Button
                    Accessible.name: "Play video"
                    Accessible.ignored: !enabled
                    Image {
                        anchors.fill: parent
                        source: root.msg.videoThumbnailUri !== undefined
                                ? root.msg.videoThumbnailUri : ""
                        visible: String(source) !== ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 640
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 56
                        height: 56
                        radius: 28
                        color: Qt.rgba(0, 0, 0, 0.45)
                        PeersIcon {
                            anchors.centerIn: parent
                            name: "play"
                            size: 28
                            color: Theme.bubbleOwnText
                        }
                    }
                    TapHandler {
                        enabled: parent.enabled
                        onTapped: root.openMedia(String(root.msg.key || ""))
                    }
                }

                // A shared location: coordinates + a quiet action hint, matching
                // Android's locRow rather than nesting a card inside the bubble.
                ColumnLayout {
                    visible: root.kind === "location"
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.msg.lat !== undefined
                              ? Number(root.msg.lat).toFixed(5) + ", " + Number(root.msg.lng).toFixed(5)
                              : ""
                        color: root.own ? Theme.bubbleOwnText : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Open in maps"
                        color: root.own ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.captionSize
                    }
                    TapHandler {
                        onTapped: root.openExternal(
                            "https://www.openstreetmap.org/?mlat=" + root.msg.lat
                            + "&mlon=" + root.msg.lng + "#map=16/" + root.msg.lat + "/" + root.msg.lng)
                    }
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

            }
        }

        // Android keeps status/time outside the fill so compact text and media
        // bubbles do not grow a footer in their coloured surface.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: timestamp.implicitHeight
            Text {
                id: timestamp
                x: root.own ? bubble.x + bubble.width - width : bubble.x
                text: root.statusText
                color: root.failed ? Theme.unread : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
            }
        }
        }

        Item { Layout.fillWidth: true }
    }
}
