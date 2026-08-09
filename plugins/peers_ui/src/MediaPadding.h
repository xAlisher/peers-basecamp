#ifndef PEERS_MEDIA_PADDING_H
#define PEERS_MEDIA_PADDING_H

#include <QByteArray>

//
// Padmé size padding — a straight port of Peers Android's `MediaPadding.kt`.
//
// Encrypting media hides its content but not its LENGTH, and a length is close
// to a fingerprint: an observer who sees a 2,847,113-byte blob learns a great
// deal about which file it is. Padmé buckets the padded length so many distinct
// files share one on-the-wire size, at a bounded (~12% max) overhead.
//
// Wire layout of the padded plaintext, before encryption:
//
//     [4-byte big-endian realLen][data][zero padding up to the Padmé bucket]
//
// This MUST match Android byte for byte or the two clients cannot read each
// other's media. `tests/media-blob.mjs` checks that against an independent
// implementation rather than trusting this comment.
//
namespace MediaPadding {

// Size of the length header, in bytes.
int headerBytes();

// The Padmé bucket for a length. Ported from MediaPadding.kt:19-27 — 64-bit
// throughout, because that is what Kotlin's Long-based numberOfLeadingZeros
// gives and the bucket boundaries differ if you do it in 32 bits.
qint64 padmeBucket(qint64 length);

// [4-byte BE realLen][data][zeros] grown to the Padmé bucket of (header + len).
QByteArray pad(const QByteArray& data);

// Inverse. Returns false — rather than a truncated buffer — when the input is
// too short or its declared length does not fit, since this parses bytes that
// came off the network.
bool strip(const QByteArray& padded, QByteArray* out);

} // namespace MediaPadding

#endif // PEERS_MEDIA_PADDING_H
