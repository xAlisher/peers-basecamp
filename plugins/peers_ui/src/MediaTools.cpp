#include "MediaTools.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
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
