#include "ContentMarkers.h"

#include <QJsonArray>
#include <QRegularExpression>
#include <QStringList>
#include <QUrl>

namespace ContentMarkers {
namespace {

// The unit separator Peers uses between a marker's header and its payload.
constexpr QChar kUS = QChar(0x001F);

// Hard bounds. Peer-controlled input never drives an allocation, and a body
// that exceeds these is rejected rather than truncated into something that
// looks valid.
constexpr int kMaxBody = 1 << 20;      // 1 MiB — far above any real text body
constexpr int kMaxHeaderFields = 8;
constexpr int kMaxLabelLen = 256;
constexpr int kMaxKeyLen = 64;

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
    const int us = payload.indexOf(kUS);
    return us < 0 ? payload : payload.left(us);
}

QString afterUS(const QString& payload)
{
    const int us = payload.indexOf(kUS);
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
        // cid:key:mime:w:h[:cap]
        o.insert(QStringLiteral("cid"), fields.value(0));
        o.insert(QStringLiteral("mime"), fields.value(2));
        o.insert(QStringLiteral("width"), fields.value(3).toInt());
        o.insert(QStringLiteral("height"), fields.value(4).toInt());
        const QString cap = clampLabel(fields.value(5));
        o.insert(QStringLiteral("caption"), cap);
        // The decryption key is deliberately NOT surfaced to QML.
        const QString mime = fields.value(2);
        o.insert(QStringLiteral("text"),
                 cap.isEmpty() ? (mime.startsWith(QLatin1String("video")) ? QStringLiteral("Video")
                                                                         : QStringLiteral("Media"))
                               : cap);
        break;
    }
    case Kind::InlinePhoto: {
        // mime:w:h␟<base64 | absPath>
        o.insert(QStringLiteral("mime"), fields.value(0));
        o.insert(QStringLiteral("width"), fields.value(1).toInt());
        o.insert(QStringLiteral("height"), fields.value(2).toInt());
        o.insert(QStringLiteral("hasData"), !afterUS(payload).isEmpty());
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
        // <+|->emoji:key
        if (header.isEmpty()) {
            o.insert(QStringLiteral("kind"), kindName(Kind::Unknown));
            o.insert(QStringLiteral("text"), QString());
            break;
        }
        const QChar op = payload.at(0);
        const int sep = payload.indexOf(QLatin1Char(':'), 1);
        o.insert(QStringLiteral("add"), op == QLatin1Char('+'));
        o.insert(QStringLiteral("emoji"), sep < 0 ? QString() : payload.mid(1, sep - 1).left(16));
        o.insert(QStringLiteral("targetKey"),
                 sep < 0 ? QString() : payload.mid(sep + 1).left(kMaxKeyLen));
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
