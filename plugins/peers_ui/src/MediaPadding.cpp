#include "MediaPadding.h"

namespace MediaPadding {
namespace {

constexpr int kHeader = 4;   // MediaPadding.kt:12

// Kotlin's java.lang.Long.numberOfLeadingZeros, for a non-negative value.
int leadingZeros64(quint64 v)
{
    if (v == 0)
        return 64;
    int n = 0;
    while ((v & (quint64(1) << 63)) == 0) {
        v <<= 1;
        ++n;
    }
    return n;
}

} // namespace

int headerBytes() { return kHeader; }

qint64 padmeBucket(qint64 length)
{
    // MediaPadding.kt:19-27, transcribed. The two shifts are floor(log2 l) and
    // floor(log2 e)+1; `lastBits` is how many low bits get rounded up.
    if (length < 2)
        return 2;
    const int e = 63 - leadingZeros64(static_cast<quint64>(length));
    const int s = (63 - leadingZeros64(static_cast<quint64>(e))) + 1;
    const int lastBits = e - s;
    if (lastBits <= 0)
        return length;
    const qint64 mask = (qint64(1) << lastBits) - 1;
    return (length + mask) & ~mask;
}

QByteArray pad(const QByteArray& data)
{
    const qint64 realLen = data.size();
    const qint64 total = kHeader + realLen;
    const qint64 bucket = padmeBucket(total);

    QByteArray out(static_cast<int>(bucket), '\0');
    // Big-endian length header.
    out[0] = static_cast<char>((realLen >> 24) & 0xFF);
    out[1] = static_cast<char>((realLen >> 16) & 0xFF);
    out[2] = static_cast<char>((realLen >> 8) & 0xFF);
    out[3] = static_cast<char>(realLen & 0xFF);
    if (realLen > 0)
        out.replace(kHeader, static_cast<int>(realLen), data);
    return out;
}

bool strip(const QByteArray& padded, QByteArray* out)
{
    if (!out)
        return false;
    if (padded.size() < kHeader)
        return false;   // MediaPadding.kt:44

    const quint32 realLen = (static_cast<quint8>(padded[0]) << 24)
        | (static_cast<quint8>(padded[1]) << 16) | (static_cast<quint8>(padded[2]) << 8)
        | static_cast<quint8>(padded[3]);

    // A declared length that overruns the buffer is hostile input, not a short
    // read — refuse rather than clamp.
    if (static_cast<qint64>(kHeader) + realLen > padded.size())
        return false;   // MediaPadding.kt:49-52

    *out = padded.mid(kHeader, static_cast<int>(realLen));
    return true;
}

} // namespace MediaPadding
