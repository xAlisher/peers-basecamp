#include "StorageClient.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>

#include <openssl/evp.h>
#include <openssl/rand.h>

#include "MediaPadding.h"

namespace {

constexpr int kIvLen = 12;      // StorageModule.kt:39
constexpr int kTagLen = 16;     // TAG_BITS = 128
constexpr int kKeyLen = 32;
// StorageRef.kt:28 — refuse anything larger up front rather than streaming it
// into memory.
constexpr qint64 kMaxCiphertextBytes = 100LL * 1024 * 1024;

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

bool StorageClient::uploadConfigured() const { return !storageToken().isEmpty(); }
QString StorageClient::baseUrl() const { return storageBase(); }

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

QString StorageClient::cacheFileFor(const QString& cid)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/media");
    QDir().mkpath(dir);
    const QByteArray h =
        QCryptographicHash::hash(cid.toUtf8(), QCryptographicHash::Sha256).toHex();
    return dir + QLatin1Char('/') + QString::fromLatin1(h);
}

// ── upload ──────────────────────────────────────────────────────────────────

void StorageClient::uploadEncrypted(const QByteArray& bytes, UploadCb cb)
{
    if (!uploadConfigured()) {
        cb(false, {},
           QStringLiteral("Hosted media is not configured on this install "
                          "(set PEERS_STORAGE_TOKEN). The file was not sent."));
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

    QNetworkRequest req{ QUrl(storageBase() + QStringLiteral("/data")) };
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/octet-stream"));
    req.setRawHeader("Authorization", "Bearer " + storageToken().toUtf8());

    QNetworkReply* reply = m_net->post(req, blob);
    const QString keyB64 = QString::fromLatin1(key.toBase64());

    connect(reply, &QNetworkReply::finished, this, [reply, cb, keyB64]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            cb(false, {},
               QStringLiteral("Upload failed: %1").arg(reply->errorString()));
            return;
        }
        // Response body is "<cid>:<cap>", split on the FIRST colon; no colon
        // means no cap (StorageModule.kt:138-144).
        const QString body = QString::fromUtf8(reply->readAll()).trimmed();
        const int colon = body.indexOf(QLatin1Char(':'));
        Uploaded u;
        u.cid = colon < 0 ? body : body.left(colon);
        u.cap = colon < 0 ? QString() : body.mid(colon + 1);
        u.keyB64 = keyB64;

        if (!validCid(u.cid)) {
            cb(false, {}, QStringLiteral("The storage node returned an unusable id."));
            return;
        }
        cb(true, u, QString());
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

    const QString cachePath = cacheFileFor(cid);
    {
        QFile cached(cachePath);
        // A non-empty cache file short-circuits the whole fetch.
        if (cached.exists() && cached.size() > 0) {
            cb(true, cachePath, QString());
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
    if (!storageToken().isEmpty() && cap.isEmpty())
        req.setRawHeader("Authorization", "Bearer " + storageToken().toUtf8());

    QNetworkReply* reply = m_net->get(req);
    const QByteArray key = QByteArray::fromBase64(keyB64.toLatin1());

    connect(reply, &QNetworkReply::finished, this, [reply, cb, key, cachePath]() {
        reply->deleteLater();

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

        const QByteArray blob = reply->readAll();
        if (blob.size() > kMaxCiphertextBytes) {
            cb(false, QString(), QStringLiteral("That media is too large."));
            return;
        }
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
