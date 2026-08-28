#include "ContentMarkers.h"
#include "MediaSave.h"

#include <QFile>
#include <QTemporaryDir>

#include <cstdlib>
#include <iostream>

namespace {
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

    std::cout << "ok: hosted and inline voice Save is byte-identical and truthful\n";
    return 0;
}
