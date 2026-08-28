#include "MediaSave.h"

#include "ContentMarkers.h"
#include "StorageBounds.h"

#include <QFile>
#include <QFileDevice>
#include <QIODevice>
#include <QJsonObject>
#include <QSaveFile>

namespace MediaSave {

namespace {
void setError(QString* error, const QString& message)
{
    if (error)
        *error = message;
}
}

bool readBounded(QIODevice* source, qint64 expectedSize, qint64 maxBytes,
                 QByteArray* bytes, QString* error)
{
    if (!source || !bytes || expectedSize <= 0 || expectedSize > maxBytes || maxBytes <= 0) {
        setError(error, QStringLiteral("That media has an invalid size."));
        return false;
    }
    bytes->clear();
    bytes->reserve(static_cast<qsizetype>(expectedSize));
    char buffer[64 * 1024];
    while (bytes->size() <= maxBytes) {
        const qint64 room = maxBytes + 1 - bytes->size();
        const qint64 count = source->read(buffer, qMin<qint64>(room, sizeof(buffer)));
        if (count < 0) {
            bytes->clear();
            setError(error, QStringLiteral("Could not read the downloaded media."));
            return false;
        }
        if (count == 0) {
            if (!source->atEnd()) {
                bytes->clear();
                setError(error, QStringLiteral("The downloaded media is incomplete."));
                return false;
            }
            break;
        }
        bytes->append(buffer, count);
        if (bytes->size() > maxBytes) {
            bytes->clear();
            setError(error, QStringLiteral("The downloaded media is too large."));
            return false;
        }
    }
    if (bytes->size() != expectedSize) {
        bytes->clear();
        setError(error, QStringLiteral("The downloaded media changed while it was read."));
        return false;
    }
    return true;
}

bool writeCompletely(QIODevice* destination, const QByteArray& bytes, QString* error)
{
    if (!destination) {
        setError(error, QStringLiteral("Could not open the destination."));
        return false;
    }
    qint64 offset = 0;
    while (offset < bytes.size()) {
        const qint64 written = destination->write(
            bytes.constData() + offset, bytes.size() - offset);
        if (written <= 0) {
            setError(error, QStringLiteral("Could not write the complete file."));
            return false;
        }
        offset += written;
    }
    return true;
}

bool payloadBytes(const QString& raw, const QString& hostedCachePath,
                  QByteArray* bytes, QString* error)
{
    if (!bytes)
        return false;
    bytes->clear();
    if (error)
        error->clear();

    const QJsonObject decoded = ContentMarkers::decodeToJson(raw);
    const QString kind = decoded.value(QStringLiteral("kind")).toString();
    const bool hosted = decoded.contains(QStringLiteral("cid"));
    if (hosted && (kind == QLatin1String("media") || kind == QLatin1String("voice"))) {
        QFile file(hostedCachePath);
        const qint64 maxBytes = StorageBounds::maxCiphertextBytesForMime(
            decoded.value(QStringLiteral("mime")).toString());
        if (hostedCachePath.isEmpty() || !file.open(QIODevice::ReadOnly)
            || file.size() <= 0 || file.size() > maxBytes) {
            setError(error, QStringLiteral("That media has not finished downloading yet."));
            return false;
        }
        return readBounded(&file, file.size(), maxBytes, bytes, error);
    }

    if (kind == QLatin1String("photo") || kind == QLatin1String("voice")) {
        *bytes = ContentMarkers::inlinePayloadBytes(raw);
        if (!bytes->isEmpty())
            return true;
        setError(error, QStringLiteral("That message carries no data."));
        return false;
    }

    setError(error, QStringLiteral("There is nothing to save on that message."));
    return false;
}

bool writeAtomically(const QString& destinationPath, const QByteArray& bytes,
                     QString* error)
{
    if (error)
        error->clear();
    QSaveFile file(destinationPath);
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly)) {
        setError(error, QStringLiteral("Could not open the destination."));
        return false;
    }

    if (!writeCompletely(&file, bytes, error)) {
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        setError(error, QStringLiteral("Could not finish writing the file."));
        return false;
    }
    return true;
}

} // namespace MediaSave
