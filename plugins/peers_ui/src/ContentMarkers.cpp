#include "ContentMarkers.h"

#include <QJsonArray>
#include <QRegularExpression>
#include <QStringList>
#include <QUrl>

namespace ContentMarkers {
namespace {

// The unit separator Peers uses between a marker's header and its payload.
// The separator between a marker's header and its payload.
//
// Peers Android uses the PRINTABLE glyph U+241F SYMBOL FOR UNIT SEPARATOR (UTF-8
// E2 90 9F) — `const SEP = '\u241F'` in voiceMsg.ts, imageMsg.ts, relay.ts and
// the BLE codecs — NOT the ASCII control character U+001F. They look alike in a
// description and are different bytes on the wire.
//
// We emitted U+001F for a long time, which desktop⇄desktop never noticed because
// both ends agreed on the wrong byte; the phone's parser simply could not find a
// separator and fell back to rendering the raw marker as text. So: EMIT U+241F,
// and ACCEPT either, so history written by an older build still decodes.
constexpr QChar kUS = QChar(0x241F);
constexpr QChar kLegacyUS = QChar(0x001F);

// Index of the separator, whichever form it takes. Earliest wins: a payload is
// base64 or a path and contains neither, so there is no ambiguity to resolve.
int usIndex(const QString& payload)
{
    const int a = payload.indexOf(kUS);
    const int b = payload.indexOf(kLegacyUS);
    if (a < 0) return b;
    if (b < 0) return a;
    return qMin(a, b);
}

// Hard bounds. Peer-controlled input never drives an allocation, and a body
// that exceeds these is rejected rather than truncated into something that
// looks valid.
constexpr int kMaxBody = 1 << 20;      // 1 MiB — far above any real text body
constexpr int kMaxHeaderFields = 8;
constexpr int kMaxLabelLen = 256;
constexpr int kMaxKeyLen = 64;
// The largest raw payload we will put inline. Base64 inflates by ~4/3, and the
// whole thing has to survive an MLS message over the delivery network, so this
// is deliberately conservative — refusing is better than emitting a message the
// transport silently drops.
constexpr int kMaxInlineBytes = 256 * 1024;

struct MarkerDef {
    const char* prefix;
    Kind kind;
};

// Order matters: "store2:" and "store1:" must be tested before any shorter
// prefix that could shadow them, and "pfp1:clear" is handled inside the pfp1
// branch rather than as a separate prefix.
const MarkerDef kMarkers[] = {
    { "store1:", Kind::HostedMedia }, { "store2:", Kind::HostedMedia },
    { "img1v:", Kind::InlinePhoto },  { "img1:", Kind::InlinePhoto },
    { "voc1v:", Kind::VoiceNote },    { "voc1:", Kind::VoiceNote },
    { "loc1:", Kind::Location },      { "reply1:", Kind::Reply },
    { "addr1:", Kind::ContactCard },  { "react1:", Kind::Reaction },
    { "pin1:", Kind::Pin },           { "leave1:", Kind::Leave },
    { "pfp1:", Kind::Avatar },        { "gcfg1:", Kind::GroupConfig },
    { "readd1:", Kind::ReAdd },
};

// A body that looks like "<lowercase-alnum>:" but matches no known marker. We
// must not render such a thing raw — that is how a future Android marker leaks
// wire text into a desktop bubble.
bool looksLikeMarker(const QString& s)
{
    const int colon = s.indexOf(QLatin1Char(':'));
    if (colon <= 0 || colon > 12)
        return false;
    for (int i = 0; i < colon; ++i) {
        const QChar c = s.at(i);
        if (!c.isLower() && !c.isDigit())
            return false;
    }
    return true;
}

QString clampLabel(QString s)
{
    if (s.size() > kMaxLabelLen)
        s.truncate(kMaxLabelLen);
    // Strip control characters — a peer-supplied label reaches the UI.
    QString out;
    out.reserve(s.size());
    for (const QChar c : s) {
        if (!c.isNull() && (c.isPrint() || c.isSpace()))
            out.append(c);
    }
    return out.trimmed();
}

// The header portion of a marker body: everything before the unit separator, or
// the whole payload when there is none.
QString headerOf(const QString& payload)
{
    const int us = usIndex(payload);
    return us < 0 ? payload : payload.left(us);
}

QString afterUS(const QString& payload)
{
    const int us = usIndex(payload);
    return us < 0 ? QString() : payload.mid(us + 1);
}

} // namespace

bool isFolded(Kind kind)
{
    switch (kind) {
    case Kind::Reaction:
    case Kind::Pin:
    case Kind::Leave:
    case Kind::Avatar:
    case Kind::GroupConfig:
    case Kind::ReAdd:
        return true;
    default:
        return false;
    }
}

QByteArray inlinePayloadBytes(const QString& raw)
{
    const int colon = raw.indexOf(QLatin1Char(':'));
    if (colon < 0)
        return {};
    const QString b64 = afterUS(raw.mid(colon + 1));
    // A local marker (voc1v:) carries a path here, not base64; QByteArray's
    // decoder is lenient, so guard on the marker instead of on the content.
    if (b64.isEmpty() || raw.startsWith(QLatin1String("voc1v:"))
        || raw.startsWith(QLatin1String("img1v:")))
        return {};
    return QByteArray::fromBase64(b64.toLatin1());
}

QString kindName(Kind kind)
{
    switch (kind) {
    case Kind::Text:        return QStringLiteral("text");
    case Kind::HostedMedia: return QStringLiteral("media");
    case Kind::InlinePhoto: return QStringLiteral("photo");
    case Kind::VoiceNote:   return QStringLiteral("voice");
    case Kind::Location:    return QStringLiteral("location");
    case Kind::Reply:       return QStringLiteral("reply");
    case Kind::ContactCard: return QStringLiteral("contact");
    case Kind::Reaction:    return QStringLiteral("reaction");
    case Kind::Pin:         return QStringLiteral("pin");
    case Kind::Leave:       return QStringLiteral("leave");
    case Kind::Avatar:      return QStringLiteral("avatar");
    case Kind::GroupConfig: return QStringLiteral("groupConfig");
    case Kind::ReAdd:       return QStringLiteral("readd");
    case Kind::Unknown:     return QStringLiteral("unknown");
    }
    return QStringLiteral("unknown");
}

Kind classify(const QString& raw)
{
    if (raw.isEmpty() || raw.size() > kMaxBody)
        return Kind::Text;
    for (const MarkerDef& m : kMarkers) {
        if (raw.startsWith(QLatin1String(m.prefix)))
            return m.kind;
    }
    return looksLikeMarker(raw) ? Kind::Unknown : Kind::Text;
}

QString messageKey(const QString& author, const QString& body)
{
    // Two-word FNV-1a over "<author> <body>", iterating UTF-16 code units, with
    // 32-bit wrapping multiply. Must match src/messages/reactions.ts exactly or
    // reactions and pins land on the wrong message.
    constexpr quint32 R1 = 0x811c9dc5u;
    constexpr quint32 PRIME = 0x01000193u;

    const QString s = author + QLatin1Char(' ') + body;

    quint32 h1 = R1;
    quint32 h2 = R1 ^ 0x9e3779b9u;
    for (const QChar ch : s) {
        const quint32 c = ch.unicode();
        h1 = (h1 ^ c) * PRIME;
        h2 = (h2 ^ (c + 0x9eu)) * PRIME;
    }
    return QStringLiteral("%1%2")
        .arg(h1, 8, 16, QLatin1Char('0'))
        .arg(h2, 8, 16, QLatin1Char('0'));
}

QJsonObject decodeToJson(const QString& raw)
{
    QJsonObject o;

    if (raw.size() > kMaxBody) {
        o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
        o.insert(QStringLiteral("text"), QStringLiteral("[oversized message]"));
        o.insert(QStringLiteral("folded"), false);
        return o;
    }

    const Kind kind = classify(raw);
    o.insert(QStringLiteral("kind"), kindName(kind));
    o.insert(QStringLiteral("folded"), isFolded(kind));

    if (kind == Kind::Text) {
        o.insert(QStringLiteral("text"), raw);
        return o;
    }

    const int colon = raw.indexOf(QLatin1Char(':'));
    const QString payload = colon < 0 ? QString() : raw.mid(colon + 1);
    const QString header = headerOf(payload);
    const QStringList fields = header.split(QLatin1Char(':'));

    // Guard the field count before indexing, so a hostile body of 100k colons
    // costs nothing.
    if (fields.size() > kMaxHeaderFields && kind != Kind::Reply
        && kind != Kind::ContactCard) {
        o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
        o.insert(QStringLiteral("text"), QStringLiteral("[unreadable message]"));
        return o;
    }

    switch (kind) {
    case Kind::HostedMedia: {
        // cid:key:mime:w:h[:cap] — exactly 5 or 6 fields, per media.ts:65-92.
        // Anything else is refused rather than partially believed.
        if (fields.size() < 5 || fields.size() > 6) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QStringLiteral("[unreadable media]"));
            break;
        }
        const int mw = fields.value(3).toInt();
        const int mh = fields.value(4).toInt();
        if (mw < 1 || mw > 100000 || mh < 1 || mh > 100000) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QStringLiteral("[unreadable media]"));
            break;
        }
        o.insert(QStringLiteral("padded"), raw.startsWith(QLatin1String("store2:")));
        // The 6th field is the fetch CAPABILITY, not a caption. There is no
        // caption field in this grammar at all (docs/CONTENT-MARKERS.md §1) —
        // treating the cap as one printed a hex blob as the message body.
        o.insert(QStringLiteral("cap"), fields.value(5));
        o.insert(QStringLiteral("cid"), fields.value(0));
        o.insert(QStringLiteral("mime"), fields.value(2));
        o.insert(QStringLiteral("width"), mw);
        o.insert(QStringLiteral("height"), mh);
        // The decryption key is deliberately NOT surfaced to QML.
        const QString hmime = fields.value(2);
        o.insert(QStringLiteral("text"),
                 hmime.startsWith(QLatin1String("video"))
                     ? QStringLiteral("Video")
                     : (hmime == QLatin1String("image/gif")
                            ? QStringLiteral("GIF")
                            : (hmime.startsWith(QLatin1String("image"))
                                   ? QStringLiteral("📷 Photo")
                                   : QStringLiteral("Media"))));
        break;
    }
    case Kind::InlinePhoto: {
        // mime:w:h␟<base64 | absPath>
        o.insert(QStringLiteral("mime"), fields.value(0));
        o.insert(QStringLiteral("width"), fields.value(1).toInt());
        o.insert(QStringLiteral("height"), fields.value(2).toInt());
        const QString data = afterUS(payload);
        o.insert(QStringLiteral("hasData"), !data.isEmpty());
        // NO data: URI here. The Basecamp QML sandbox blocks them, so an Image
        // bound to one renders nothing — silently, which is exactly how this
        // presented: photos that arrived and decoded fine and simply did not
        // appear. The backend materialises the bytes into the cache instead and
        // hands the view a file:// URL (see PeersUiBackend's `imageUri`).
        //
        // The mime is still gated to image/* there: it is echoed from the wire,
        // and a peer must not get to choose what kind of file we write and open.
        o.insert(QStringLiteral("text"), QStringLiteral("📷 Photo"));
        break;
    }
    case Kind::VoiceNote: {
        // mime:durMs:wf,csv␟<base64 | absPath>
        o.insert(QStringLiteral("mime"), fields.value(0));
        o.insert(QStringLiteral("durationMs"), fields.value(1).toInt());
        QJsonArray wave;
        const QStringList csv = fields.value(2).split(QLatin1Char(','), Qt::SkipEmptyParts);
        // Bound the waveform: it is peer-supplied and drives a QML repeater.
        for (int i = 0; i < csv.size() && i < 256; ++i)
            wave.append(csv.at(i).toInt());
        o.insert(QStringLiteral("waveform"), wave);
        o.insert(QStringLiteral("hasData"), !afterUS(payload).isEmpty());
        o.insert(QStringLiteral("text"), QStringLiteral("🎤 Voice message"));
        break;
    }
    case Kind::Location: {
        // lat,lng[,accM]
        const QStringList parts = header.split(QLatin1Char(','));
        bool okLat = false, okLng = false;
        const double lat = parts.value(0).toDouble(&okLat);
        const double lng = parts.value(1).toDouble(&okLng);
        // Reject out-of-range coordinates rather than handing QML a bad pin.
        if (!okLat || !okLng || lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QStringLiteral("[unreadable location]"));
            break;
        }
        o.insert(QStringLiteral("lat"), lat);
        o.insert(QStringLiteral("lng"), lng);
        o.insert(QStringLiteral("text"), QStringLiteral("📍 Location"));
        break;
    }
    case Kind::Reply: {
        // key:body — the body may itself contain colons, so split once only.
        const int sep = payload.indexOf(QLatin1Char(':'));
        const QString key = sep < 0 ? QString() : payload.left(sep);
        const QString body = sep < 0 ? payload : payload.mid(sep + 1);
        o.insert(QStringLiteral("replyToKey"), key.left(kMaxKeyLen));
        // The quoted body is itself a raw body and may carry its own marker.
        o.insert(QStringLiteral("text"), previewText(body));
        o.insert(QStringLiteral("innerKind"), kindName(classify(body)));
        break;
    }
    case Kind::ContactCard: {
        // "address" or "peers:addr?label=…"
        QString address = header;
        QString label;
        const int q = payload.indexOf(QLatin1Char('?'));
        if (payload.startsWith(QLatin1String("peers:")) && q > 0) {
            address = payload.mid(6, q - 6);
            const QString query = payload.mid(q + 1);
            for (const QString& kv : query.split(QLatin1Char('&'))) {
                if (kv.startsWith(QLatin1String("label=")))
                    label = clampLabel(QUrl::fromPercentEncoding(kv.mid(6).toUtf8()));
            }
        }
        // An address reaches a URL and a lookup, so accept hex only.
        static const QRegularExpression hexOnly(QStringLiteral("^[0-9a-fA-F]{1,128}$"));
        if (!hexOnly.match(address).hasMatch()) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QStringLiteral("[unreadable contact]"));
            break;
        }
        o.insert(QStringLiteral("address"), address);
        o.insert(QStringLiteral("label"), label);
        o.insert(QStringLiteral("text"),
                 label.isEmpty() ? QStringLiteral("Shared a contact")
                                 : QStringLiteral("Contact: %1").arg(label));
        break;
    }
    case Kind::Reaction: {
        // <+|-><emoji>:<key> — split on the LAST colon, not the first. Android
        // does this deliberately (reactions.ts:53-67): an emoji contains no
        // colon and the key is trailing hex, so lastIndexOf is unambiguous while
        // a first-colon split breaks. Also reject lastIndexOf(':') < 2 and an op
        // that is not + or -, exactly as Android does.
        const int sep = payload.lastIndexOf(QLatin1Char(':'));
        const QChar op = payload.isEmpty() ? QChar() : payload.at(0);
        if (sep < 2 || (op != QLatin1Char('+') && op != QLatin1Char('-'))) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QString());
            break;
        }
        const QString emoji = payload.mid(1, sep - 1);
        const QString key = payload.mid(sep + 1);
        if (emoji.isEmpty() || key.isEmpty()) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QString());
            break;
        }
        o.insert(QStringLiteral("add"), op == QLatin1Char('+'));
        o.insert(QStringLiteral("emoji"), emoji.left(16));
        o.insert(QStringLiteral("targetKey"), key.left(kMaxKeyLen));
        o.insert(QStringLiteral("text"), QString());
        break;
    }
    case Kind::Pin: {
        // <+|->key
        if (payload.isEmpty()) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QString());
            break;
        }
        o.insert(QStringLiteral("add"), payload.at(0) == QLatin1Char('+'));
        o.insert(QStringLiteral("targetKey"), payload.mid(1).left(kMaxKeyLen));
        o.insert(QStringLiteral("text"), QString());
        break;
    }
    case Kind::Avatar: {
        o.insert(QStringLiteral("clear"), payload == QLatin1String("clear"));
        o.insert(QStringLiteral("ref"), payload.left(kMaxLabelLen));
        o.insert(QStringLiteral("text"), QString());
        break;
    }
    case Kind::GroupConfig: {
        o.insert(QStringLiteral("storageOn"), header.endsWith(QLatin1String("on")));
        o.insert(QStringLiteral("text"), QString());
        break;
    }
    case Kind::Leave:
    case Kind::ReAdd: {
        o.insert(QStringLiteral("text"), QString());
        break;
    }
    case Kind::Unknown:
    default:
        // Degrade gracefully: never render a raw marker string. Android will
        // grow markers this build does not know, and a user must not see wire
        // text because of it.
        o.insert(QStringLiteral("text"), QStringLiteral("[unsupported message]"));
        break;
    }

    return o;
}

// ── encode ──────────────────────────────────────────────────────────────────

QString encodeReply(const QString& targetKey, const QString& body)
{
    // A key with a colon in it would make the receiver's single split ambiguous.
    // messageKey() only ever emits 16 hex chars, so this is a guard against a
    // caller passing something else, not an expected case.
    QString key = targetKey;
    key.remove(QLatin1Char(':'));
    return QStringLiteral("reply1:%1:%2").arg(key.left(kMaxKeyLen), body);
}

QString encodeReaction(bool add, const QString& emoji, const QString& targetKey)
{
    QString e = emoji;
    e.remove(QLatin1Char(':'));   // the payload is emoji:key — keep it splittable
    QString key = targetKey;
    key.remove(QLatin1Char(':'));
    return QStringLiteral("react1:%1%2:%3")
        .arg(add ? QStringLiteral("+") : QStringLiteral("-"), e.left(16), key.left(kMaxKeyLen));
}

QString encodePin(bool add, const QString& targetKey)
{
    QString key = targetKey;
    key.remove(QLatin1Char(':'));
    return QStringLiteral("pin1:%1%2")
        .arg(add ? QStringLiteral("+") : QStringLiteral("-"), key.left(kMaxKeyLen));
}

QString encodeContactCard(const QString& address, const QString& label)
{
    if (label.isEmpty())
        return QStringLiteral("addr1:%1").arg(address);
    return QStringLiteral("addr1:peers:%1?label=%2")
        .arg(address, QString::fromUtf8(QUrl::toPercentEncoding(clampLabel(label))));
}

int maxInlineBytes() { return kMaxInlineBytes; }

QString encodeHostedMedia(const QString& cid, const QString& keyB64, const QString& mime,
                          int width, int height, const QString& cap)
{
    // Field order is cid:key:mime:w:h[:cap] and none of those may contain a
    // colon, which is what makes a plain split unambiguous on the far side.
    const QString head = QStringLiteral("store2:%1:%2:%3:%4:%5")
                             .arg(cid, keyB64, mime)
                             .arg(width)
                             .arg(height);
    return cap.isEmpty() ? head : head + QLatin1Char(':') + cap;
}

QString encodeInlinePhoto(const QString& mime, int width, int height, const QByteArray& bytes)
{
    return QStringLiteral("img1:%1:%2:%3%4%5")
        .arg(mime.isEmpty() ? QStringLiteral("image/png") : mime)
        .arg(width)
        .arg(height)
        .arg(kUS)
        .arg(QString::fromLatin1(bytes.toBase64()));
}

QString encodeVoiceNote(const QString& mime, int durationMs, const QList<int>& waveform,
                        const QByteArray& bytes)
{
    QStringList wf;
    // Bound the waveform on the way out too — it drives a repeater on the peer.
    for (int i = 0; i < waveform.size() && i < 256; ++i)
        wf << QString::number(waveform.at(i));
    return QStringLiteral("voc1:%1:%2:%3%4%5")
        .arg(mime.isEmpty() ? QStringLiteral("audio/mp4") : mime)
        .arg(durationMs)
        .arg(wf.join(QLatin1Char(',')), QString(kUS))
        .arg(QString::fromLatin1(bytes.toBase64()));
}

bool imageSize(const QByteArray& b, int* width, int* height)
{
    if (!width || !height)
        return false;

    auto be32 = [&](int i) {
        return (static_cast<quint32>(static_cast<quint8>(b[i])) << 24)
            | (static_cast<quint32>(static_cast<quint8>(b[i + 1])) << 16)
            | (static_cast<quint32>(static_cast<quint8>(b[i + 2])) << 8)
            | static_cast<quint32>(static_cast<quint8>(b[i + 3]));
    };

    // PNG: 8-byte signature, then an IHDR chunk whose width/height are the two
    // big-endian u32s at offsets 16 and 20.
    static const char kPng[] = "\x89PNG\r\n\x1a\n";
    if (b.size() >= 24 && b.startsWith(QByteArray(kPng, 8))) {
        *width = static_cast<int>(be32(16));
        *height = static_cast<int>(be32(20));
        return *width > 0 && *height > 0;
    }

    // JPEG: walk the marker segments to a Start Of Frame, which carries the
    // dimensions. Every read is bounds-checked — this parses attacker-supplied
    // bytes.
    if (b.size() >= 4 && static_cast<quint8>(b[0]) == 0xFF && static_cast<quint8>(b[1]) == 0xD8) {
        int i = 2;
        while (i + 9 < b.size()) {
            if (static_cast<quint8>(b[i]) != 0xFF) {
                ++i;
                continue;
            }
            const quint8 marker = static_cast<quint8>(b[i + 1]);
            // Standalone markers carry no length.
            if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
                i += 2;
                continue;
            }
            const int len = (static_cast<quint8>(b[i + 2]) << 8) | static_cast<quint8>(b[i + 3]);
            if (len < 2)
                return false;
            // SOF0..SOF15, excluding the non-frame markers DHT/JPG/DAC.
            if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8
                && marker != 0xCC) {
                if (i + 9 >= b.size())
                    return false;
                *height = (static_cast<quint8>(b[i + 5]) << 8) | static_cast<quint8>(b[i + 6]);
                *width = (static_cast<quint8>(b[i + 7]) << 8) | static_cast<quint8>(b[i + 8]);
                return *width > 0 && *height > 0;
            }
            i += 2 + len;
        }
    }
    return false;
}

QString previewText(const QString& raw)
{
    const Kind kind = classify(raw);
    if (kind == Kind::Text)
        return raw;
    const QJsonObject o = decodeToJson(raw);
    const QString t = o.value(QStringLiteral("text")).toString();
    return t;
}

} // namespace ContentMarkers
