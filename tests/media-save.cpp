#include "ContentMarkers.h"
#include "HostedBoundary.h"
#include "MediaSave.h"

#include <QBuffer>
#include <QFile>
#include <QJsonObject>
#include <QTemporaryDir>

#include <cstdlib>
#include <iostream>

namespace {
class FailingWriteDevice final : public QIODevice {
public:
    FailingWriteDevice() { open(QIODevice::WriteOnly); }

protected:
    qint64 readData(char*, qint64) override { return -1; }
    qint64 writeData(const char*, qint64 maxSize) override
    {
        if (m_wrote)
            return -1;
        m_wrote = true;
        return qMin<qint64>(3, maxSize);
    }

private:
    bool m_wrote = false;
};

void require(bool condition, const char* message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}
}

int main()
{
    QTemporaryDir dir;
    require(dir.isValid(), "temporary directory");

    const QByteArray expected("voice-bytes\0verbatim", 20);
    const QString inlineVoice = ContentMarkers::encodeVoiceNote(
        QStringLiteral("audio/mp4"), 1234, QList<int>{1, 2, 3}, expected);
    QByteArray bytes;
    QString error;
    require(MediaSave::payloadBytes(inlineVoice, QString(), &bytes, &error),
            "inline voice payload loads");
    require(bytes == expected, "inline voice bytes are byte-for-byte identical");

    const QString cachedPath = dir.filePath(QStringLiteral("hosted.m4a"));
    QFile cached(cachedPath);
    require(cached.open(QIODevice::WriteOnly), "hosted cache fixture opens");
    require(cached.write(expected) == expected.size(), "hosted cache fixture writes fully");
    cached.close();

    const QString hostedVoice = ContentMarkers::encodeHostedMedia(
        QStringLiteral("cid123"),
        QStringLiteral("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
        QStringLiteral("audio/mp4"), 1234, 1, QStringLiteral("deadbeef"));
    bytes.clear();
    error.clear();
    require(MediaSave::payloadBytes(hostedVoice, cachedPath, &bytes, &error),
            "hosted voice payload loads");
    require(bytes == expected, "hosted voice bytes are byte-for-byte identical");

    bytes.clear();
    error.clear();
    require(!MediaSave::payloadBytes(hostedVoice, dir.filePath(QStringLiteral("missing")),
                                     &bytes, &error),
            "incomplete hosted download fails");
    require(!error.isEmpty(), "incomplete hosted download reports an error");

    QBuffer shortRead;
    shortRead.setData(QByteArray("tiny"));
    require(shortRead.open(QIODevice::ReadOnly), "short-read fixture opens");
    bytes.clear();
    error.clear();
    require(!MediaSave::readBounded(&shortRead, 8, 8, &bytes, &error),
            "short hosted read fails");

    QBuffer growingRead;
    growingRead.setData(QByteArray("123456789"));
    require(growingRead.open(QIODevice::ReadOnly), "growing-read fixture opens");
    bytes.clear();
    error.clear();
    require(!MediaSave::readBounded(&growingRead, 4, 8, &bytes, &error),
            "hosted read that grows past its checked size fails bounded");

    FailingWriteDevice failingWrite;
    error.clear();
    require(!MediaSave::writeCompletely(&failingWrite, expected, &error),
            "short then failed destination write fails truthfully");

    const QString savedPath = dir.filePath(QStringLiteral("saved.m4a"));
    error.clear();
    require(MediaSave::writeAtomically(savedPath, expected, &error),
            "destination write succeeds");
    QFile saved(savedPath);
    require(saved.open(QIODevice::ReadOnly), "saved destination opens");
    require(saved.readAll() == expected, "saved destination is byte-for-byte identical");

    error.clear();
    require(!MediaSave::writeAtomically(dir.path(), expected, &error),
            "destination write failure is truthful");
    require(!error.isEmpty(), "destination write failure reports an error");

    QString depthExhausted = hostedVoice;
    for (int i = 0; i < 20; ++i)
        depthExhausted.prepend(QStringLiteral("reply1:key:"));
    const QList<QString> sensitiveBodies{
        hostedVoice,
        QStringLiteral("reply1:key:") + hostedVoice,
        QStringLiteral("reply1:key:pfp1:clear:") + hostedVoice,
        QStringLiteral("store2:") + QString(9000, QLatin1Char('x')),
        depthExhausted,
    };
    for (const QString& body : sensitiveBodies)
        require(!HostedBoundary::restoreToComposer(body),
                "hosted body is never restored to composer");
    require(HostedBoundary::restoreToComposer(QStringLiteral("ordinary message")),
            "ordinary text may be restored to composer");
    QJsonObject viewRow{{QStringLiteral("cid"), QStringLiteral("cid")},
                        {QStringLiteral("keyB64"), QStringLiteral("key")},
                        {QStringLiteral("cap"), QStringLiteral("capability")},
                        {QStringLiteral("text"), QStringLiteral("safe")}};
    HostedBoundary::sanitizeViewRow(&viewRow);
    require(!viewRow.contains(QStringLiteral("cid"))
                && !viewRow.contains(QStringLiteral("keyB64"))
                && !viewRow.contains(QStringLiteral("cap")),
            "serialized view row contains no hosted secret fields");

    std::cout << "ok: hosted and inline voice Save is byte-identical and truthful\n";
    return 0;
}
