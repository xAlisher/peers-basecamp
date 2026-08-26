#include "MediaTools.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

namespace MediaTools {
namespace {

QString findModuleDir()
{
#if defined(__linux__)
    QFile f(QStringLiteral("/proc/self/maps"));
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        // /proc/self/maps is virtual and reports size 0, so atEnd() is true
        // immediately and a `while (!f.atEnd())` loop never runs. Read lines
        // until readLine() returns empty — that is the real EOF.
        QByteArray line;
        while (!(line = f.readLine()).isEmpty()) {
            if (line.contains("peers_ui_plugin.so")
                || line.contains("peers_ui_replica_factory.so")) {
                const int slash = line.indexOf('/');
                if (slash >= 0)
                    return QFileInfo(QString::fromUtf8(line.mid(slash)).trimmed()).absolutePath();
            }
        }
    }
#endif
    return QString();
}

}   // namespace

QString moduleDir()
{
    // Resolved once: the plugin's own path does not move while it is loaded.
    static const QString dir = findModuleDir();
    return dir;
}

bool isBundled(const QString& path)
{
    const QString dir = moduleDir();
    return !dir.isEmpty() && path.startsWith(dir + QStringLiteral("/bin/"));
}

QString resolveBin(const QString& name)
{
    const QString override =
        qEnvironmentVariable(QStringLiteral("PEERS_%1_BIN").arg(name.toUpper()).toLatin1().constData());
    if (!override.isEmpty())
        return override;

    const QString dir = moduleDir();
    if (!dir.isEmpty()) {
        const QFileInfo fi(dir + QStringLiteral("/bin/") + name);
        if (fi.exists() && fi.isExecutable())
            return fi.absoluteFilePath();
    }

    // Not bundled — fall back to PATH. Returns empty when it is not there, so
    // callers can say which tool is missing instead of failing opaquely.
    return QStandardPaths::findExecutable(name);
}

bool probeMediaSize(const QString& path, int* width, int* height)
{
    if (!width || !height || path.isEmpty())
        return false;

    const QString exe = resolveBin(QStringLiteral("ffprobe"));
    if (exe.isEmpty())
        return false;

    QProcess probe;
    probe.setProcessEnvironment(cleanSpawnEnv());
    probe.setProgram(exe);
    probe.setArguments({QStringLiteral("-v"),
                        QStringLiteral("error"),
                        QStringLiteral("-protocol_whitelist"),
                        QStringLiteral("file,crypto,data"),
                        QStringLiteral("-select_streams"),
                        QStringLiteral("v:0"),
                        QStringLiteral("-show_entries"),
                        QStringLiteral("stream=width,height"),
                        QStringLiteral("-of"),
                        QStringLiteral("csv=p=0:s=x"),
                        QStringLiteral("-i"),
                        path});
    probe.start();
    if (!probe.waitForStarted(1500) || !probe.waitForFinished(5000)) {
        probe.kill();
        probe.waitForFinished(1000);
        return false;
    }
    if (probe.exitStatus() != QProcess::NormalExit || probe.exitCode() != 0)
        return false;

    const QString output = QString::fromUtf8(probe.readAllStandardOutput().left(128)).trimmed();
    static const QRegularExpression dimensions(QStringLiteral("^(\\d+)x(\\d+)$"));
    const QRegularExpressionMatch match = dimensions.match(output);
    if (!match.hasMatch())
        return false;

    bool widthOk = false;
    bool heightOk = false;
    const int parsedWidth = match.captured(1).toInt(&widthOk);
    const int parsedHeight = match.captured(2).toInt(&heightOk);
    if (!widthOk || !heightOk || parsedWidth < 1 || parsedWidth > 100000
        || parsedHeight < 1 || parsedHeight > 100000) {
        return false;
    }
    *width = parsedWidth;
    *height = parsedHeight;
    return true;
}

QString mediaCacheDir()
{
    const QString dir = moduleDir();
    if (!dir.isEmpty()) {
        const QString inRoot = dir + QStringLiteral("/media-cache");
        if (QDir().mkpath(inRoot)) {
            // mkpath succeeds on an existing dir too, so prove it is writable
            // rather than assuming — a read-only install must fall through.
            QFile probe(inRoot + QStringLiteral("/.w"));
            if (probe.open(QIODevice::WriteOnly)) {
                probe.close();
                QFile::remove(probe.fileName());
                return inRoot;
            }
        }
    }
    const QString fallback = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(fallback);
    return fallback;
}

QProcessEnvironment cleanSpawnEnv()
{
    QProcessEnvironment e = QProcessEnvironment::systemEnvironment();
    e.remove(QStringLiteral("LD_LIBRARY_PATH"));
    e.remove(QStringLiteral("LD_PRELOAD"));
    return e;
}

}   // namespace MediaTools
