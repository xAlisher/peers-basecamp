#include "MediaSave.h"

#include "ContentMarkers.h"
#include "StorageBounds.h"

#include <QFile>
#include <QFileDevice>
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
        const qint64 expected = file.size();
        *bytes = file.readAll();
        if (file.error() != QFileDevice::NoError || bytes->size() != expected) {
            bytes->clear();
            setError(error, QStringLiteral("Could not read the downloaded media."));
            return false;
        }
        return true;
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

    qint64 offset = 0;
    while (offset < bytes.size()) {
        const qint64 written = file.write(bytes.constData() + offset, bytes.size() - offset);
        if (written <= 0) {
            file.cancelWriting();
            setError(error, QStringLiteral("Could not write the complete file."));
            return false;
        }
        offset += written;
    }
    if (!file.commit()) {
        setError(error, QStringLiteral("Could not finish writing the file."));
        return false;
    }
    return true;
}

} // namespace MediaSave
