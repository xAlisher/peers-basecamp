#ifndef PEERS_MEDIA_SAVE_H
#define PEERS_MEDIA_SAVE_H

#include <QByteArray>
#include <QString>

class QIODevice;

namespace MediaSave {

// Extract bytes for inline or already-decrypted hosted media without re-encoding.
bool payloadBytes(const QString& raw, const QString& hostedCachePath,
                  QByteArray* bytes, QString* error);

// Read exactly the previously observed size while never materialising more than maxBytes.
bool readBounded(QIODevice* source, qint64 expectedSize, qint64 maxBytes,
                 QByteArray* bytes, QString* error);

// Loop through partial writes and fail on zero/error rather than blessing truncation.
bool writeCompletely(QIODevice* destination, const QByteArray& bytes, QString* error);

// Replace the destination atomically and report every open/write/commit failure.
bool writeAtomically(const QString& destinationPath, const QByteArray& bytes,
                     QString* error);

} // namespace MediaSave

#endif // PEERS_MEDIA_SAVE_H
