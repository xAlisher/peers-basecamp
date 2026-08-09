#include "BackupReader.h"

#include <QJsonArray>
#include <QJsonDocument>

#include <openssl/evp.h>

namespace BackupReader {
namespace {

// The envelope's own identity check. Android uses optString, so a MISSING
// format yields "" and fails the same check — we match that, and additionally
// refuse an unexpected kdf (see below).
constexpr const char* kFormat = "peers-backup-enc";
constexpr const char* kKdf = "pbkdf2-hmac-sha256";

// Android bounds iters to 1..10_000_000. Honour the same window: a file
// claiming a billion iterations is a denial-of-service, not a backup.
constexpr int kMinIters = 1;
constexpr int kMaxIters = 10000000;

// A backup is a text JSON file. Anything vastly larger than a real one is
// hostile input, and we refuse before allocating.
constexpr int kMaxEnvelopeBytes = 64 * 1024 * 1024;

// AES-256-GCM, as written by BackupCrypto.kt.
constexpr int kTagBytes = 16;
constexpr int kKeyBytes = 32;

Result failure(const QString& message)
{
    Result r;
    r.ok = false;
    r.error = message;
    return r;
}

} // namespace

QByteArray deriveKey(const QString& passphrase, const QByteArray& salt, int iterations, int keyLen)
{
    const QByteArray pass = passphrase.toUtf8();
    QByteArray out(keyLen, 0);
    // Android hands a char[] to PBEKeySpec and lets the JCE provider encode it;
    // on Android that provider is UTF-8, so UTF-8 is the matching choice here.
    // docs/BACKUP-FORMAT.md §8.1 flags this as the one place a non-ASCII
    // passphrase could in principle diverge.
    if (PKCS5_PBKDF2_HMAC(pass.constData(), pass.size(),
                          reinterpret_cast<const unsigned char*>(salt.constData()), salt.size(),
                          iterations, EVP_sha256(), keyLen,
                          reinterpret_cast<unsigned char*>(out.data()))
        != 1) {
        return {};
    }
    return out;
}

Result open(const QByteArray& envelope, const QString& passphrase)
{
    if (envelope.isEmpty())
        return failure(QStringLiteral("That file is empty."));
    if (envelope.size() > kMaxEnvelopeBytes)
        return failure(QStringLiteral("That file is too large to be a Peers backup."));

    QJsonParseError perr{};
    const QJsonDocument doc = QJsonDocument::fromJson(envelope, &perr);
    if (doc.isNull() || !doc.isObject())
        return failure(QStringLiteral("That is not a Peers backup (it is not JSON)."));

    const QJsonObject env = doc.object();
    const QString format = env.value(QStringLiteral("format")).toString();

    // A legacy pre-#361 export is PLAINTEXT JSON with format "logos-chat-backup"
    // and no identity. Say which it is instead of "not a backup".
    if (format == QLatin1String("logos-chat-backup"))
        return failure(QStringLiteral(
            "That is an older unencrypted backup (logos-chat-backup). Reading those is not "
            "supported yet."));

    if (format != QLatin1String(kFormat))
        return failure(QStringLiteral("That is not a Peers encrypted backup."));

    // Android never reads `kdf` and would decrypt a file claiming any KDF. We
    // refuse instead: honouring a field we then ignore is how a downgrade slips
    // through.
    const QString kdf = env.value(QStringLiteral("kdf")).toString();
    if (!kdf.isEmpty() && kdf != QLatin1String(kKdf))
        return failure(QStringLiteral("This backup uses an unsupported key derivation (%1).").arg(kdf));

    if (!env.contains(QStringLiteral("iters")))
        return failure(QStringLiteral("This backup is missing its iteration count."));
    const int iters = env.value(QStringLiteral("iters")).toInt();
    if (iters < kMinIters || iters > kMaxIters)
        return failure(QStringLiteral("This backup declares an unusable iteration count."));

    const QByteArray salt =
        QByteArray::fromBase64(env.value(QStringLiteral("salt")).toString().toLatin1());
    const QByteArray iv =
        QByteArray::fromBase64(env.value(QStringLiteral("iv")).toString().toLatin1());
    const QByteArray ct =
        QByteArray::fromBase64(env.value(QStringLiteral("ct")).toString().toLatin1());

    if (salt.isEmpty() || iv.isEmpty() || ct.size() <= kTagBytes)
        return failure(QStringLiteral("This backup is malformed."));

    const QByteArray key = deriveKey(passphrase, salt, iters, kKeyBytes);
    if (key.size() != kKeyBytes)
        return failure(QStringLiteral("Could not derive a key from that passphrase."));

    // Java's Cipher APPENDS the GCM tag to the ciphertext; OpenSSL wants it
    // separately.
    const QByteArray body = ct.left(ct.size() - kTagBytes);
    const QByteArray tag = ct.right(kTagBytes);

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx)
        return failure(QStringLiteral("Could not start decryption."));

    QByteArray plain(body.size(), 0);
    int outLen = 0;
    bool ok = EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1
        && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, iv.size(), nullptr) == 1
        && EVP_DecryptInit_ex(ctx, nullptr, nullptr,
                              reinterpret_cast<const unsigned char*>(key.constData()),
                              reinterpret_cast<const unsigned char*>(iv.constData()))
            == 1
        && EVP_DecryptUpdate(ctx, reinterpret_cast<unsigned char*>(plain.data()), &outLen,
                             reinterpret_cast<const unsigned char*>(body.constData()), body.size())
            == 1;

    int finalLen = 0;
    if (ok) {
        ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, kTagBytes,
                                 const_cast<char*>(tag.constData()))
            == 1;
    }
    if (ok) {
        // This is the authentication check. It fails for a wrong passphrase, so
        // nothing below ever sees unauthenticated plaintext.
        ok = EVP_DecryptFinal_ex(ctx, reinterpret_cast<unsigned char*>(plain.data()) + outLen,
                                 &finalLen)
            == 1;
    }
    EVP_CIPHER_CTX_free(ctx);

    if (!ok)
        return failure(QStringLiteral("Wrong passphrase, or the backup is damaged."));

    plain.resize(outLen + finalLen);

    const QJsonDocument pdoc = QJsonDocument::fromJson(plain);
    // Wipe the plaintext buffer once parsed — it held the identity seed.
    plain.fill('\0');

    if (pdoc.isNull() || !pdoc.isObject())
        return failure(QStringLiteral("The backup decrypted but its contents are not readable."));

    Result r;
    r.ok = true;
    r.payload = pdoc.object();

    const QString identity = r.payload.value(QStringLiteral("identity")).toString();
    if (!identity.isEmpty()) {
        r.hasIdentity = true;
        r.identityBytes = QByteArray::fromBase64(identity.toLatin1()).size();
    }
    // The seed must not travel further than this. Nothing downstream can use it
    // (ADR 0004) and the payload crosses to QML as JSON.
    r.payload.remove(QStringLiteral("identity"));

    r.conversationCount = r.payload.value(QStringLiteral("conversations")).toArray().size();
    r.messageCount = r.payload.value(QStringLiteral("messages")).toArray().size();
    return r;
}

} // namespace BackupReader
