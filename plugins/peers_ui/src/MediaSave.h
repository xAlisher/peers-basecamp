#ifndef PEERS_MEDIA_SAVE_H
#define PEERS_MEDIA_SAVE_H

#include <QByteArray>
#include <QString>

namespace MediaSave {

// Extract bytes for inline or already-decrypted hosted media without re-encoding.
bool payloadBytes(const QString& raw, const QString& hostedCachePath,
                  QByteArray* bytes, QString* error);

// Replace the destination atomically and report every open/write/commit failure.
bool writeAtomically(const QString& destinationPath, const QByteArray& bytes,
                     QString* error);

} // namespace MediaSave

#endif // PEERS_MEDIA_SAVE_H
