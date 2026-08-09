#include "VoiceRecorder.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUuid>

#include "MediaTools.h"

#include <cmath>

namespace {

// Mono 16 kHz is what speech needs and what Android captures; anything richer
// only makes the payload bigger for no audible gain.
constexpr int kSampleRate = 16000;

QString findTool(const QString &name)
{
    // Prefer the copy bundled with this module: inside the AppImage, whatever is
    // on PATH may not be loadable at all, and a user with no ffmpeg installed
    // should still be able to record.
    return MediaTools::resolveBin(name);
}

// The capture command, in preference order. ffmpeg first because it stops
// cleanly on `q` and finalises the WAV header; the others are fallbacks for
// machines that have PulseAudio/ALSA tooling but no ffmpeg.
struct Capture
{
    QString program;
    QStringList args;
    QString tool;
};

Capture captureCommand(const QString &wavPath)
{
    const QString secs = QString::number(VoiceRecorder::maxDurationMs() / 1000);

    QString p = findTool(QStringLiteral("ffmpeg"));
    if (!p.isEmpty()) {
        return {p,
                {QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"),
                 QStringLiteral("error"), QStringLiteral("-f"), QStringLiteral("pulse"),
                 QStringLiteral("-i"), QStringLiteral("default"), QStringLiteral("-ac"),
                 QStringLiteral("1"), QStringLiteral("-ar"), QString::number(kSampleRate),
                 QStringLiteral("-t"), secs, QStringLiteral("-y"), wavPath},
                QStringLiteral("ffmpeg")};
    }
    p = findTool(QStringLiteral("parecord"));
    if (!p.isEmpty()) {
        return {p,
                {QStringLiteral("--channels=1"),
                 QStringLiteral("--rate=%1").arg(kSampleRate),
                 QStringLiteral("--format=s16le"), QStringLiteral("--file-format=wav"), wavPath},
                QStringLiteral("parecord")};
    }
    p = findTool(QStringLiteral("arecord"));
    if (!p.isEmpty()) {
        return {p,
                {QStringLiteral("-q"), QStringLiteral("-f"), QStringLiteral("S16_LE"),
                 QStringLiteral("-c"), QStringLiteral("1"), QStringLiteral("-r"),
                 QString::number(kSampleRate), QStringLiteral("-t"), QStringLiteral("wav"),
                 QStringLiteral("-d"), secs, wavPath},
                QStringLiteral("arecord")};
    }
    return {};
}

quint32 le32(const QByteArray &b, int off)
{
    if (off + 4 > b.size())
        return 0;
    const auto *u = reinterpret_cast<const quint8 *>(b.constData() + off);
    return quint32(u[0]) | (quint32(u[1]) << 8) | (quint32(u[2]) << 16) | (quint32(u[3]) << 24);
}

// Locate the PCM payload of a RIFF/WAVE file. Returns false when this is not a
// WAV we can read — better to say so than to bucket header bytes as audio.
bool wavData(const QByteArray &wav, int *dataOff, int *dataLen, int *channels, int *rate)
{
    if (wav.size() < 12 || !wav.startsWith("RIFF") || wav.mid(8, 4) != QByteArray("WAVE"))
        return false;

    *channels = 1;
    *rate = kSampleRate;
    int pos = 12;
    while (pos + 8 <= wav.size()) {
        const QByteArray id = wav.mid(pos, 4);
        const quint32 sz = le32(wav, pos + 4);
        const int body = pos + 8;
        if (id == QByteArray("fmt ") && body + 16 <= wav.size()) {
            *channels = qMax(1, int(quint8(wav[body + 2])) | (int(quint8(wav[body + 3])) << 8));
            *rate = qMax(1, int(le32(wav, body + 4)));
        } else if (id == QByteArray("data")) {
            // A tool killed mid-stream may leave the size field at 0 or -1; in
            // that case everything to EOF is audio.
            const int remaining = wav.size() - body;
            int len = int(sz);
            if (len <= 0 || len > remaining)
                len = remaining;
            *dataOff = body;
            *dataLen = len;
            return len > 0;
        }
        if (sz == 0)
            break;
        pos = body + int(sz) + (int(sz) & 1);   // chunks are word-aligned
    }
    return false;
}

}   // namespace

QString VoiceRecorder::captureTool()
{
    return captureCommand(QStringLiteral("/dev/null")).tool;
}

VoiceRecorder::VoiceRecorder(QObject *parent) : QObject(parent) {}

VoiceRecorder::~VoiceRecorder()
{
    cancel();
}

int VoiceRecorder::elapsedMs() const
{
    if (!m_proc)
        return m_frozenMs;
    return int(qMin<qint64>(m_clock.elapsed(), maxDurationMs()));
}

bool VoiceRecorder::start(QString *whyNot)
{
    if (m_proc) {
        if (whyNot)
            *whyNot = QStringLiteral("Already recording.");
        return false;
    }

    const QString dir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    m_wavPath = QDir(dir).filePath(QStringLiteral("peers-voice-%1.wav")
                                       .arg(QUuid::createUuid().toString(QUuid::Id128)));

    const Capture cmd = captureCommand(m_wavPath);
    if (cmd.program.isEmpty()) {
        if (whyNot)
            *whyNot = QStringLiteral(
                "No microphone capture tool found. Voice notes need one of ffmpeg, parecord or "
                "arecord on PATH.");
        m_wavPath.clear();
        return false;
    }

    m_proc = new QProcess(this);
    m_proc->setProgram(cmd.program);
    m_proc->setArguments(cmd.args);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    // A bundled, nix-built recorder must not inherit the AppImage's
    // LD_LIBRARY_PATH — it would load the host's mismatched libraries and die.
    m_proc->setProcessEnvironment(MediaTools::cleanSpawnEnv());
    m_proc->start();
    if (!m_proc->waitForStarted(4000)) {
        if (whyNot)
            *whyNot = QStringLiteral("Could not start %1: %2").arg(cmd.tool, m_proc->errorString());
        cleanup();
        return false;
    }

    m_clock.start();
    m_frozenMs = 0;

    m_ticker = new QTimer(this);
    m_ticker->setInterval(500);
    connect(m_ticker, &QTimer::timeout, this, [this] {
        if (!m_proc)
            return;
        Q_EMIT tick(elapsedMs());
        // ffmpeg/arecord stop themselves at the cap; parecord does not, and in
        // any case the caller must be told capture has ended.
        if (m_clock.elapsed() >= maxDurationMs()
            || m_proc->state() == QProcess::NotRunning) {
            m_frozenMs = int(qMin<qint64>(m_clock.elapsed(), maxDurationMs()));
            stopProcess();
            if (m_ticker)
                m_ticker->stop();
            Q_EMIT autoStopped();
        }
    });
    m_ticker->start();
    return true;
}

void VoiceRecorder::stopProcess()
{
    if (!m_proc)
        return;
    if (m_proc->state() != QProcess::NotRunning) {
        // ffmpeg quits gracefully on `q`, finalising the RIFF size fields.
        m_proc->write("q\n");
        m_proc->closeWriteChannel();
        if (!m_proc->waitForFinished(3000)) {
            m_proc->terminate();   // parecord/arecord close the file on SIGTERM
            if (!m_proc->waitForFinished(3000))
                m_proc->kill();
        }
    }
}

void VoiceRecorder::cleanup()
{
    if (m_ticker) {
        m_ticker->stop();
        m_ticker->deleteLater();
        m_ticker = nullptr;
    }
    if (m_proc) {
        m_proc->deleteLater();
        m_proc = nullptr;
    }
}

void VoiceRecorder::cancel()
{
    stopProcess();
    cleanup();
    if (!m_wavPath.isEmpty()) {
        QFile::remove(m_wavPath);
        m_wavPath.clear();
    }
    m_frozenMs = 0;
}

bool VoiceRecorder::finish(QByteArray *bytes, QString *mime, int *durationMs,
                           QVector<int> *waveform, QString *whyNot)
{
    const int elapsed = elapsedMs();
    stopProcess();
    cleanup();

    const QString wavPath = m_wavPath;
    m_wavPath.clear();
    m_frozenMs = 0;

    auto fail = [&](const QString &why) {
        if (whyNot)
            *whyNot = why;
        if (!wavPath.isEmpty())
            QFile::remove(wavPath);
        return false;
    };

    if (wavPath.isEmpty())
        return fail(QStringLiteral("Not recording."));

    QFile f(wavPath);
    if (!f.open(QIODevice::ReadOnly))
        return fail(QStringLiteral("The recording could not be read back."));
    const QByteArray wav = f.readAll();
    f.close();

    int off = 0, len = 0, channels = 1, rate = kSampleRate;
    if (!wavData(wav, &off, &len, &channels, &rate))
        return fail(QStringLiteral("Nothing was captured — check that a microphone is available."));

    // Duration from the samples themselves, so it describes the audio actually
    // present rather than how long the button was held.
    const int frames = len / (2 * qMax(1, channels));
    int ms = int(qint64(frames) * 1000 / qMax(1, rate));
    if (ms <= 0)
        ms = elapsed;
    if (ms < 200)
        return fail(QStringLiteral("That was too short to send."));

    // ~40 bars, each the peak amplitude in its slice, normalised so the loudest
    // bar is 100. Normalising against the take rather than full scale keeps a
    // quietly-spoken note from rendering as a flat line.
    const auto *pcm = reinterpret_cast<const qint16 *>(wav.constData() + off);
    const int bars = waveformBars();
    QVector<int> peaks(bars, 0);
    int loudest = 1;
    for (int i = 0; i < bars; ++i) {
        const qint64 from = qint64(frames) * i / bars;
        const qint64 to = qint64(frames) * (i + 1) / bars;
        int peak = 0;
        for (qint64 fr = from; fr < to; ++fr) {
            const int v = qAbs(int(pcm[fr * channels]));
            if (v > peak)
                peak = v;
        }
        peaks[i] = peak;
        loudest = qMax(loudest, peak);
    }
    waveform->clear();
    waveform->reserve(bars);
    for (int p : std::as_const(peaks))
        waveform->append(qBound(0, int(std::lround(100.0 * p / loudest)), 100));

    // Transcode to what the phone expects. Without ffmpeg the WAV goes as-is:
    // bigger, but playable, and far better than refusing to send.
    const QString ff = MediaTools::resolveBin(QStringLiteral("ffmpeg"));
    if (!ff.isEmpty()) {
        const QString m4a = wavPath + QStringLiteral(".m4a");
        QProcess enc;
        enc.setProcessEnvironment(MediaTools::cleanSpawnEnv());
        enc.start(ff,
                  {QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"),
                   QStringLiteral("error"), QStringLiteral("-i"), wavPath, QStringLiteral("-c:a"),
                   QStringLiteral("aac"), QStringLiteral("-b:a"), QStringLiteral("32k"),
                   QStringLiteral("-ac"), QStringLiteral("1"), QStringLiteral("-movflags"),
                   QStringLiteral("+faststart"), QStringLiteral("-y"), m4a});
        if (enc.waitForFinished(30000) && enc.exitStatus() == QProcess::NormalExit
            && enc.exitCode() == 0) {
            QFile out(m4a);
            if (out.open(QIODevice::ReadOnly)) {
                *bytes = out.readAll();
                out.close();
            }
            QFile::remove(m4a);
            if (!bytes->isEmpty()) {
                *mime = QStringLiteral("audio/mp4");
                *durationMs = ms;
                QFile::remove(wavPath);
                return true;
            }
        }
        QFile::remove(m4a);
    }

    *bytes = wav;
    *mime = QStringLiteral("audio/wav");
    *durationMs = ms;
    QFile::remove(wavPath);
    return true;
}
