#include "ContentMarkers.h"

#include <QString>

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

QString reply(const QString& body)
{
    return QStringLiteral("reply1:key:") + body;
}

QString relay(const QString& body)
{
    return QStringLiteral("lr1:sender") + QChar(0x241F) + body;
}

} // namespace

int main()
{
    const QString hosted = QStringLiteral("store2:cid:key:audio/mp4:0:0:cap");

    require(ContentMarkers::containsHostedReference(hosted), "direct hosted reference");
    require(ContentMarkers::containsHostedReference(reply(hosted)), "reply wrapper");
    require(ContentMarkers::containsHostedReference(relay(hosted)), "relay wrapper");
    require(ContentMarkers::containsHostedReference(QStringLiteral("pfp1:") + hosted),
            "avatar wrapper");
    require(ContentMarkers::containsHostedReference(reply(QStringLiteral("pfp1:") + hosted)),
            "reply/avatar wrappers");
    require(ContentMarkers::containsHostedReference(relay(reply(QStringLiteral("pfp1:") + hosted))),
            "relay/reply/avatar wrappers");

    require(ContentMarkers::containsHostedReference(QStringLiteral("reply1::") + hosted),
            "malformed reply fails closed");
    require(ContentMarkers::containsHostedReference(QStringLiteral("lr1:sender:") + hosted),
            "malformed relay fails closed");
    require(ContentMarkers::containsHostedReference(QStringLiteral("pfp1:clear:") + hosted),
            "malformed avatar clear fails closed");
    require(ContentMarkers::containsHostedReference(
                reply(QStringLiteral("pfp1:clear:") + hosted)),
            "reply-wrapped malformed avatar clear fails closed");
    require(ContentMarkers::containsHostedReference(QStringLiteral("pfp1:ordinary text")),
            "malformed avatar body fails closed");

    QString deeplyWrapped = hosted;
    for (int i = 0; i < 12; ++i)
        deeplyWrapped = reply(deeplyWrapped);
    require(ContentMarkers::containsHostedReference(deeplyWrapped), "depth exhaustion fails closed");

    require(!ContentMarkers::containsHostedReference(QStringLiteral("ordinary text")),
            "ordinary text remains safe");
    require(!ContentMarkers::containsHostedReference(reply(QStringLiteral("ordinary text"))),
            "ordinary reply remains safe");
    require(!ContentMarkers::containsHostedReference(relay(QStringLiteral("ordinary text"))),
            "ordinary relay remains safe");
    require(!ContentMarkers::containsHostedReference(QStringLiteral("pfp1:clear")),
            "avatar clear control remains safe");

    std::cout << "ok: hosted wrapper classification is bounded and fail-closed\n";
    return 0;
}
