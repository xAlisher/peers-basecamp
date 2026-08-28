#ifndef PEERS_HOSTED_BOUNDARY_H
#define PEERS_HOSTED_BOUNDARY_H

#include "ContentMarkers.h"

#include <QJsonObject>
#include <QString>

namespace HostedBoundary {

inline bool restoreToComposer(const QString& raw)
{
    return !ContentMarkers::containsHostedReference(raw);
}

inline void sanitizeViewRow(QJsonObject* row)
{
    if (!row)
        return;
    row->remove(QStringLiteral("cid"));
    row->remove(QStringLiteral("key"));
    row->remove(QStringLiteral("keyB64"));
    row->remove(QStringLiteral("cap"));
    row->remove(QStringLiteral("capability"));
}

} // namespace HostedBoundary

#endif // PEERS_HOSTED_BOUNDARY_H
