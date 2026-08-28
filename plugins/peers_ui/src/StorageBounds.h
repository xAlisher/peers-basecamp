#ifndef PEERS_STORAGE_BOUNDS_H
#define PEERS_STORAGE_BOUNDS_H

#include <QStringView>
#include <QtGlobal>

namespace StorageBounds {

constexpr qint64 maxGeneralCiphertextBytes = 100LL * 1024 * 1024;
constexpr qint64 maxAudioCiphertextBytes = 2LL * 1024 * 1024;

inline qint64 maxCiphertextBytesForMime(QStringView mime)
{
    return mime.startsWith(QStringView(u"audio/"), Qt::CaseInsensitive)
        ? maxAudioCiphertextBytes
        : maxGeneralCiphertextBytes;
}

inline bool validCacheFileSize(qint64 bytes, QStringView mime)
{
    return bytes > 0 && bytes <= maxCiphertextBytesForMime(mime);
}

} // namespace StorageBounds

#endif // PEERS_STORAGE_BOUNDS_H
