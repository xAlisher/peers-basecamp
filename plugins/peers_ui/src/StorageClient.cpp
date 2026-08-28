#include "StorageClient.h"

#include "MediaTools.h"
#include "StorageBounds.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QThread>
#include <QUrl>
#include <QUrlQuery>

#include <limits>
#include <memory>
#include <set>

#include <openssl/evp.h>
#include <openssl/rand.h>

#include "MediaPadding.h"

namespace {

constexpr int kIvLen = 12;      // StorageModule.kt:39
constexpr int kTagLen = 16;     // TAG_BITS = 128
constexpr int kKeyLen = 32;
// StorageRef.kt:28 — refuse anything larger up front rather than streaming it
// into memory.
constexpr qint64 kMaxCiphertextBytes = StorageBounds::maxGeneralCiphertextBytes;
constexpr qint64 kMaxSmallResponseBytes = 4096;
constexpr int kMaxProofDifficulty = 24;
constexpr qint64 kMaxClockHorizonSeconds = 2 * 60;

QString envOr(const char* name, const QString& fallback)
{
    const QByteArray v = qgetenv(name);
    return v.isEmpty() ? fallback : QString::fromUtf8(v);
}

QString storageBase()
{
    return envOr("PEERS_STORAGE_BASE",
                 QStringLiteral("https://msg.logos.live/s/api/storage/v1"));
}

QString storageToken() { return envOr("PEERS_STORAGE_TOKEN", QString()); }

void skipJsonWhitespace(const QByteArray& body, qsizetype* offset)
{
    while (*offset < body.size()
           && (body[*offset] == ' ' || body[*offset] == '\t' || body[*offset] == '\r'
               || body[*offset] == '\n'))
        ++*offset;
}

bool takeJsonString(const QByteArray& body, qsizetype* offset, QByteArray* encoded)
{
    if (*offset >= body.size() || body[*offset] != '"')
        return false;
    const qsizetype start = (*offset)++;
    while (*offset < body.size()) {
        const char value = body[(*offset)++];
        if (value == '\\') {
            if (*offset >= body.size())
                return false;
            ++*offset;
        } else if (value == '"') {
            if (encoded)
                *encoded = body.mid(start, *offset - start);
            return true;
        }
    }
    return false;
}

bool skipJsonValue(const QByteArray& body, qsizetype* offset)
{
    skipJsonWhitespace(body, offset);
    if (*offset >= body.size())
        return false;
    if (body[*offset] == '"')
        return takeJsonString(body, offset, nullptr);
    if (body[*offset] == '{' || body[*offset] == '[') {
        QByteArray closers;
        closers.append(body[(*offset)++] == '{' ? '}' : ']');
        while (*offset < body.size() && !closers.isEmpty()) {
            if (body[*offset] == '"') {
                if (!takeJsonString(body, offset, nullptr))
                    return false;
                continue;
            }
            const char value = body[(*offset)++];
            if (value == '{')
                closers.append('}');
            else if (value == '[')
                closers.append(']');
            else if (value == closers.back())
                closers.chop(1);
        }
        return closers.isEmpty();
    }
    const qsizetype start = *offset;
    while (*offset < body.size() && body[*offset] != ',' && body[*offset] != '}')
        ++*offset;
    return *offset > start;
}

bool uniqueTopLevelObjectKeys(const QByteArray& body, QHash<QString, QByteArray>* values)
{
    if (!values)
        return false;
    values->clear();
    qsizetype offset = 0;
    skipJsonWhitespace(body, &offset);
    if (offset >= body.size() || body[offset++] != '{')
        return false;
    std::set<QString> keys;
    skipJsonWhitespace(body, &offset);
    if (offset < body.size() && body[offset] == '}') {
        ++offset;
    } else {
        while (offset < body.size()) {
            QByteArray encodedKey;
            if (!takeJsonString(body, &offset, &encodedKey))
                return false;
            QJsonParseError error;
            const QJsonDocument keyDocument =
                QJsonDocument::fromJson(QByteArray("[") + encodedKey + ']', &error);
            if (error.error != QJsonParseError::NoError || !keyDocument.isArray()
                || keyDocument.array().size() != 1 || !keyDocument.array().first().isString())
                return false;
            const QString key = keyDocument.array().first().toString();
            if (!keys.insert(key).second)
                return false;
            skipJsonWhitespace(body, &offset);
            if (offset >= body.size() || body[offset++] != ':')
                return false;
            skipJsonWhitespace(body, &offset);
            const qsizetype valueStart = offset;
            if (!skipJsonValue(body, &offset))
                return false;
            qsizetype valueEnd = offset;
            while (valueEnd > valueStart
                   && (body[valueEnd - 1] == ' ' || body[valueEnd - 1] == '\t'
                       || body[valueEnd - 1] == '\r' || body[valueEnd - 1] == '\n'))
                --valueEnd;
            values->insert(key, body.mid(valueStart, valueEnd - valueStart));
            skipJsonWhitespace(body, &offset);
            if (offset < body.size() && body[offset] == ',') {
                ++offset;
                skipJsonWhitespace(body, &offset);
                continue;
            }
            if (offset >= body.size() || body[offset++] != '}')
                return false;
            break;
        }
    }
    skipJsonWhitespace(body, &offset);
    return offset == body.size();
}

bool exactIntegerToken(const QByteArray& token, qint64* out)
{
    static const QRegularExpression expression(QStringLiteral("^-?(?:0|[1-9][0-9]*)$"));
    const QString text = QString::fromUtf8(token);
    if (!expression.match(text).hasMatch())
        return false;
    bool ok = false;
    const qint64 value = text.toLongLong(&ok, 10);
    if (ok)
        *out = value;
    return ok;
}

bool strictObject(const QByteArray& body, const QStringList& expected, QJsonObject* out,
                  QHash<QString, QByteArray>* tokens)
{
    if (!uniqueTopLevelObjectKeys(body, tokens))
        return false;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(body, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return false;
    const QJsonObject object = document.object();
    QStringList actual = object.keys();
    QStringList wanted = expected;
    actual.sort();
    wanted.sort();
    if (actual != wanted)
        return false;
    *out = object;
    return true;
}

bool validOpaque64(const QString& value)
{
    static const QRegularExpression re(QStringLiteral("^[0-9a-f]{64}$"));
    return re.match(value).hasMatch();
}

bool validUploadCapability(const QString& value)
{
    static const QRegularExpression re(QStringLiteral("^[0-9a-f]{32}$"));
    return re.match(value).hasMatch();
}

int leadingZeroBits(const QByteArray& digest)
{
    int bits = 0;
    for (unsigned char value : digest) {
        if (value == 0) {
            bits += 8;
            continue;
        }
        for (unsigned char mask = 0x80; (value & mask) == 0; mask >>= 1)
            ++bits;
        break;
    }
    return bits;
}

qint64 solveProof(const QString& challenge, qint64 bytes, int difficulty, qint64 budgetMillis)
{
    const QByteArray prefix = challenge.toUtf8() + ':' + QByteArray::number(bytes) + ':';
    QElapsedTimer elapsed;
    elapsed.start();
    for (qint64 nonce = 0;; ++nonce) {
        const QByteArray digest = QCryptographicHash::hash(
            prefix + QByteArray::number(nonce), QCryptographicHash::Sha256);
        if (leadingZeroBits(digest) >= difficulty)
            return nonce;
        if ((nonce & 0xfff) == 0 && elapsed.hasExpired(budgetMillis))
            return -1;
        if (nonce == std::numeric_limits<qint64>::max())
            return -1;
    }
}

} // namespace

StorageClient::StorageClient(QObject* parent)
    : QObject(parent), m_net(new QNetworkAccessManager(this))
{
    // A 3xx must never be followed: it is how a hostile or misconfigured node
    // would redirect a fetch somewhere else. Android sets
    // instanceFollowRedirects = false for the same reason.
    m_net->setRedirectPolicy(QNetworkRequest::ManualRedirectPolicy);
}

StorageClient::~StorageClient() = default;

QString StorageClient::baseUrl() const { return storageBase(); }

qint64 StorageClient::maxHostedPlaintextBytes()
{
    static const qint64 maximum = [] {
        qint64 low = 0;
        qint64 high = kMaxCiphertextBytes;
        while (low < high) {
            const qint64 middle = low + (high - low + 1) / 2;
            const qint64 ciphertext =
                MediaPadding::padmeBucket(MediaPadding::headerBytes() + middle) + kIvLen + kTagLen;
            if (ciphertext <= kMaxCiphertextBytes)
                low = middle;
            else
                high = middle - 1;
        }
        return low;
    }();
    return maximum;
}

void StorageClient::postBounded(QNetworkRequest request, const QByteArray& body, PostCb cb)
{
    QNetworkReply* reply = m_net->post(request, body);
    const auto received = std::make_shared<QByteArray>();
    const auto oversized = std::make_shared<bool>(false);

    connect(reply, &QIODevice::readyRead, this, [reply, received, oversized] {
        received->append(reply->read(kMaxSmallResponseBytes + 1 - received->size()));
        if (received->size() > kMaxSmallResponseBytes || reply->bytesAvailable() > 0) {
            *oversized = true;
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [reply, received, oversized, cb] {
        received->append(reply->read(kMaxSmallResponseBytes + 1 - received->size()));
        reply->deleteLater();
        if (*oversized || received->size() > kMaxSmallResponseBytes) {
            cb(false, {}, QStringLiteral("The storage response was too large."));
            return;
        }
        const int status =
            reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status >= 300 && status < 400) {
            cb(false, {}, QStringLiteral("The storage node tried to redirect the request."));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            cb(false, {}, QStringLiteral("The storage request failed."));
            return;
        }
        cb(true, *received, QString());
    });
}

// ── validation (StorageRef.kt:38-53) ────────────────────────────────────────

bool StorageClient::validCid(const QString& cid)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9_~-]{1,128}$"));
    return re.match(cid).hasMatch();
}

bool StorageClient::validCap(const QString& cap)
{
    if (cap.isEmpty())
        return true;   // legacy capless markers
    static const QRegularExpression re(QStringLiteral("^[A-Fa-f0-9]{1,256}$"));
    return re.match(cap).hasMatch();
}

bool StorageClient::validMime(const QString& mime)
{
    static const QRegularExpression re(QStringLiteral(
        "^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$"));
    return re.match(mime).hasMatch();
}

bool StorageClient::validKeyB64(const QString& keyB64)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9+/=]{4,64}$"));
    if (!re.match(keyB64).hasMatch())
        return false;
    // The JS regex only bounds the length; the key must actually be 32 bytes.
    return QByteArray::fromBase64(keyB64.toLatin1()).size() == kKeyLen;
}

QString StorageClient::cacheSuffixForMime(const QString& mime)
{
    const QString lower = mime.toLower();
    if (lower == QLatin1String("image/jpeg") || lower == QLatin1String("image/jpg"))
        return QStringLiteral(".jpg");
    if (lower == QLatin1String("image/png"))
        return QStringLiteral(".png");
    if (lower == QLatin1String("image/gif"))
        return QStringLiteral(".gif");
    if (lower == QLatin1String("image/webp"))
        return QStringLiteral(".webp");
    if (lower == QLatin1String("image/bmp"))
        return QStringLiteral(".bmp");
    if (lower == QLatin1String("audio/mp4"))
        return QStringLiteral(".m4a");
    if (lower == QLatin1String("audio/mpeg"))
        return QStringLiteral(".mp3");
    if (lower == QLatin1String("audio/ogg"))
        return QStringLiteral(".ogg");
    if (lower == QLatin1String("audio/wav") || lower == QLatin1String("audio/x-wav"))
        return QStringLiteral(".wav");
    return QStringLiteral(".bin");
}

QString StorageClient::cacheFileFor(const QString& cid, const QString& mime)
{
    const QString dir = MediaTools::mediaCacheDir();
    QDir().mkpath(dir);
    const QByteArray h =
        QCryptographicHash::hash(cid.toUtf8(), QCryptographicHash::Sha256).toHex();
    return dir + QLatin1Char('/') + QString::fromLatin1(h) + cacheSuffixForMime(mime);
}

// ── upload ──────────────────────────────────────────────────────────────────

void StorageClient::uploadEncrypted(const QByteArray& bytes, UploadCb cb)
{
    if (bytes.size() > maxHostedPlaintextBytes()) {
        cb(false, {}, QStringLiteral("That media is too large."));
        return;
    }
    // 1. Pad first, so the ciphertext length reveals a bucket, not a fingerprint.
    const QByteArray plain = MediaPadding::pad(bytes);

    // 2. Fresh key and IV per blob. Reusing either across blobs under GCM is
    //    catastrophic, so they are generated here and never cached.
    QByteArray key(kKeyLen, 0);
    QByteArray iv(kIvLen, 0);
    if (RAND_bytes(reinterpret_cast<unsigned char*>(key.data()), kKeyLen) != 1
        || RAND_bytes(reinterpret_cast<unsigned char*>(iv.data()), kIvLen) != 1) {
        cb(false, {}, QStringLiteral("Could not generate encryption material."));
        return;
    }

    QByteArray ct(plain.size(), 0);
    QByteArray tag(kTagLen, 0);
    int outLen = 0, finalLen = 0;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    bool ok = ctx
        && EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1
        && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, kIvLen, nullptr) == 1
        && EVP_EncryptInit_ex(ctx, nullptr, nullptr,
                              reinterpret_cast<const unsigned char*>(key.constData()),
                              reinterpret_cast<const unsigned char*>(iv.constData()))
            == 1
        && EVP_EncryptUpdate(ctx, reinterpret_cast<unsigned char*>(ct.data()), &outLen,
                             reinterpret_cast<const unsigned char*>(plain.constData()),
                             plain.size())
            == 1
        && EVP_EncryptFinal_ex(ctx, reinterpret_cast<unsigned char*>(ct.data()) + outLen,
                               &finalLen)
            == 1
        && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, kTagLen, tag.data()) == 1;
    if (ctx)
        EVP_CIPHER_CTX_free(ctx);

    if (!ok) {
        cb(false, {}, QStringLiteral("Could not encrypt the file."));
        return;
    }
    ct.resize(outLen + finalLen);

    // 3. blob = iv || ct || tag  (Java appends the tag to the ciphertext)
    const QByteArray blob = iv + ct + tag;
    const QString keyB64 = QString::fromLatin1(key.toBase64());
    if (blob.isEmpty() || blob.size() > kMaxCiphertextBytes) {
        cb(false, {}, QStringLiteral("That media is too large."));
        return;
    }

    QNetworkRequest challengeRequest{
        QUrl(storageBase() + QStringLiteral("/data/upload-challenges"))
    };
    challengeRequest.setTransferTimeout(30000);
    postBounded(challengeRequest, {}, [this, blob, keyB64, cb](
                                          bool challengeOk, QByteArray challengeBody, QString error) {
        if (!challengeOk) {
            cb(false, {}, error);
            return;
        }
        QJsonObject challengeJson;
        QHash<QString, QByteArray> challengeTokens;
        if (!strictObject(challengeBody,
                          { QStringLiteral("challenge"), QStringLiteral("difficulty"),
                            QStringLiteral("expires_at") },
                          &challengeJson, &challengeTokens)) {
            cb(false, {}, QStringLiteral("The storage node returned an invalid challenge."));
            return;
        }
        const QString challenge = challengeJson.value(QStringLiteral("challenge")).toString();
        qint64 difficulty64 = 0;
        qint64 expiresAt = 0;
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        if (!validOpaque64(challenge)
            || !exactIntegerToken(challengeTokens.value(QStringLiteral("difficulty")), &difficulty64)
            || difficulty64 < 1 || difficulty64 > kMaxProofDifficulty
            || !exactIntegerToken(challengeTokens.value(QStringLiteral("expires_at")), &expiresAt)
            || expiresAt <= now || expiresAt > now + kMaxClockHorizonSeconds) {
            cb(false, {}, QStringLiteral("The storage node returned invalid challenge caveats."));
            return;
        }

        const auto nonce = std::make_shared<qint64>(-1);
        const qint64 proofBudgetMillis = (expiresAt - now) * 1000;
        QThread* worker = QThread::create([nonce, challenge, bytes = blob.size(),
                                           difficulty = static_cast<int>(difficulty64),
                                           proofBudgetMillis] {
            *nonce = solveProof(challenge, bytes, difficulty, proofBudgetMillis);
        });
        connect(worker, &QThread::finished, worker, &QObject::deleteLater);
        connect(worker, &QThread::finished, this,
                [this, blob, keyB64, cb, challenge, expiresAt, nonce] {
            if (*nonce < 0 || QDateTime::currentSecsSinceEpoch() >= expiresAt) {
                cb(false, {}, QStringLiteral("The upload challenge expired."));
                return;
            }
            QJsonObject proof;
            proof.insert(QStringLiteral("challenge"), challenge);
            proof.insert(QStringLiteral("bytes"), blob.size());
            proof.insert(QStringLiteral("nonce"), *nonce);
            QNetworkRequest grantRequest{
                QUrl(storageBase() + QStringLiteral("/data/upload-grants"))
            };
            grantRequest.setHeader(QNetworkRequest::ContentTypeHeader,
                                   QStringLiteral("application/json"));
            grantRequest.setTransferTimeout(30000);
            postBounded(grantRequest, QJsonDocument(proof).toJson(QJsonDocument::Compact),
                        [this, blob, keyB64, cb](bool grantOk, QByteArray grantBody,
                                                QString grantError) {
                if (!grantOk) {
                    cb(false, {}, grantError);
                    return;
                }
                QJsonObject grantJson;
                QHash<QString, QByteArray> grantTokens;
                if (!strictObject(grantBody,
                                  { QStringLiteral("grant"), QStringLiteral("max_bytes"),
                                    QStringLiteral("expires_at") },
                                  &grantJson, &grantTokens)) {
                    cb(false, {}, QStringLiteral("The storage node returned an invalid grant."));
                    return;
                }
                const QString grant = grantJson.value(QStringLiteral("grant")).toString();
                qint64 maxBytes = 0;
                qint64 grantExpiresAt = 0;
                const qint64 grantNow = QDateTime::currentSecsSinceEpoch();
                if (!validOpaque64(grant)
                    || !exactIntegerToken(grantTokens.value(QStringLiteral("max_bytes")), &maxBytes)
                    || maxBytes != blob.size()
                    || !exactIntegerToken(grantTokens.value(QStringLiteral("expires_at")),
                                          &grantExpiresAt)
                    || grantExpiresAt <= grantNow
                    || grantExpiresAt > grantNow + kMaxClockHorizonSeconds) {
                    cb(false, {}, QStringLiteral("The storage node returned invalid grant caveats."));
                    return;
                }

                QNetworkRequest uploadRequest{
                    QUrl(storageBase() + QStringLiteral("/data"))
                };
                uploadRequest.setHeader(QNetworkRequest::ContentTypeHeader,
                                        QStringLiteral("application/octet-stream"));
                uploadRequest.setRawHeader("X-Upload-Grant", grant.toUtf8());
                uploadRequest.setTransferTimeout(120000);
                postBounded(uploadRequest, blob,
                            [cb, keyB64](bool uploadOk, QByteArray uploadBody,
                                        QString uploadError) {
                    if (!uploadOk) {
                        cb(false, {}, uploadError);
                        return;
                    }
                    const QString body = QString::fromUtf8(uploadBody);
                    const int colon = body.indexOf(QLatin1Char(':'));
                    if (colon <= 0 || colon != body.lastIndexOf(QLatin1Char(':'))) {
                        cb(false, {}, QStringLiteral("The storage node returned an unusable id."));
                        return;
                    }
                    Uploaded uploaded;
                    uploaded.cid = body.left(colon);
                    uploaded.cap = body.mid(colon + 1);
                    uploaded.keyB64 = keyB64;
                    if (!validCid(uploaded.cid) || !validUploadCapability(uploaded.cap)) {
                        cb(false, {}, QStringLiteral("The storage node returned an unusable id."));
                        return;
                    }
                    cb(true, uploaded, QString());
                });
            });
        });
        worker->start();
    });
}

// ── download ────────────────────────────────────────────────────────────────

void StorageClient::downloadDecrypt(const QString& cid, const QString& keyB64, const QString& cap,
                                    const QString& mime, DownloadCb cb)
{
    // Re-validate everything, even though the marker parser already did. These
    // values reach a URL and a filesystem path, and defence in depth here is
    // what Android does too.
    if (!validCid(cid) || !validKeyB64(keyB64) || !validCap(cap) || !validMime(mime)) {
        cb(false, QString(), QStringLiteral("That media reference is malformed."));
        return;
    }

    const qint64 maxCiphertextBytes = StorageBounds::maxCiphertextBytesForMime(mime);

    const QString cachePath = cacheFileFor(cid, mime);
    {
        QFile cached(cachePath);
        // A non-empty cache file short-circuits the whole fetch.
        if (cached.exists() && StorageBounds::validCacheFileSize(cached.size(), mime)) {
            cb(true, cachePath, QString());
            return;
        }
        if (cached.exists() && cached.size() > 0) {
            cb(false, QString(), QStringLiteral("That media is too large."));
            return;
        }
    }

    if (storageToken().isEmpty() && cap.isEmpty()) {
        cb(false, QString(),
           QStringLiteral("That hosted-media reference has no download capability, "
                          "and this install has no legacy storage credential."));
        return;
    }

    QUrl url(storageBase() + QStringLiteral("/data/")
             + QString::fromUtf8(QUrl::toPercentEncoding(cid)));
    if (!cap.isEmpty()) {
        QUrlQuery q;
        q.addQueryItem(QStringLiteral("cap"), cap);
        url.setQuery(q);
    }

    QNetworkRequest req{ url };
    req.setTransferTimeout(60000);
    if (!storageToken().isEmpty() && cap.isEmpty())
        req.setRawHeader("Authorization", "Bearer " + storageToken().toUtf8());

    QNetworkReply* reply = m_net->get(req);
    const QByteArray key = QByteArray::fromBase64(keyB64.toLatin1());
    const auto received = std::make_shared<QByteArray>();
    const auto oversized = std::make_shared<bool>(false);

    connect(reply, &QNetworkReply::metaDataChanged, this,
            [reply, oversized, maxCiphertextBytes] {
        bool ok = false;
        const qint64 declared =
            reply->header(QNetworkRequest::ContentLengthHeader).toLongLong(&ok);
        if (ok && declared > maxCiphertextBytes) {
            *oversized = true;
            reply->abort();
        }
    });
    connect(reply, &QIODevice::readyRead, this,
            [reply, received, oversized, maxCiphertextBytes] {
        const qint64 remaining = maxCiphertextBytes + 1 - received->size();
        if (remaining > 0)
            received->append(reply->read(remaining));
        if (received->size() > maxCiphertextBytes || reply->bytesAvailable() > 0) {
            *oversized = true;
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this,
            [reply, cb, key, cachePath, received, oversized, maxCiphertextBytes]() {
        const qint64 remaining = maxCiphertextBytes + 1 - received->size();
        if (remaining > 0)
            received->append(reply->read(remaining));
        reply->deleteLater();

        if (*oversized || received->size() > maxCiphertextBytes
            || reply->bytesAvailable() > 0) {
            cb(false, QString(), QStringLiteral("That media is too large."));
            return;
        }

        const int status =
            reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status >= 300 && status < 400) {
            cb(false, QString(), QStringLiteral("The storage node tried to redirect the fetch."));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            cb(false, QString(), QStringLiteral("Fetch failed: %1").arg(reply->errorString()));
            return;
        }

        // An HTML or JSON body is an error page, not a blob. Treating one as
        // ciphertext would produce a confusing decrypt failure instead of the
        // real reason.
        const QString ctype =
            reply->header(QNetworkRequest::ContentTypeHeader).toString().toLower();
        if (ctype.contains(QLatin1String("text/html"))
            || ctype.contains(QLatin1String("application/json"))) {
            cb(false, QString(), QStringLiteral("The storage node returned an error page."));
            return;
        }

        const QByteArray& blob = *received;
        if (blob.size() <= kIvLen + kTagLen) {
            cb(false, QString(), QStringLiteral("That media is truncated."));
            return;
        }

        const QByteArray iv = blob.left(kIvLen);
        const QByteArray tag = blob.right(kTagLen);
        const QByteArray body = blob.mid(kIvLen, blob.size() - kIvLen - kTagLen);

        QByteArray plain(body.size(), 0);
        int outLen = 0, finalLen = 0;
        EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
        bool ok = ctx
            && EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1
            && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, kIvLen, nullptr) == 1
            && EVP_DecryptInit_ex(ctx, nullptr, nullptr,
                                  reinterpret_cast<const unsigned char*>(key.constData()),
                                  reinterpret_cast<const unsigned char*>(iv.constData()))
                == 1
            && EVP_DecryptUpdate(ctx, reinterpret_cast<unsigned char*>(plain.data()), &outLen,
                                 reinterpret_cast<const unsigned char*>(body.constData()),
                                 body.size())
                == 1
            && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, kTagLen,
                                   const_cast<char*>(tag.constData()))
                == 1
            && EVP_DecryptFinal_ex(ctx, reinterpret_cast<unsigned char*>(plain.data()) + outLen,
                                   &finalLen)
                == 1;
        if (ctx)
            EVP_CIPHER_CTX_free(ctx);

        if (!ok) {
            cb(false, QString(), QStringLiteral("That media could not be decrypted."));
            return;
        }
        plain.resize(outLen + finalLen);

        QByteArray unpadded;
        if (!MediaPadding::strip(plain, &unpadded)) {
            cb(false, QString(), QStringLiteral("That media is malformed."));
            return;
        }

        QFile out(cachePath);
        if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            cb(false, QString(), QStringLiteral("Could not write the media cache."));
            return;
        }
        out.write(unpadded);
        out.close();
        cb(true, cachePath, QString());
    });
}
