#ifndef PEERS_STORAGE_CLIENT_H
#define PEERS_STORAGE_CLIENT_H

#include <QByteArray>
#include <QObject>
#include <QString>
#include <functional>

class QNetworkAccessManager;

//
// Logos-Storage hosted media — the `store2:` path, ported from Peers Android's
// `StorageModule.kt`.
//
// WHY THIS EXISTS: the chat core carries only text, so media rides a marker in
// the message body. Small images fit inline as base64 (`img1:`), but anything
// real — a photo, a GIF, a video — does not survive an MLS message. Those go to
// Logos Storage encrypted, and only a reference travels in the chat:
//
//     store2:<cid>:<key>:<mime>:<w>:<h>[:<cap>]
//
// The key travels END-TO-END inside the encrypted message and is NEVER sent to
// the storage node. The node holds ciphertext it cannot read, addressed by a
// hash of that ciphertext.
//
// Blob layout at the CID (must match Android byte for byte or the clients
// cannot read each other's media):
//
//     iv(12) || AES-256-GCM( Padmé-padded plaintext ) || tag(16)
//
// CONFIGURATION. The token is a legacy migration credential for uploads and
// capless downloads. It must not be embedded in an LGX or installation. New
// downloads use their per-blob capability without transmitting this bearer.
//
//     PEERS_STORAGE_BASE   default https://msg.logos.live/s/api/storage/v1
//     PEERS_STORAGE_TOKEN  default empty
//
// With no token, uploads and legacy capless downloads fail closed. A validated
// capability-bearing marker may still be fetched.
//
class StorageClient : public QObject
{
    Q_OBJECT

public:
    explicit StorageClient(QObject* parent = nullptr);
    ~StorageClient() override;

    // Whether the legacy upload path is configured.
    bool uploadConfigured() const;
    QString baseUrl() const;

    struct Uploaded {
        QString cid;
        QString keyB64;   // 32-byte AES key, base64 — for the marker only
        QString cap;      // per-blob fetch capability; may be empty (legacy)
    };

    using UploadCb = std::function<void(bool ok, Uploaded, QString error)>;
    using DownloadCb = std::function<void(bool ok, QString localPath, QString error)>;

    // Pad → encrypt → POST. `bytes` is the raw file.
    void uploadEncrypted(const QByteArray& bytes, UploadCb cb);

    // GET → decrypt → unpad → cache. Returns a local file path.
    //
    // Every field here came off the network inside a peer's message, so each is
    // re-validated before it reaches a URL or a filesystem path — the marker
    // parser having already checked them is not a reason to trust them here.
    void downloadDecrypt(const QString& cid, const QString& keyB64, const QString& cap,
                         const QString& mime, DownloadCb cb);

    // Cache path for a CID: SHA-256(cid) in lowercase hex, never the raw CID —
    // a peer-supplied identifier must not become a filename. A fixed suffix is
    // retained so Qt Quick can select an image decoder for local file URLs.
    static QString cacheFileFor(const QString& cid, const QString& mime);
    static QString cacheSuffixForMime(const QString& mime);

    // Field validation, mirroring StorageRef.kt. Exposed for tests.
    static bool validCid(const QString& cid);
    static bool validCap(const QString& cap);     // empty is valid (legacy capless)
    static bool validMime(const QString& mime);
    static bool validKeyB64(const QString& keyB64);   // must decode to exactly 32 bytes

private:
    QNetworkAccessManager* m_net = nullptr;
};

#endif // PEERS_STORAGE_CLIENT_H
