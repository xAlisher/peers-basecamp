#ifndef PEERS_BACKUP_READER_H
#define PEERS_BACKUP_READER_H

#include <QByteArray>
#include <QJsonObject>
#include <QString>

//
// Reader for the Peers mobile encrypted backup (`.peersenc`).
//
// Ground truth, with path:line citations, in docs/BACKUP-FORMAT.md. In short:
// the file is a single UTF-8 JSON envelope (no magic bytes, no framing) whose
// `ct` is AES-256-GCM over the plaintext backup JSON, keyed by
// PBKDF2-HMAC-SHA256 over the passphrase.
//
// SCOPE, honestly stated: this reads the backup. It does NOT adopt the identity
// inside it — `chat_module` 0.2.2 exposes no identity-import method, so there is
// nowhere to put the seed (ADR 0004). The seed is therefore parsed, reported as
// present, and deliberately NOT surfaced to QML.
//
namespace BackupReader {

struct Result {
    bool ok = false;
    QString error;            // user-facing; never leaks key material

    // Populated on success.
    QJsonObject payload;      // the decrypted backup JSON
    bool hasIdentity = false; // an `identity` seed was present
    int identityBytes = 0;    // its decoded length (64 in practice)
    int conversationCount = 0;
    int messageCount = 0;
};

// Decrypt a `.peersenc` envelope. `envelope` is the raw file contents.
//
// Fails cleanly and completely — a wrong passphrase yields ok=false with no
// partial payload, because GCM authenticates before we ever look at the
// plaintext.
Result open(const QByteArray& envelope, const QString& passphrase);

// Exposed for tests: PBKDF2-HMAC-SHA256 → `keyLen` bytes.
QByteArray deriveKey(const QString& passphrase, const QByteArray& salt, int iterations,
                     int keyLen = 32);

} // namespace BackupReader

#endif // PEERS_BACKUP_READER_H
