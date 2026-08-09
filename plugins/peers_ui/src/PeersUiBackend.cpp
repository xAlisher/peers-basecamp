#include "PeersUiBackend.h"

// Generated umbrella: LogosModules (behind modules()) built from
// metadata.json#dependencies — the Qt-typed peers_core wrapper, LogosResult
// and logos::CallError all live here.
#include "logos_sdk.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QSet>
#include <QTimer>

#include "BackupReader.h"
#include "StorageClient.h"
#include "VoiceRecorder.h"
#include "ContentMarkers.h"

namespace {

// Empty means "logos.test", per ChatConfig in chat_module.lidl. Named
// explicitly so the choice is visible rather than implied by a default.
constexpr const char* kDefaultDeliveryPreset = "logos.test";
constexpr const char* kChatLogLevel = "info";

// The delivery entry node Peers Android pins by default
// (src/stores/deliveryNode.ts: DEFAULT_DELIVERY_NODE). Entering the cluster
// through the SAME node as the phone is what makes desktop<->phone delivery
// prompt rather than waiting on gossip to find its way across cluster 2.
//
// Pinning switches peers_core to delivery's FLAT config shape, whose listening
// ports are FIXED — so two PINNED instances cannot share a host. The
// two-instance tests therefore set PEERS_DELIVERY_NODE="" and get the layered
// shape with OS-assigned ports.
//
// Set PEERS_DELIVERY_NODE to override, or empty to use the preset's own nodes.
constexpr const char* kDefaultDeliveryNode =
    "/dns4/msg.logos.live/tcp/30304/p2p/"
    "16Uiu2HAmNdX1s7wRhygyWKmYiUst84329TSz3byLEP6FjcoxDbH4";

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
        modules().peers_core.shutdown();
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
    const QByteArray nodeEnv = qgetenv("PEERS_DELIVERY_NODE");
    const QString deliveryNode = nodeEnv.isNull()
        ? QString::fromLatin1(kDefaultDeliveryNode)
        : QString::fromUtf8(nodeEnv);   // set-but-empty deliberately means "use the preset"

    const QVariantMap config{
        { QStringLiteral("delivery_preset"), QString::fromLatin1(kDefaultDeliveryPreset) },
        { QStringLiteral("delivery_node"), deliveryNode },
        { QStringLiteral("log_level"), QString::fromLatin1(kChatLogLevel) },
    };
    if (!deliveryNode.isEmpty())
        setStatusDetail(QStringLiteral("pinning %1").arg(deliveryNode.section('/', 2, 2)));

    const LogosResult res = modules().peers_core.init(config);
    if (!res.success) {
        setChatStatus(PeersUiBackendSimpleSource::Error);
        reportFailure(QStringLiteral("Failed to initialise chat"), res.getError<QString>());
        return;
    }
    m_moduleInitialised = true;

    setLogDir(modules().peers_core.get_log_path());

    // Subscribe BEFORE the first snapshot, so nothing that fires in the gap is
    // dropped (invariant 2 in the header).
    subscribeToEvents();

    refreshMyAddress();
    refreshConversations();
    m_initialSnapshotDone = true;

    // Seed status from the snapshot, in case delivery_state_changed fired
    // during init() before the listener existed.
    const QVariantMap status = modules().peers_core.status().toMap();
    applyDeliveryState(status.value(QStringLiteral("delivery_state")).toString(),
                       status.value(QStringLiteral("detail")).toString());

    startHealthProbe();
}

void PeersUiBackend::subscribeToEvents()
{
    if (m_eventsSubscribed)
        return;
    m_eventsSubscribed = true;

    auto& chat = modules().peers_core;
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
        modules().peers_core.healthAsync([this](bool answered) {
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
    const QString address = modules().peers_core.get_address();
    if (address.isEmpty())
        return;
    setMyAddress(address);
    setMyLabel(shortLabel(address));
}

void PeersUiBackend::refreshConversations()
{
    if (!m_moduleInitialised)
        return;

    const QVariantList convos = modules().peers_core.list_conversations();

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
        //
        // chat_module's preview is simply the LAST message, so after a reaction
        // or pin it is a folded control marker with no display text and the row
        // would go blank. Keep the last renderable preview instead — Android
        // shows the last renderable message for the same reason.
        const QString rawPreview = c.value(QStringLiteral("preview")).toString();
        QString preview = ContentMarkers::previewText(rawPreview);
        if (preview.isEmpty())
            preview = m_lastPreview.value(convoId);
        else
            m_lastPreview.insert(convoId, preview);

        QJsonObject row{
            { QStringLiteral("convoId"), convoId },
            { QStringLiteral("displayName"), display },
            { QStringLiteral("isGroup"), isGroup },
            { QStringLiteral("description"), c.value(QStringLiteral("description")).toString() },
            { QStringLiteral("nickname"), c.value(QStringLiteral("nickname")).toString() },
            { QStringLiteral("messageCount"), c.value(QStringLiteral("message_count")).toInt() },
            { QStringLiteral("lastActivityMs"),
              c.value(QStringLiteral("last_activity_ms")).toLongLong() },
            { QStringLiteral("preview"), preview },
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
    const QVariantList msgs = modules().peers_core.get_messages(convoId, &err);
    if (!err.ok()) {
        reportFailure(QStringLiteral("Could not load messages"),
                      QString::fromStdString(err.message));
        return false;
    }

    // Two passes. Control markers (reactions, pins) are FOLDED — they must never
    // occupy a bubble — so the first pass collects them and the second attaches
    // them to the message they target. A single pass would miss a reaction that
    // arrives before the message it points at, which happens on catch-up.
    // Android folds reactions as a SET OF REACTORS per emoji (reactions.ts:70-114):
    // count = set.size, so the same person reacting twice still counts once, and
    // a '-' removes that reactor. Incrementing a counter instead double-counts.
    struct Fold {
        QHash<QString, QSet<QString>> reactors;   // emoji → set of reactor ids
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
                                                       : displayFor(sender)));
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
        // Who reacted: this account for our own, else the sender's address.
        const QString reactor = m.value(QStringLiteral("from_self")).toBool()
            ? me
            : m.value(QStringLiteral("sender")).toString();

        Fold& f = reactions[target];
        if (o.value(QStringLiteral("add")).toBool()) {
            f.reactors[emoji].insert(reactor);
        } else {
            f.reactors[emoji].remove(reactor);
            if (f.reactors.value(emoji).isEmpty())
                f.reactors.remove(emoji);
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

        // Hidden by "delete for me" — local only, Peers has no remote unsend.
        if (m_hiddenKeys.contains(key))
            continue;

        // Keep the RAW body so an action can work on what was actually sent.
        m_rawByKey.insert(key, content);

        row.insert(QStringLiteral("key"), key);
        // The RAW body, for actions that must act on what was sent rather than
        // on the rendered text (Android's "Copy message" copies this). Omitted
        // for inline payloads, which would put megabytes of base64 into the
        // view-model for no benefit — Android excludes those from copy anyway.
        if (kind != ContentMarkers::Kind::InlinePhoto && kind != ContentMarkers::Kind::VoiceNote)
            row.insert(QStringLiteral("raw"), content);
        row.insert(QStringLiteral("fromSelf"), fromSelf);
        row.insert(QStringLiteral("timestampMs"),
                   m.value(QStringLiteral("timestamp_ms")).toDouble());
        row.insert(QStringLiteral("sender"), sender);
        row.insert(QStringLiteral("senderLabel"),
                   sender.isEmpty() ? QStringLiteral("Peer") : displayFor(sender));
        // The short hex, always, alongside the label. Android's attribution line
        // shows BOTH — the name you gave someone and the identity it stands for
        // — so a friendly label can never quietly stand in for the wrong account.
        row.insert(QStringLiteral("senderHex"),
                   sender.isEmpty() ? QString() : shortLabel(sender));

        // Hosted media: hand the view a local file once we have it, and start
        // the fetch when we do not. The decryption key never reaches QML.
        if (row.value(QStringLiteral("kind")).toString() == QLatin1String("media")) {
            const QString cid = row.value(QStringLiteral("cid")).toString();
            const QStringList mf = content.mid(content.indexOf(QLatin1Char(':')) + 1)
                                       .split(QLatin1Char(':'));
            const QString keyB64 = mf.value(1);
            const QString mmime = mf.value(2);
            const QString mcap = mf.value(5);
            if (m_mediaPaths.contains(cid)) {
                row.insert(QStringLiteral("localPath"), m_mediaPaths.value(cid));
                row.insert(QStringLiteral("dataUri"),
                           QStringLiteral("file://") + m_mediaPaths.value(cid));
            } else if (!cid.isEmpty()) {
                const QString c = convoId;
                deferToEventLoop([this, c, cid, keyB64, mcap, mmime] {
                    fetchHostedMedia(c, cid, keyB64, mcap, mmime);
                });
            }
        }

        // A voice note arrives inline as base64. The host has no QtMultimedia, so
        // playback means handing a real file to the desktop's own player —
        // materialise it once, in the cache, keyed by the message identity.
        if (row.value(QStringLiteral("kind")).toString() == QLatin1String("voice")
            && row.value(QStringLiteral("hasData")).toBool()) {
            const QString cached = m_mediaPaths.value(key);
            if (!cached.isEmpty() && QFile::exists(cached)) {
                row.insert(QStringLiteral("localPath"), cached);
            } else {
                const QByteArray audio = ContentMarkers::inlinePayloadBytes(content);
                if (!audio.isEmpty()) {
                    const QString mime = row.value(QStringLiteral("mime")).toString();
                    const QString ext = mime.contains(QLatin1String("wav"))
                        ? QStringLiteral("wav")
                        : (mime.contains(QLatin1String("mpeg")) ? QStringLiteral("mp3")
                                                                : QStringLiteral("m4a"));
                    const QString dir =
                        QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
                    QDir().mkpath(dir);
                    const QString path =
                        QDir(dir).filePath(QStringLiteral("voice-%1.%2").arg(key, ext));
                    QFile out(path);
                    if (out.open(QIODevice::WriteOnly)) {
                        out.write(audio);
                        out.close();
                        m_mediaPaths.insert(key, path);
                        row.insert(QStringLiteral("localPath"), path);
                    }
                }
            }
        }

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
            for (auto it = f.reactors.begin(); it != f.reactors.end(); ++it) {
                QJsonArray who;
                for (const QString& r : it.value())
                    who.append(r.isEmpty() ? QStringLiteral("unknown") : displayFor(r));
                pills.append(QJsonObject{
                    { QStringLiteral("emoji"), it.key() },
                    { QStringLiteral("count"), it.value().size() },
                    { QStringLiteral("mine"), it.value().contains(me) },
                    { QStringLiteral("who"), who },   // long-press shows who reacted
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
    const LogosResult res = modules().peers_core.create_conversation(addr);
    if (!res.success)
        reportFailure(QStringLiteral("Could not start the conversation"), res.getError<QString>());
}

void PeersUiBackend::sendMessage(QString conversationId, QString content)
{
    if (conversationId.isEmpty() || content.isEmpty())
        return;
    const LogosResult res = modules().peers_core.send_message(conversationId, content);
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
    const LogosResult res = modules().peers_core.delete_conversation(conversationId);
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
        modules().peers_core.set_conversation_nickname(conversationId, nickname);
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
        modules().peers_core.create_group_conversation(name.trimmed(), description.trimmed());
    if (!res.success)
        reportFailure(QStringLiteral("Could not create the group"), res.getError<QString>());
}

void PeersUiBackend::addGroupMember(QString conversationId, QString peerAddress)
{
    const QString addr = peerAddress.trimmed();
    if (conversationId.isEmpty() || addr.isEmpty())
        return;
    const LogosResult res = modules().peers_core.add_group_member(conversationId, addr);
    if (!res.success) {
        reportFailure(QStringLiteral("Could not add the member"), res.getError<QString>());
        return;
    }

    // The invite is committed and delivered asynchronously, and members_changed
    // only fires once the group COMMITS it. Without a nudge here the pending
    // window is never seen and the roster jumps straight to committed, so the
    // user gets no feedback that the invite is in flight.
    if (conversationId == currentConversationId()) {
        deferToEventLoop([this] { refreshMembers(); });
        for (int delayMs : { 500, 2000, 5000 }) {
            QTimer::singleShot(delayMs, this, [this, conversationId] {
                if (conversationId == currentConversationId())
                    refreshMembers();
            });
        }
    }
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

    const QVariantList members = modules().peers_core.list_group_members(convoId);

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
              address.isEmpty() ? QStringLiteral("unknown account") : displayFor(address) },
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
void PeersUiBackend::forwardMessage(QString fromConversationId, QString messageId,
                                    QString toConversationId)
{
    Q_UNUSED(fromConversationId)
    if (messageId.isEmpty() || toConversationId.isEmpty())
        return;
    // Forward the RAW body, so a photo forwards as a photo and a hosted-media
    // reference stays fetchable rather than becoming its display text. A reply
    // is deliberately unwrapped: its quote key means nothing in another thread.
    QString raw = m_rawByKey.value(messageId);
    if (raw.isEmpty()) {
        report(QStringLiteral("That message is no longer loaded, so it cannot be forwarded."));
        return;
    }
    if (ContentMarkers::classify(raw) == ContentMarkers::Kind::Reply) {
        const int sep = raw.indexOf(QLatin1Char(':'), QStringLiteral("reply1:").size());
        raw = sep < 0 ? raw : raw.mid(sep + 1);
    }
    sendMessage(toConversationId, raw);
    Q_EMIT toast(QStringLiteral("Forwarded"));
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
void PeersUiBackend::deleteMessageForMe(QString conversationId, QString messageId)
{
    if (messageId.isEmpty())
        return;
    // LOCAL ONLY. Peers has no remote unsend, and the UI must say so rather than
    // implying the peer's copy went anywhere.
    m_hiddenKeys.insert(messageId, true);
    saveState();
    if (conversationId == currentConversationId())
        loadMessages(conversationId);
    Q_EMIT toast(QStringLiteral("Deleted for you"));
}
void PeersUiBackend::copyToClipboard(QString text)
{
    // The clipboard lives in the view process, so QML does the actual copy; this
    // exists so a caller can ask for the RAW body of a message by key (what
    // Android's "Copy message" copies) rather than its display text.
    Q_UNUSED(text)
    Q_EMIT toast(QStringLiteral("Copied"));
}
void PeersUiBackend::sendMedia(QString conversationId, QString localPath, QString kind)
{
    if (conversationId.isEmpty() || localPath.isEmpty())
        return;

    // A plain filesystem path, never a file:// URL — QML must convert with
    // url.toLocalFile() before calling this.
    QFileInfo info(localPath);
    if (!info.exists() || !info.isFile()) {
        report(QStringLiteral("That file does not exist: %1").arg(info.fileName()));
        return;
    }

    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly)) {
        report(QStringLiteral("Could not read %1").arg(info.fileName()));
        return;
    }
    const QByteArray bytes = f.readAll();
    f.close();

    // Videos and audio must carry their real type: the receiver picks a player
    // from the mime, and calling an mp4 "image/png" makes it unplayable on both
    // ends. Anything unrecognised travels as a generic blob rather than being
    // mislabelled as an image.
    const QString suffix = info.suffix().toLower();
    static const QHash<QString, QString> kMimes = {
        {QStringLiteral("png"), QStringLiteral("image/png")},
        {QStringLiteral("jpg"), QStringLiteral("image/jpeg")},
        {QStringLiteral("jpeg"), QStringLiteral("image/jpeg")},
        {QStringLiteral("gif"), QStringLiteral("image/gif")},
        {QStringLiteral("webp"), QStringLiteral("image/webp")},
        {QStringLiteral("bmp"), QStringLiteral("image/bmp")},
        {QStringLiteral("mp4"), QStringLiteral("video/mp4")},
        {QStringLiteral("m4v"), QStringLiteral("video/mp4")},
        {QStringLiteral("mov"), QStringLiteral("video/quicktime")},
        {QStringLiteral("webm"), QStringLiteral("video/webm")},
        {QStringLiteral("mkv"), QStringLiteral("video/x-matroska")},
        {QStringLiteral("3gp"), QStringLiteral("video/3gpp")},
        {QStringLiteral("m4a"), QStringLiteral("audio/mp4")},
        {QStringLiteral("mp3"), QStringLiteral("audio/mpeg")},
        {QStringLiteral("ogg"), QStringLiteral("audio/ogg")},
        {QStringLiteral("opus"), QStringLiteral("audio/ogg")},
        {QStringLiteral("wav"), QStringLiteral("audio/wav")},
    };
    const QString mime = kMimes.value(suffix, QStringLiteral("application/octet-stream"));
    const bool isImage = mime.startsWith(QLatin1String("image/"));

    if (kind == QLatin1String("voice")) {
        // Duration and waveform are the recorder's to supply; sending zeros is
        // honest about not having them rather than inventing a shape.
        sendMessage(conversationId,
                    ContentMarkers::encodeVoiceNote(QStringLiteral("audio/mp4"), 0, {}, bytes));
        return;
    }

    int w = 0, h = 0;
    ContentMarkers::imageSize(bytes, &w, &h);   // 0x0 is fine — the view uses the natural size

    // Small images ride inline as base64. Anything bigger will not survive an
    // MLS message, so it goes to Logos Storage encrypted and only a `store2:`
    // reference travels in the chat — the same split Android makes.
    if (isImage && bytes.size() <= ContentMarkers::maxInlineBytes()) {
        sendMessage(conversationId, ContentMarkers::encodeInlinePhoto(mime, w, h, bytes));
        return;
    }

    if (!storage()->configured()) {
        report(isImage
                   ? QStringLiteral("%1 is %2 KB — too large to send inline (limit %3 KB), and "
                                    "hosted media is not configured on this install. Set "
                                    "PEERS_STORAGE_TOKEN to enable it. Nothing was sent.")
                         .arg(info.fileName())
                         .arg(bytes.size() / 1024)
                         .arg(ContentMarkers::maxInlineBytes() / 1024)
                   : QStringLiteral("%1 can only be sent as hosted media, which is not configured "
                                    "on this install. Set PEERS_STORAGE_TOKEN to enable it. "
                                    "Nothing was sent.")
                         .arg(info.fileName()));
        return;
    }

    report(QStringLiteral("Uploading %1 (%2 KB)…").arg(info.fileName()).arg(bytes.size() / 1024));
    storage()->uploadEncrypted(bytes, [this, conversationId, mime, w, h](
                                          bool ok, StorageClient::Uploaded u, QString err) {
        if (!ok) {
            report(err);
            return;
        }
        sendMessage(conversationId,
                    ContentMarkers::encodeHostedMedia(u.cid, u.keyB64, mime, w, h, u.cap));
    });
}

void PeersUiBackend::sendLocation(QString conversationId, double lat, double lng)
{
    if (conversationId.isEmpty())
        return;
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
        report(QStringLiteral("That location is out of range."));
        return;
    }
    // loc1:<lat>,<lng> — Android's grammar; the optional third field is accuracy,
    // which the desktop has no source for, so it is omitted rather than faked.
    sendMessage(conversationId,
                QStringLiteral("loc1:%1,%2")
                    .arg(lat, 0, 'f', 6)
                    .arg(lng, 0, 'f', 6));
}

StorageClient* PeersUiBackend::storage()
{
    if (!m_storage)
        m_storage = new StorageClient(this);
    return m_storage;
}

void PeersUiBackend::fetchHostedMedia(const QString& convoId, const QString& cid,
                                      const QString& keyB64, const QString& cap,
                                      const QString& mime)
{
    // One fetch per blob. Without this guard every re-render of the thread
    // would start another download of the same media.
    const QString token = cid;
    if (m_fetching.contains(token))
        return;
    m_fetching.insert(token);

    storage()->downloadDecrypt(cid, keyB64, cap, mime,
                               [this, convoId, token](bool ok, QString path, QString err) {
                                   m_fetching.remove(token);
                                   if (!ok) {
                                       report(err);
                                       return;
                                   }
                                   m_mediaPaths.insert(token, path);
                                   // Re-render the thread so the bubble picks up
                                   // the now-local file.
                                   if (convoId == currentConversationId())
                                       loadMessages(convoId);
                               });
}
void PeersUiBackend::saveMedia(QString messageId, QString destPath)
{
    if (messageId.isEmpty() || destPath.isEmpty())
        return;
    const QString raw = m_rawByKey.value(messageId);
    if (raw.isEmpty()) {
        report(QStringLiteral("That message is no longer loaded."));
        return;
    }

    const QJsonObject o = ContentMarkers::decodeToJson(raw);
    const QString kind = o.value(QStringLiteral("kind")).toString();

    QByteArray bytes;
    if (kind == QLatin1String("media")) {
        // Hosted media is already decrypted into the cache by the fetch path.
        const QString cached = m_mediaPaths.value(o.value(QStringLiteral("cid")).toString());
        QFile f(cached);
        if (cached.isEmpty() || !f.open(QIODevice::ReadOnly)) {
            report(QStringLiteral("That media has not finished downloading yet."));
            return;
        }
        bytes = f.readAll();
    } else if (kind == QLatin1String("photo") || kind == QLatin1String("voice")) {
        // Inline: the payload sits after the unit separator.
        const int us = raw.indexOf(QChar(0x001F));
        if (us < 0) {
            report(QStringLiteral("That message carries no data."));
            return;
        }
        bytes = QByteArray::fromBase64(raw.mid(us + 1).toLatin1());
    } else {
        report(QStringLiteral("There is nothing to save on that message."));
        return;
    }

    QFile out(destPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        report(QStringLiteral("Could not write %1").arg(QFileInfo(destPath).fileName()));
        return;
    }
    out.write(bytes);
    out.close();
    Q_EMIT toast(QStringLiteral("Saved"));
}
void PeersUiBackend::startRecording()
{
    if (!m_recorder) {
        m_recorder = new VoiceRecorder(this);
        connect(m_recorder, &VoiceRecorder::tick, this,
                [this](int ms) { setRecordingMs(ms); });
        connect(m_recorder, &VoiceRecorder::autoStopped, this, [this] {
            // Capture stopped at the two-minute cap. What was recorded is still
            // held and sendable — say that rather than implying it was lost.
            setRecordingMs(m_recorder->elapsedMs());
            Q_EMIT toast(QStringLiteral("Two-minute limit reached — send or discard."));
        });
    }
    if (m_recorder->recording())
        return;

    QString whyNot;
    if (!m_recorder->start(&whyNot)) {
        report(whyNot);
        return;
    }
    setRecordingMs(0);
    setRecording(true);
}

void PeersUiBackend::cancelRecording()
{
    if (!m_recorder)
        return;
    m_recorder->cancel();
    setRecording(false);
    setRecordingMs(0);
}

void PeersUiBackend::sendRecording(QString conversationId)
{
    if (!m_recorder) {
        report(QStringLiteral("Nothing was recorded."));
        return;
    }

    QByteArray bytes;
    QString mime;
    int durationMs = 0;
    QVector<int> waveform;
    QString whyNot;
    const bool ok = m_recorder->finish(&bytes, &mime, &durationMs, &waveform, &whyNot);

    setRecording(false);
    setRecordingMs(0);

    if (!ok) {
        report(whyNot);
        return;
    }
    if (conversationId.isEmpty()) {
        report(QStringLiteral("Open a conversation before sending a voice note."));
        return;
    }

    // A voice note rides inline like a photo. Two minutes of 32 kbit AAC is
    // ~480 KB, so a long one can still exceed the inline ceiling; refuse
    // explicitly rather than emitting a message the peer cannot decode.
    if (bytes.size() > ContentMarkers::maxInlineBytes()) {
        report(QStringLiteral("That voice note is %1 KB, over the %2 KB message limit. "
                              "Record a shorter one.")
                   .arg(bytes.size() / 1024)
                   .arg(ContentMarkers::maxInlineBytes() / 1024));
        return;
    }

    sendMessage(conversationId,
                ContentMarkers::encodeVoiceNote(mime, durationMs,
                                                QList<int>(waveform.cbegin(), waveform.cend()),
                                                bytes));
}
void PeersUiBackend::refreshContacts()
{
    QJsonArray rows;
    for (auto it = m_contacts.begin(); it != m_contacts.end(); ++it) {
        QJsonObject o = it.value().toObject();
        o.insert(QStringLiteral("address"), it.key());
        if (o.value(QStringLiteral("label")).toString().isEmpty())
            o.insert(QStringLiteral("label"), shortLabel(it.key()));
        // The short hex is always available so a row can show both, the way
        // Android does (label on top, address beneath).
        o.insert(QStringLiteral("shortAddress"), shortLabel(it.key()));
        rows.append(o);
    }
    setContactsJson(QString::fromUtf8(QJsonDocument(rows).toJson(QJsonDocument::Compact)));
}
QString PeersUiBackend::displayFor(const QString& address) const
{
    const QString label =
        m_contacts.value(address).toObject().value(QStringLiteral("label")).toString();
    return label.isEmpty() ? shortLabel(address) : label;
}

void PeersUiBackend::setContactLabel(QString address, QString label)
{
    if (address.isEmpty())
        return;
    QJsonObject o = m_contacts.value(address).toObject();
    o.insert(QStringLiteral("label"), label);
    m_contacts.insert(address, o);
    saveState();

    // Android's LabelModal writes the label to the conversation row's nickname,
    // which is what renames the row in the list. Mirror that for the open 1:1 so
    // labelling someone renames them everywhere at once, not just in bubbles.
    if (!currentIsGroup() && !currentConversationId().isEmpty()
        && currentPeerAddress() == address)
        setConversationNickname(currentConversationId(), label);

    refreshContacts();
    refreshConversations();
    if (!currentConversationId().isEmpty())
        loadMessages(currentConversationId());
}
void PeersUiBackend::removeContact(QString address)
{
    m_contacts.remove(address);
    saveState();
    refreshContacts();
    refreshConversations();
    if (!currentConversationId().isEmpty())
        loadMessages(currentConversationId());
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
    const LogosResult res = modules().peers_core.set_installation_name(name);
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
    if (localPath.isEmpty()) {
        Q_EMIT backupFailed(QStringLiteral("Choose a backup file first."));
        return;
    }
    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly)) {
        Q_EMIT backupFailed(QStringLiteral("Could not read %1").arg(QFileInfo(localPath).fileName()));
        return;
    }
    const QByteArray envelope = f.readAll();
    f.close();

    const BackupReader::Result res = BackupReader::open(envelope, passphrase);
    if (!res.ok) {
        Q_EMIT backupFailed(res.error);
        return;
    }

    // The backup carries an identity seed, but chat_module 0.2.2 has nowhere to
    // put it — there is no import method on the contract (ADR 0004). Say so
    // plainly instead of implying the desktop client has become that identity.
    if (res.hasIdentity) {
        report(QStringLiteral(
                   "Backup opened: %1 conversations, %2 messages. It contains an identity "
                   "(%3 bytes), but this build cannot adopt it — the chat core has no "
                   "identity-import method yet.")
                   .arg(res.conversationCount)
                   .arg(res.messageCount)
                   .arg(res.identityBytes));
    }

    // The address the backup belonged to is not derivable here without the core,
    // so report the empty string rather than guessing one.
    Q_EMIT backupOpened(QString(), res.conversationCount, res.messageCount);
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
    m_hiddenKeys = root.value(QStringLiteral("hidden")).toObject();

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
        { QStringLiteral("hidden"), m_hiddenKeys },
    };

    QFile f(settingsPath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}
