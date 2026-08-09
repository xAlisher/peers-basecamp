#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QVector>

class QProcess;
class QTimer;

//
// Voice-note capture for the desktop client.
//
// The Qt host does not ship QtMultimedia, so there is no in-process recorder to
// use. Rather than declare voice notes impossible on the desktop, this drives an
// external capture tool (ffmpeg, else parecord, else arecord) over QProcess and
// produces exactly the payload Peers Android produces: mono AAC in an MP4
// container, a duration in milliseconds, and ~40 amplitude bars normalised to
// 0..100 (src/native/Audio.ts).
//
// Capture always lands as WAV first. That is what makes the waveform real —
// the bars are measured from the PCM samples, not invented — and the WAV is then
// transcoded to AAC so the phone can play it back with no special handling.
//
class VoiceRecorder : public QObject
{
    Q_OBJECT
public:
    explicit VoiceRecorder(QObject *parent = nullptr);
    ~VoiceRecorder() override;

    // Android stops capture at two minutes; matching it keeps a stray recording
    // from growing into something no MLS message could carry.
    static constexpr int maxDurationMs() { return 120000; }
    // Android renders ~40 bars.
    static constexpr int waveformBars() { return 40; }

    // Name of the capture tool that will be used, or an empty string when the
    // machine has none. Callers use this to explain the failure concretely.
    static QString captureTool();

    bool recording() const { return m_proc != nullptr; }
    int elapsedMs() const;

    // Begins capture. On failure returns false and fills `whyNot`.
    bool start(QString *whyNot);
    // Stops and discards.
    void cancel();
    // Stops, finalises and decodes. On success fills every out-param.
    bool finish(QByteArray *bytes, QString *mime, int *durationMs, QVector<int> *waveform,
                QString *whyNot);

Q_SIGNALS:
    // Capture hit maxDurationMs() and stopped itself. What was captured is still
    // there to be sent — this is a stop, not a discard.
    void autoStopped();
    // Roughly once a second while recording, so the composer can show a timer.
    void tick(int elapsedMs);

private:
    void stopProcess();
    void cleanup();

    QProcess *m_proc = nullptr;
    QTimer *m_ticker = nullptr;
    QElapsedTimer m_clock;
    QString m_wavPath;
    int m_frozenMs = 0;   // elapsed at the moment capture stopped
};
