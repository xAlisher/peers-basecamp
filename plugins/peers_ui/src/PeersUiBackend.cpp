#include "PeersUiBackend.h"

// Generated umbrella: LogosModules (behind modules()) built from
// metadata.json#dependencies — the Qt-typed chat_module wrapper, LogosResult
// and logos::CallError all live here.
#include "logos_sdk.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QTimer>

#include "ContentMarkers.h"

namespace {

// Empty means "logos.test", per ChatConfig in chat_module.lidl. Named
// explicitly so the choice is visible rather than implied by a default.
constexpr const char* kDefaultDeliveryPreset = "logos.test";
constexpr const char* kChatLogLevel = "info";

constexpr int kHealthIntervalMs = 15000;

// How many failures to retain for the UI's error strip.
constexpr int kMaxRetainedErrors = 50;

QString shortLabel(const QString& address)
{
    // Peers shows the leading 8 hex characters as a row label.
    return address.left(8);
}

} // namespace

PeersUiBackend::PeersUiBackend(QObject* parent)
    : PeersUiBackendSimpleSource(parent)
{
    if (QCoreApplication::organizationName().isEmpty())
        QCoreApplication::setOrganizationName(QStringLiteral("Logos"));
    if (QCoreApplication::applicationName().isEmpty())
        QCoreApplication::setApplicationName(QStringLiteral("peers-basecamp"));

    setChatStatus(PeersUiBackendSimpleSource::Stopped);
    setStatusDetail(QString());
    setMyAddress(QString());
    setMyLabel(QString());
    setCurrentConversationId(QString());
    setLoadedConversationId(QString());
    setConversationsJson(QStringLiteral("[]"));
    setMessagesJson(QStringLiteral("[]"));
    setMembersJson(QStringLiteral("[]"));
    setContactsJson(QStringLiteral("[]"));
    setSettingsJson(QStringLiteral("{}"));
    setCurrentPinnedJson(QStringLiteral("{}"));

    loadState();
}

PeersUiBackend::~PeersUiBackend()
{
    if (m_moduleInitialised) {
        // Best effort — the host may already be tearing the module down.
        modules().chat_module.shutdown();
    }
}

// ── lifecycle ───────────────────────────────────────────────────────────────

void PeersUiBackend::onContextReady()
{
    // Defer one turn. Doing synchronous module work directly inside
    // onContextReady runs it while the plugin glue is still on the stack.
    deferToEventLoop([this] { initialiseModule(); });
}

void PeersUiBackend::initialiseModule()
{
    setChatStatus(PeersUiBackendSimpleSource::Initialising);

    // ChatConfig reaches the module untyped: there is no generated struct for a
    // record in parameter position, so the wire shape IS the contract.
    const QVariantMap config{
        { QStringLiteral("delivery_preset"), QString::fromLatin1(kDefaultDeliveryPreset) },
        { QStringLiteral("log_level"), QString::fromLatin1(kChatLogLevel) },
    };

    const LogosResult res = modules().chat_module.init(config);
    if (!res.success) {
        setChatStatus(PeersUiBackendSimpleSource::Error);
        reportFailure(QStringLiteral("Failed to initialise chat"), res.getError<QString>());
        return;
    }
    m_moduleInitialised = true;

    setLogDir(modules().chat_module.get_log_path());

    // Subscribe BEFORE the first snapshot, so nothing that fires in the gap is
    // dropped (invariant 2 in the header).
    subscribeToEvents();

    refreshMyAddress();
    refreshConversations();
    m_initialSnapshotDone = true;

    // Seed status from the snapshot, in case delivery_state_changed fired
    // during init() before the listener existed.
    const QVariantMap status = modules().chat_module.status().toMap();
    applyDeliveryState(status.value(QStringLiteral("delivery_state")).toString(),
                       status.value(QStringLiteral("detail")).toString());

    startHealthProbe();
}

void PeersUiBackend::subscribeToEvents()
{
    if (m_eventsSubscribed)
        return;
    m_eventsSubscribed = true;

    auto& chat = modules().chat_module;
    chat.on(QStringLiteral("message_received"),
            [this](const QVariantList& a) { applyMessageReceived(a); });
    chat.on(QStringLiteral("message_sent"),
            [this](const QVariantList& a) { applyMessageSent(a); });
    chat.on(QStringLiteral("conversation_created"),
            [this](const QVariantList& a) { applyConversationCreated(a); });
    chat.on(QStringLiteral("conversation_updated"),
            [this](const QVariantList& a) { applyConversationUpdated(a); });
    chat.on(QStringLiteral("members_changed"),
            [this](const QVariantList& a) { applyMembersChanged(a); });
    chat.on(QStringLiteral("conversation_deleted"),
            [this](const QVariantList& a) { applyConversationDeleted(a); });
    chat.on(QStringLiteral("delivery_state_changed"), [this](const QVariantList& a) {
        applyDeliveryState(a.value(0).toString(), a.value(1).toString());
    });
}

void PeersUiBackend::startHealthProbe()
{
    if (m_healthTimer)
        return;
    m_healthTimer = new QTimer(this);
    m_healthTimer->setInterval(kHealthIntervalMs);
    // Until something asks, a module that died is indistinguishable from an idle
    // one, and the app goes on looking connected until the next thing the user
    // does times out.
    connect(m_healthTimer, &QTimer::timeout, this, [this] {
        modules().chat_module.healthAsync([this](bool answered) {
            if (!answered && chatStatus() != PeersUiBackendSimpleSource::Error) {
                setChatStatus(PeersUiBackendSimpleSource::Error);
                report(QStringLiteral("Chat module stopped responding."));
            }
        });
    });
    m_healthTimer->start();
}

// ── refresh ─────────────────────────────────────────────────────────────────

void PeersUiBackend::refreshMyAddress()
{
    if (!m_moduleInitialised)
        return;
    const QString address = modules().chat_module.get_address();
    if (address.isEmpty())
        return;
    setMyAddress(address);
    setMyLabel(shortLabel(address));
}

void PeersUiBackend::refreshConversations()
{
    if (!m_moduleInitialised)
        return;

    const QVariantList convos = modules().chat_module.list_conversations();

    QJsonArray rows;
    for (const QVariant& v : convos) {
        const QVariantMap c = v.toMap();
        const QString convoId = c.value(QStringLiteral("convo_id")).toString();
        const QString kind = c.value(QStringLiteral("kind")).toString();
        const bool isGroup = kind == QLatin1String("group");

        // A group's shared name wins; then the local-only nickname; then the
        // short form of the id. Peers never shows a bare empty row.
        QString display = c.value(QStringLiteral("name")).toString();
        if (display.isEmpty())
            display = c.value(QStringLiteral("nickname")).toString();
        if (display.isEmpty())
            display = shortLabel(convoId);

        // The preview is arbitrary peer-supplied text that may carry a content
        // marker, so render what the marker means rather than its wire form.
        const QString rawPreview = c.value(QStringLiteral("preview")).toString();

        QJsonObject row{
            { QStringLiteral("convoId"), convoId },
            { QStringLiteral("displayName"), display },
            { QStringLiteral("isGroup"), isGroup },
            { QStringLiteral("description"), c.value(QStringLiteral("description")).toString() },
            { QStringLiteral("nickname"), c.value(QStringLiteral("nickname")).toString() },
            { QStringLiteral("messageCount"), c.value(QStringLiteral("message_count")).toInt() },
            { QStringLiteral("lastActivityMs"),
              c.value(QStringLiteral("last_activity_ms")).toLongLong() },
            { QStringLiteral("preview"), ContentMarkers::previewText(rawPreview) },
            // The identicon seed: the peer address for a 1:1, the shared convo
            // id for a group — matching Peers.
            { QStringLiteral("avatarSeed"), convoId },
            { QStringLiteral("avatarKind"),
              isGroup ? QStringLiteral("group") : QStringLiteral("contact") },
        };
        rows.append(row);
    }

    setConversationsJson(QString::fromUtf8(QJsonDocument(rows).toJson(QJsonDocument::Compact)));
}

bool PeersUiBackend::loadMessages(const QString& convoId)
{
    if (!m_moduleInitialised || convoId.isEmpty())
        return false;

    // A failed read comes back as an empty list, so ask for the error too: an
    // empty thread and an unreachable module must not look alike.
    logos::CallError err;
    const QVariantList msgs = modules().chat_module.get_messages(convoId, &err);
    if (!err.ok()) {
        reportFailure(QStringLiteral("Could not load messages"),
                      QString::fromStdString(err.message));
        return false;
    }

    // Two passes. Control markers (reactions, pins) are FOLDED — they must never
    // occupy a bubble — so the first pass collects them and the second attaches
    // them to the message they target. A single pass would miss a reaction that
    // arrives before the message it points at, which happens on catch-up.
    struct Fold {
        QHash<QString, int> counts;       // emoji → count
        QSet<QString> mine;               // emoji this account reacted with
    };
    QHash<QString, Fold> reactions;       // target key → folded reactions
    QString pinnedKey;

    // key → what that message says, so a reply can show the text it QUOTES.
    // The reply1: marker carries only the target key, so without this the quote
    // box would echo the reply's own body — which is exactly the bug a
    // screenshot caught on 2026-08-09.
    QHash<QString, QString> textByKey;
    QHash<QString, QString> senderByKey;

    const QString me = myAddress();

    auto authorOf = [&](const QVariantMap& m) {
        // The key is hashed over (author, raw body); for our own messages the
        // wire carries no sender, so it is this account.
        return m.value(QStringLiteral("from_self")).toBool()
            ? me
            : m.value(QStringLiteral("sender")).toString();
    };

    for (const QVariant& v : msgs) {
        const QVariantMap m = v.toMap();
        const QString content = m.value(QStringLiteral("content")).toString();
        const ContentMarkers::Kind kind = ContentMarkers::classify(content);

        if (!ContentMarkers::isFolded(kind)) {
            // Index every renderable message by its key so replies can resolve
            // the text they quote.
            const QString k = ContentMarkers::messageKey(authorOf(m), content);
            const QString sender = m.value(QStringLiteral("sender")).toString();
            textByKey.insert(k, ContentMarkers::previewText(content));
            senderByKey.insert(k,
                               m.value(QStringLiteral("from_self")).toBool()
                                   ? QStringLiteral("You")
                                   : (sender.isEmpty() ? QStringLiteral("Peer")
                                                       : shortLabel(sender)));
            continue;
        }

        if (kind != ContentMarkers::Kind::Reaction && kind != ContentMarkers::Kind::Pin)
            continue;

        const QJsonObject o = ContentMarkers::decodeToJson(content);
        const QString target = o.value(QStringLiteral("targetKey")).toString();
        if (target.isEmpty())
            continue;

        if (kind == ContentMarkers::Kind::Pin) {
            // Last pin wins; an unpin clears it.
            if (o.value(QStringLiteral("add")).toBool())
                pinnedKey = target;
            else if (pinnedKey == target)
                pinnedKey.clear();
            continue;
        }

        const QString emoji = o.value(QStringLiteral("emoji")).toString();
        if (emoji.isEmpty())
            continue;
        Fold& f = reactions[target];
        if (o.value(QStringLiteral("add")).toBool()) {
            f.counts[emoji] = f.counts.value(emoji) + 1;
            if (m.value(QStringLiteral("from_self")).toBool())
                f.mine.insert(emoji);
        } else {
            const int left = f.counts.value(emoji) - 1;
            if (left > 0)
                f.counts[emoji] = left;
            else
                f.counts.remove(emoji);
            if (m.value(QStringLiteral("from_self")).toBool())
                f.mine.remove(emoji);
        }
    }

    QJsonArray rows;
    QJsonObject pinnedRow;

    for (const QVariant& v : msgs) {
        const QVariantMap m = v.toMap();
        const QString content = m.value(QStringLiteral("content")).toString();
        const ContentMarkers::Kind kind = ContentMarkers::classify(content);
        if (ContentMarkers::isFolded(kind))
            continue;   // control markers never render as a bubble

        const bool fromSelf = m.value(QStringLiteral("from_self")).toBool();
        const QString sender = m.value(QStringLiteral("sender")).toString();

        // Decode once, here — QML never sees a raw marker string.
        QJsonObject row = ContentMarkers::decodeToJson(content);

        // The cross-device identity Peers uses in place of a message id the wire
        // does not carry. Hashed over the RAW body, so a reply's key covers the
        // whole "reply1:…" string, matching Android.
        const QString key = ContentMarkers::messageKey(authorOf(m), content);
        row.insert(QStringLiteral("key"), key);
        row.insert(QStringLiteral("fromSelf"), fromSelf);
        row.insert(QStringLiteral("timestampMs"),
                   m.value(QStringLiteral("timestamp_ms")).toDouble());
        row.insert(QStringLiteral("sender"), sender);
        row.insert(QStringLiteral("senderLabel"),
                   sender.isEmpty() ? QStringLiteral("Peer") : shortLabel(sender));

        // Resolve what a reply quotes. If the quoted message isn't in this
        // conversation's history (deleted, or before our join), say so rather
        // than showing nothing or, worse, the reply's own text.
        if (row.value(QStringLiteral("kind")).toString() == QLatin1String("reply")) {
            const QString target = row.value(QStringLiteral("replyToKey")).toString();
            row.insert(QStringLiteral("quotedText"),
                       textByKey.value(target, QStringLiteral("Original message unavailable")));
            row.insert(QStringLiteral("quotedSender"), senderByKey.value(target));
        }

        if (reactions.contains(key)) {
            const Fold& f = reactions.value(key);
            QJsonArray pills;
            for (auto it = f.counts.begin(); it != f.counts.end(); ++it) {
                pills.append(QJsonObject{
                    { QStringLiteral("emoji"), it.key() },
                    { QStringLiteral("count"), it.value() },
                    { QStringLiteral("mine"), f.mine.contains(it.key()) },
                });
            }
            if (!pills.isEmpty())
                row.insert(QStringLiteral("reactions"), pills);
        }

        if (!pinnedKey.isEmpty() && key == pinnedKey) {
            row.insert(QStringLiteral("pinned"), true);
            pinnedRow = row;
        }

        rows.append(row);
    }

    setMessagesJson(QString::fromUtf8(QJsonDocument(rows).toJson(QJsonDocument::Compact)));
    setCurrentPinnedJson(
        QString::fromUtf8(QJsonDocument(pinnedRow).toJson(QJsonDocument::Compact)));
    return true;
}

void PeersUiBackend::syncCurrentConversationMeta()
{
    const QString id = currentConversationId();
    if (id.isEmpty()) {
        setCurrentIsGroup(false);
        setCurrentDisplayName(QString());
        setCurrentDescription(QString());
        setCurrentPeerAddress(QString());
        setMemberCount(0);
        setPendingMemberCount(0);
        setMembersJson(QStringLiteral("[]"));
        setCurrentPinnedJson(QStringLiteral("{}"));
        return;
    }

    // Read the row we already hold rather than re-querying the core.
    const QJsonArray convos =
        QJsonDocument::fromJson(conversationsJson().toUtf8()).array();
    for (const QJsonValue& v : convos) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("convoId")).toString() != id)
            continue;
        setCurrentIsGroup(o.value(QStringLiteral("isGroup")).toBool());
        QString name = o.value(QStringLiteral("displayName")).toString();
        setCurrentDisplayName(name);
        setCurrentDescription(o.value(QStringLiteral("description")).toString());
        break;
    }

    setCurrentDraft(m_drafts.value(id));
    setCurrentPinnedJson(
        QString::fromUtf8(QJsonDocument(m_pinnedByConvo.value(id).toObject()).toJson(
            QJsonDocument::Compact)));

    refreshMembers();
}

// ── conversations & messages ────────────────────────────────────────────────

void PeersUiBackend::selectConversation(QString conversationId)
{
    setCurrentConversationId(conversationId);
    setLoadedConversationId(QString()); // the view shows "loading", not stale rows
    setMessagesJson(QStringLiteral("[]"));

    if (conversationId.isEmpty()) {
        syncCurrentConversationMeta();
        return;
    }
    if (loadMessages(conversationId))
        setLoadedConversationId(conversationId);
    syncCurrentConversationMeta();
}

void PeersUiBackend::createConversation(QString peerAddress)
{
    const QString addr = peerAddress.trimmed();
    if (addr.isEmpty()) {
        report(QStringLiteral("Enter a peer address to start a conversation."));
        return;
    }
    if (addr == myAddress()) {
        report(QStringLiteral("That is your own address."));
        return;
    }
    const LogosResult res = modules().chat_module.create_conversation(addr);
    if (!res.success)
        reportFailure(QStringLiteral("Could not start the conversation"), res.getError<QString>());
}

void PeersUiBackend::sendMessage(QString conversationId, QString content)
{
    if (conversationId.isEmpty() || content.isEmpty())
        return;
    const LogosResult res = modules().chat_module.send_message(conversationId, content);
    if (!res.success) {
        reportFailure(QStringLiteral("Message not sent"), res.getError<QString>());
        // Hand the text back so the composer can restore it.
        Q_EMIT sendFailed(conversationId, content);
        return;
    }
    m_drafts.remove(conversationId);
    if (conversationId == currentConversationId())
        setCurrentDraft(QString());
    saveState();
}

void PeersUiBackend::retryMessage(QString conversationId, QString localId)
{
    Q_UNUSED(localId)
    Q_UNUSED(conversationId)
    // A failed send never reached the core, so there is nothing queued to retry:
    // the composer holds the text (see sendFailed) and re-sending is a normal
    // sendMessage. Wired as a no-op rather than pretending to have a queue.
    reportUnimplemented(QStringLiteral("retryMessage (the composer re-sends instead)"));
}

void PeersUiBackend::deleteConversation(QString conversationId)
{
    if (conversationId.isEmpty())
        return;
    const LogosResult res = modules().chat_module.delete_conversation(conversationId);
    if (!res.success) {
        reportFailure(QStringLiteral("Could not delete the conversation"),
                      res.getError<QString>());
        return;
    }
    if (currentConversationId() == conversationId)
        selectConversation(QString());
}

void PeersUiBackend::setConversationNickname(QString conversationId, QString nickname)
{
    const LogosResult res =
        modules().chat_module.set_conversation_nickname(conversationId, nickname);
    if (!res.success)
        reportFailure(QStringLiteral("Could not rename the conversation"),
                      res.getError<QString>());
    else
        deferToEventLoop([this] { refreshConversations(); });
}

void PeersUiBackend::setDraft(QString conversationId, QString text)
{
    if (conversationId.isEmpty())
        return;
    if (text.isEmpty())
        m_drafts.remove(conversationId);
    else
        m_drafts.insert(conversationId, text);
    if (conversationId == currentConversationId())
        setCurrentDraft(text);
    saveState();
}

// ── events ──────────────────────────────────────────────────────────────────
//
// Every handler below defers its module reads: it is running inside the
// replica's read handler (invariant 1).

void PeersUiBackend::applyMessageReceived(const QVariantList& a)
{
    const QString convoId = a.value(0).toString();
    deferToEventLoop([this, convoId] {
        refreshConversations();
        if (convoId == currentConversationId() && loadMessages(convoId))
            setLoadedConversationId(convoId);
    });
}

void PeersUiBackend::applyMessageSent(const QVariantList& a)
{
    const QString convoId = a.value(0).toString();
    deferToEventLoop([this, convoId] {
        refreshConversations();
        if (convoId == currentConversationId() && loadMessages(convoId))
            setLoadedConversationId(convoId);
    });
}

void PeersUiBackend::applyConversationCreated(const QVariantList& a)
{
    // conversation_created(convo_id, is_outgoing, peer_label, kind, name, desc)
    const QString convoId = a.value(0).toString();
    const bool isOutgoing = a.value(1).toBool();

    deferToEventLoop([this, convoId, isOutgoing] {
        refreshConversations();
        // A conversation this installation started should open, the way it does
        // on Android — the user asked for it, so putting them in it is the
        // expected behaviour rather than leaving them on an empty pane.
        // An INCOMING conversation must not steal the current selection.
        if (isOutgoing && !convoId.isEmpty() && currentConversationId().isEmpty())
            selectConversation(convoId);
    });
}

void PeersUiBackend::applyConversationUpdated(const QVariantList& a)
{
    Q_UNUSED(a)
    deferToEventLoop([this] { refreshConversations(); });
}

void PeersUiBackend::applyMembersChanged(const QVariantList& a)
{
    const QString convoId = a.value(0).toString();
    deferToEventLoop([this, convoId] {
        if (convoId == currentConversationId())
            refreshMembers();
    });
}

void PeersUiBackend::applyConversationDeleted(const QVariantList& a)
{
    const QString convoId = a.value(0).toString();
    deferToEventLoop([this, convoId] {
        refreshConversations();
        if (convoId == currentConversationId())
            selectConversation(QString());
    });
}

void PeersUiBackend::applyDeliveryState(const QString& state, const QString& detail)
{
    setStatusDetail(detail);

    const bool online = state.compare(QLatin1String("online"), Qt::CaseInsensitive) == 0
        || state.compare(QLatin1String("connected"), Qt::CaseInsensitive) == 0;

    if (online) {
        const bool wasOffline = chatStatus() != PeersUiBackendSimpleSource::Online;
        setChatStatus(PeersUiBackendSimpleSource::Online);
        // Coming online is when a snapshot taken while offline becomes wrong.
        if (wasOffline && m_initialSnapshotDone) {
            deferToEventLoop([this] {
                refreshMyAddress();
                refreshConversations();
                const QString id = currentConversationId();
                if (!id.isEmpty() && loadMessages(id))
                    setLoadedConversationId(id);
            });
        }
    } else if (m_moduleInitialised) {
        setChatStatus(PeersUiBackendSimpleSource::Initialising);
    }
}

// ── groups ──────────────────────────────────────────────────────────────────

void PeersUiBackend::createGroupConversation(QString name, QString description)
{
    const LogosResult res =
        modules().chat_module.create_group_conversation(name.trimmed(), description.trimmed());
    if (!res.success)
        reportFailure(QStringLiteral("Could not create the group"), res.getError<QString>());
}

void PeersUiBackend::addGroupMember(QString conversationId, QString peerAddress)
{
    const QString addr = peerAddress.trimmed();
    if (conversationId.isEmpty() || addr.isEmpty())
        return;
    const LogosResult res = modules().chat_module.add_group_member(conversationId, addr);
    if (!res.success)
        reportFailure(QStringLiteral("Could not add the member"), res.getError<QString>());
}

void PeersUiBackend::refreshMembers()
{
    const QString convoId = currentConversationId();
    if (!m_moduleInitialised || convoId.isEmpty()) {
        setMembersJson(QStringLiteral("[]"));
        setMemberCount(0);
        setPendingMemberCount(0);
        return;
    }

    const QVariantList members = modules().chat_module.list_group_members(convoId);

    QJsonArray rows;
    int committed = 0;
    int pendingCount = 0;
    QString peerAddress;

    for (const QVariant& v : members) {
        const QVariantMap m = v.toMap();
        const QString address = m.value(QStringLiteral("address")).toString();
        const bool pending = m.value(QStringLiteral("pending")).toBool();
        const bool isSelf = !address.isEmpty() && address == myAddress();

        if (pending)
            ++pendingCount;
        else
            ++committed;

        // An empty address is the roster's "no confirmed account" signal. Keep
        // the row — it is a real participant — and let the view render it as an
        // unknown account rather than dropping a member silently.
        rows.append(QJsonObject{
            { QStringLiteral("address"), address },
            { QStringLiteral("label"),
              address.isEmpty() ? QStringLiteral("unknown account") : shortLabel(address) },
            { QStringLiteral("isSelf"), isSelf },
            { QStringLiteral("pending"), pending },
            { QStringLiteral("avatarSeed"), address },
        });

        if (!currentIsGroup() && !isSelf && !address.isEmpty())
            peerAddress = address;
    }

    setMembersJson(QString::fromUtf8(QJsonDocument(rows).toJson(QJsonDocument::Compact)));
    setMemberCount(committed);
    setPendingMemberCount(pendingCount);
    setCurrentPeerAddress(peerAddress);
}

void PeersUiBackend::leaveGroup(QString conversationId)
{
    // chat_module 0.2.2 has no leave/remove primitive: the contract offers only
    // delete_conversation, which is LOCAL. Say so rather than implying the group
    // was told. Tracked in docs/PARITY.md.
    Q_UNUSED(conversationId)
    reportUnimplemented(
        QStringLiteral("leaving a group remotely — the core has no leave primitive; "
                       "deleting removes it locally only"));
}

// ── everything still to be wired ────────────────────────────────────────────
//
// These exist in the contract so the QML surface is stable, and report honestly
// rather than failing silently. Each is tracked by an open issue and listed as
// unimplemented in docs/PARITY.md.

void PeersUiBackend::sendReply(QString conversationId, QString content, QString replyToId)
{
    if (conversationId.isEmpty() || content.isEmpty())
        return;
    if (replyToId.isEmpty()) {
        // Nothing to quote — a plain message is the honest fallback rather than
        // emitting a malformed reply1: the peer would render as "[unreadable]".
        sendMessage(conversationId, content);
        return;
    }
    sendMessage(conversationId, ContentMarkers::encodeReply(replyToId, content));
}
void PeersUiBackend::forwardMessage(QString a, QString b, QString c)
{
    Q_UNUSED(a) Q_UNUSED(b) Q_UNUSED(c)
    reportUnimplemented(QStringLiteral("forward"));
}
void PeersUiBackend::reactToMessage(QString conversationId, QString messageId, QString emoji)
{
    if (conversationId.isEmpty() || messageId.isEmpty() || emoji.isEmpty())
        return;
    // A reaction is a folded control message: it is sent like any other body and
    // never renders as a bubble on either side.
    sendMessage(conversationId, ContentMarkers::encodeReaction(true, emoji, messageId));
}

void PeersUiBackend::unreactToMessage(QString conversationId, QString messageId, QString emoji)
{
    if (conversationId.isEmpty() || messageId.isEmpty() || emoji.isEmpty())
        return;
    sendMessage(conversationId, ContentMarkers::encodeReaction(false, emoji, messageId));
}

void PeersUiBackend::pinMessage(QString conversationId, QString messageId)
{
    if (conversationId.isEmpty() || messageId.isEmpty())
        return;
    sendMessage(conversationId, ContentMarkers::encodePin(true, messageId));
}

void PeersUiBackend::unpinMessage(QString conversationId)
{
    if (conversationId.isEmpty())
        return;
    // Unpin targets whatever is currently pinned in this conversation.
    const QJsonObject pinned =
        QJsonDocument::fromJson(currentPinnedJson().toUtf8()).object();
    const QString key = pinned.value(QStringLiteral("key")).toString();
    if (key.isEmpty()) {
        report(QStringLiteral("Nothing is pinned in this conversation."));
        return;
    }
    sendMessage(conversationId, ContentMarkers::encodePin(false, key));
}
void PeersUiBackend::deleteMessageForMe(QString a, QString b)
{
    Q_UNUSED(a) Q_UNUSED(b)
    reportUnimplemented(QStringLiteral("delete for me"));
}
void PeersUiBackend::copyToClipboard(QString text)
{
    Q_UNUSED(text)
    // The clipboard belongs to the view process; QML copies directly.
    reportUnimplemented(QStringLiteral("clipboard from the backend (QML copies directly)"));
}
void PeersUiBackend::sendMedia(QString a, QString b, QString c)
{
    Q_UNUSED(a) Q_UNUSED(b) Q_UNUSED(c)
    reportUnimplemented(QStringLiteral("sending media"));
}
void PeersUiBackend::saveMedia(QString a, QString b)
{
    Q_UNUSED(a) Q_UNUSED(b)
    reportUnimplemented(QStringLiteral("saving media"));
}
void PeersUiBackend::startRecording() { reportUnimplemented(QStringLiteral("voice notes")); }
void PeersUiBackend::cancelRecording() { reportUnimplemented(QStringLiteral("voice notes")); }
void PeersUiBackend::sendRecording(QString a)
{
    Q_UNUSED(a)
    reportUnimplemented(QStringLiteral("voice notes"));
}
void PeersUiBackend::refreshContacts()
{
    QJsonArray rows;
    for (auto it = m_contacts.begin(); it != m_contacts.end(); ++it) {
        QJsonObject o = it.value().toObject();
        o.insert(QStringLiteral("address"), it.key());
        if (!o.contains(QStringLiteral("label")))
            o.insert(QStringLiteral("label"), shortLabel(it.key()));
        rows.append(o);
    }
    setContactsJson(QString::fromUtf8(QJsonDocument(rows).toJson(QJsonDocument::Compact)));
}
void PeersUiBackend::setContactLabel(QString address, QString label)
{
    if (address.isEmpty())
        return;
    QJsonObject o = m_contacts.value(address).toObject();
    o.insert(QStringLiteral("label"), label);
    m_contacts.insert(address, o);
    saveState();
    refreshContacts();
}
void PeersUiBackend::removeContact(QString address)
{
    m_contacts.remove(address);
    saveState();
    refreshContacts();
}
void PeersUiBackend::sendContactCard(QString conversationId, QString address)
{
    if (conversationId.isEmpty() || address.isEmpty())
        return;
    const QString label =
        m_contacts.value(address).toObject().value(QStringLiteral("label")).toString();
    sendMessage(conversationId, ContentMarkers::encodeContactCard(address, label));
}
void PeersUiBackend::setDisplayName(QString name)
{
    setMyDisplayName(name);
    m_settings.insert(QStringLiteral("displayName"), name);
    saveState();
    const LogosResult res = modules().chat_module.set_installation_name(name);
    if (!res.success)
        reportFailure(QStringLiteral("Could not set the display name"), res.getError<QString>());
}
void PeersUiBackend::setAvatar(QString localPath)
{
    Q_UNUSED(localPath)
    reportUnimplemented(QStringLiteral("custom avatars"));
}
void PeersUiBackend::decodeQrFromFile(QString localPath)
{
    Q_UNUSED(localPath)
    reportUnimplemented(QStringLiteral("QR scanning"));
}
void PeersUiBackend::setSetting(QString key, QString jsonValue)
{
    const QJsonDocument d = QJsonDocument::fromJson(QStringLiteral("[%1]").arg(jsonValue).toUtf8());
    if (d.isNull() || !d.isArray() || d.array().isEmpty()) {
        report(QStringLiteral("Could not read that setting value."));
        return;
    }
    m_settings.insert(key, d.array().at(0));
    saveState();
    setSettingsJson(QString::fromUtf8(QJsonDocument(m_settings).toJson(QJsonDocument::Compact)));
}
void PeersUiBackend::setPin(QString pin)
{
    Q_UNUSED(pin)
    reportUnimplemented(QStringLiteral("PIN app-lock"));
}
void PeersUiBackend::setDuressPin(QString pin)
{
    Q_UNUSED(pin)
    reportUnimplemented(QStringLiteral("the duress PIN"));
}
void PeersUiBackend::clearPin(QString currentPin)
{
    Q_UNUSED(currentPin)
    reportUnimplemented(QStringLiteral("PIN app-lock"));
}
void PeersUiBackend::unlock(QString pin)
{
    Q_UNUSED(pin)
    reportUnimplemented(QStringLiteral("PIN app-lock"));
}
void PeersUiBackend::lock() { reportUnimplemented(QStringLiteral("PIN app-lock")); }
void PeersUiBackend::resetIdentityAndData()
{
    reportUnimplemented(QStringLiteral("reset identity and data"));
}
void PeersUiBackend::openBackup(QString localPath, QString passphrase)
{
    Q_UNUSED(localPath) Q_UNUSED(passphrase)
    // The decryptor lands with its tests; adopting the identity is upstream
    // blocked (ADR 0004).
    Q_EMIT backupFailed(QStringLiteral("Reading a Peers backup is not wired up yet."));
}
void PeersUiBackend::exportBackup(QString destPath, QString passphrase)
{
    Q_UNUSED(destPath) Q_UNUSED(passphrase)
    reportUnimplemented(QStringLiteral("backup export"));
}

// ── plumbing ────────────────────────────────────────────────────────────────

void PeersUiBackend::deferToEventLoop(std::function<void()> work)
{
    QTimer::singleShot(0, this, [work = std::move(work)]() { work(); });
}

void PeersUiBackend::report(const QString& message)
{
    QVariantList list = errors();
    QVariantMap entry{
        { QStringLiteral("when"), QDateTime::currentDateTime().toString(Qt::ISODate) },
        { QStringLiteral("message"), message },
        { QStringLiteral("count"), 1 },
    };
    // Collapse an immediate repeat rather than flooding the strip.
    if (!list.isEmpty()
        && list.first().toMap().value(QStringLiteral("message")).toString() == message) {
        QVariantMap first = list.first().toMap();
        first[QStringLiteral("count")] = first.value(QStringLiteral("count")).toInt() + 1;
        list[0] = first;
    } else {
        list.prepend(entry);
        while (list.size() > kMaxRetainedErrors)
            list.removeLast();
    }
    setErrors(list);
    Q_EMIT error(message);
}

void PeersUiBackend::reportFailure(const QString& action, const QString& reason)
{
    // An empty reason gets words of its own rather than a dangling separator:
    // it is what a call that never reached the module leaves behind, which is
    // the worst moment to say least.
    report(reason.isEmpty() ? QStringLiteral("%1 — the chat module did not answer.").arg(action)
                            : QStringLiteral("%1 — %2").arg(action, reason));
}

void PeersUiBackend::reportUnimplemented(const QString& what)
{
    report(QStringLiteral("Not available yet: %1.").arg(what));
}

// ── local state ─────────────────────────────────────────────────────────────

QString PeersUiBackend::settingsPath() const
{
    // Beside the chat module's instance directory when the host assigned one,
    // so a wipe takes this with it.
    const QString dir = logDir().isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        : QFileInfo(logDir()).absolutePath();
    QDir().mkpath(dir);
    return QDir(dir).filePath(QStringLiteral("peers-ui-state.json"));
}

void PeersUiBackend::loadState()
{
    QFile f(settingsPath());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();

    m_settings = root.value(QStringLiteral("settings")).toObject();
    m_contacts = root.value(QStringLiteral("contacts")).toObject();
    m_pinnedByConvo = root.value(QStringLiteral("pinned")).toObject();

    const QJsonObject drafts = root.value(QStringLiteral("drafts")).toObject();
    for (auto it = drafts.begin(); it != drafts.end(); ++it)
        m_drafts.insert(it.key(), it.value().toString());

    setMyDisplayName(m_settings.value(QStringLiteral("displayName")).toString());
    setSettingsJson(QString::fromUtf8(QJsonDocument(m_settings).toJson(QJsonDocument::Compact)));
}

void PeersUiBackend::saveState()
{
    QJsonObject drafts;
    for (auto it = m_drafts.begin(); it != m_drafts.end(); ++it)
        drafts.insert(it.key(), it.value());

    const QJsonObject root{
        { QStringLiteral("settings"), m_settings },
        { QStringLiteral("contacts"), m_contacts },
        { QStringLiteral("pinned"), m_pinnedByConvo },
        { QStringLiteral("drafts"), drafts },
    };

    QFile f(settingsPath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}
