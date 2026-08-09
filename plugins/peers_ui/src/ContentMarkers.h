#ifndef PEERS_CONTENT_MARKERS_H
#define PEERS_CONTENT_MARKERS_H

#include <QJsonObject>
#include <QString>

//
// The Peers content-marker codec (ADR 0002).
//
// chat_module 0.2.2 carries only `content: tstr`, so Peers encodes media,
// replies, reactions, pins, avatars and contact cards as marker-prefixed
// payloads inside the message body. The grammar is Peers Android's — reused
// verbatim so the two clients can understand each other — and is specified with
// path:line citations in docs/CONTENT-MARKERS.md.
//
// THIS IS A SECURITY BOUNDARY. Every string reaching these functions came off
// the network and is attacker-controlled. The parser therefore: never allocates
// based on a peer-supplied length, bounds every field, rejects rather than
// repairs malformed input, and never lets a peer-supplied string reach a file
// path or a URL without explicit validation by the caller.
//
namespace ContentMarkers {

// Marker classes. "Folded" markers are control messages that must never render
// as their own bubble (reactions, pins, avatar broadcasts, group config).
enum class Kind {
    Text,          // no marker — plain text
    HostedMedia,   // store1: / store2:
    InlinePhoto,   // img1:
    VoiceNote,     // voc1:
    Location,      // loc1:
    Reply,         // reply1:
    ContactCard,   // addr1:
    Reaction,      // react1:   (folded)
    Pin,           // pin1:     (folded)
    Leave,         // leave1:   (folded)
    Avatar,        // pfp1:     (folded)
    GroupConfig,   // gcfg1:    (folded)
    ReAdd,         // readd1:   (folded)
    Unknown,       // a marker-looking prefix we do not implement
};

// True for control markers that must not produce a message bubble.
bool isFolded(Kind kind);

// The cross-device message identity Peers uses in place of a message id the
// wire does not carry: a two-word FNV-1a over "<author> <body>", rendered as
// exactly 16 lowercase hex characters.
//
// `body` is the RAW stored content — for a reply that is the whole "reply1:…"
// string, not the unwrapped text.
//
// Known and accepted collision: the same author sending an identical body twice
// shares a key, so a reaction lands on both.
QString messageKey(const QString& author, const QString& body);

// Decode a raw message body into the object the view renders. Always returns a
// usable object: an unrecognised or malformed marker degrades to readable text
// rather than an empty bubble or a raw marker string (ADR 0002).
//
// Keys always present: "kind" (see kindName), "text".
// Kind-specific keys are documented in docs/VIEW-MODEL.md.
QJsonObject decodeToJson(const QString& raw);

// One-line conversation-list preview for a raw body, matching Peers'
// chatStore preview mapping ("📷 Photo", "🎤 Voice message", …).
QString previewText(const QString& raw);

// Stable lowercase name for a Kind, as it appears in decodeToJson's "kind".
QString kindName(Kind kind);

// ── encode ──────────────────────────────────────────────────────────────────
// Each returns the raw body to hand to send_message. The grammar is Peers
// Android's, so the phone can parse what we send (docs/CONTENT-MARKERS.md).

// reply1:<key>:<body> — key identifies the quoted message, body is the reply
// text. The body may itself contain colons, so a parser must split ONCE.
QString encodeReply(const QString& targetKey, const QString& body);

// react1:<+|-><emoji>:<key>
QString encodeReaction(bool add, const QString& emoji, const QString& targetKey);

// pin1:<+|-><key>
QString encodePin(bool add, const QString& targetKey);

// addr1:<address> — a shared contact card.
QString encodeContactCard(const QString& address, const QString& label);

// img1:<mime>:<w>:<h><base64> — an inline photo.
//
// Peers uses this for small images and the hosted `store2:` ref for large ones.
// We have no storage-module dependency yet, so this client only speaks inline
// and refuses anything over the cap rather than emitting a message the network
// will drop (see kMaxInlineBytes).
QString encodeInlinePhoto(const QString& mime, int width, int height,
                          const QByteArray& bytes);

// voc1:<mime>:<durMs>:<wf,csv><base64> — an inline voice note.
QString encodeVoiceNote(const QString& mime, int durationMs,
                        const QList<int>& waveform, const QByteArray& bytes);

// The largest payload we will put inline, in raw bytes before base64.
// Beyond this a message is not worth sending: it will not survive the transport.
int maxInlineBytes();

// Read the pixel dimensions out of a PNG or JPEG header. Returns false when the
// format isn't recognised, in which case the caller should send 0x0 and let the
// view use the image's natural size. Deliberately byte-level so the module does
// not need a QtGui dependency for one number.
bool imageSize(const QByteArray& bytes, int* width, int* height);

// The marker class of a raw body, without decoding it.
Kind classify(const QString& raw);

} // namespace ContentMarkers

#endif // PEERS_CONTENT_MARKERS_H
