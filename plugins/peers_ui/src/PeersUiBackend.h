#ifndef PEERS_UI_BACKEND_H
#define PEERS_UI_BACKEND_H

#include <QDateTime>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QVariantList>
#include <functional>

#include "rep_peers_ui_source.h"     // PeersUiBackendSimpleSource (repc from src/peers_ui.rep)
#include "logos_ui_plugin_context.h" // LogosUiPluginContext: modules() + onContextReady()

class QTimer;
class StorageClient;
class VoiceRecorder;

//
// The Peers backend. Bridges QML (logos.module("peers_ui")) to the upstream
// chat_module 0.2.2 MLS core via the builder-generated typed client
// (modules().chat_module.*) — see ADR 0001.
//
// Two invariants run through this whole class and are easy to break:
//
//  1. NEVER issue a synchronous module read (list_conversations, get_messages,
//     list_group_members) from inside a module event callback. Those are
//     synchronous QtRO calls; issuing one from an event handler re-enters the
//     replica's socket-read handler while its read notifier is disabled, so the
//     reply only arrives after the ~20s call timeout and the UI thread stalls
//     for that entire time. Every such read from an event path goes through
//     deferToEventLoop().
//
//  2. Subscribe to events BEFORE taking the first snapshot, or an event that
//     fires in the gap is lost and history stays missing until a reconnect that
//     may never come.
//
// List data reaches QML as JSON strings rather than QtRO-remoted models
// (ADR 0006), so there is exactly one source of truth per list.
//
class PeersUiBackend : public PeersUiBackendSimpleSource,
                       public LogosUiPluginContext
{
public:
    explicit PeersUiBackend(QObject* parent = nullptr);
    ~PeersUiBackend() override;

    // ── conversations & messages ────────────────────────────────────────────
    void selectConversation(QString conversationId) override;
    void createConversation(QString peerAddress) override;
    void sendMessage(QString conversationId, QString content) override;
    void retryMessage(QString conversationId, QString localId) override;
    void deleteConversation(QString conversationId) override;
    void setConversationNickname(QString conversationId, QString nickname) override;
    void setDraft(QString conversationId, QString text) override;

    // ── message interactions ────────────────────────────────────────────────
    void sendReply(QString conversationId, QString content, QString replyToId) override;
    void forwardMessage(QString fromConversationId, QString messageId,
                        QString toConversationId) override;
    void reactToMessage(QString conversationId, QString messageId, QString emoji) override;
    void unreactToMessage(QString conversationId, QString messageId, QString emoji) override;
    void pinMessage(QString conversationId, QString messageId) override;
    void unpinMessage(QString conversationId) override;
    void deleteMessageForMe(QString conversationId, QString messageId) override;
    void copyToClipboard(QString text) override;

    // ── media ───────────────────────────────────────────────────────────────
    void sendMedia(QString conversationId, QString localPath, QString kind) override;
    void sendLocation(QString conversationId, double lat, double lng) override;
    void saveMedia(QString messageId, QString destPath) override;
    void startRecording() override;
    void cancelRecording() override;
    void sendRecording(QString conversationId) override;

    // ── groups ──────────────────────────────────────────────────────────────
    void createGroupConversation(QString name, QString description) override;
    void addGroupMember(QString conversationId, QString peerAddress) override;
    void refreshMembers() override;
    void leaveGroup(QString conversationId) override;

    // ── contacts & identity ─────────────────────────────────────────────────
    void refreshContacts() override;
    void setContactLabel(QString address, QString label) override;
    void removeContact(QString address) override;
    void sendContactCard(QString conversationId, QString address) override;
    void setDisplayName(QString name) override;
    void setAvatar(QString localPath) override;
    void decodeQrFromFile(QString localPath) override;

    // ── settings ────────────────────────────────────────────────────────────
    void setSetting(QString key, QString jsonValue) override;

    // ── security ────────────────────────────────────────────────────────────
    void setPin(QString pin) override;
    void setDuressPin(QString pin) override;
    void clearPin(QString currentPin) override;
    void unlock(QString pin) override;
    void lock() override;
    void resetIdentityAndData() override;

    // ── identity portability ────────────────────────────────────────────────
    void openBackup(QString localPath, QString passphrase) override;
    void exportBackup(QString destPath, QString passphrase) override;

protected:
    // Fires once the generated plugin glue has wired modules(), so the typed
    // chat_module surface is live. init() + event subscription happen here.
    // Never do synchronous work directly in here — defer one turn.
    void onContextReady() override;

private:
    // ── lifecycle ───────────────────────────────────────────────────────────
    void initialiseModule();
    void subscribeToEvents();
    void startHealthProbe();

    // ── refresh ─────────────────────────────────────────────────────────────
    void refreshConversations();
    void refreshMyAddress();
    bool loadMessages(const QString& convoId);
    void syncCurrentConversationMeta();

    // ── event handlers (positional args, in lidl declaration order) ─────────
    void applyMessageReceived(const QVariantList& a);
    void applyMessageSent(const QVariantList& a);
    void applyConversationCreated(const QVariantList& a);
    void applyConversationUpdated(const QVariantList& a);
    void applyMembersChanged(const QVariantList& a);
    void applyConversationDeleted(const QVariantList& a);
    void applyDeliveryState(const QString& state, const QString& detail);

    // ── plumbing ────────────────────────────────────────────────────────────
    // Runs `work` on the next event-loop turn. See invariant 1 above.
    void deferToEventLoop(std::function<void()> work);
    // The one way a failure reaches anyone: it joins the retained error list,
    // goes to the log, and raises the error() signal.
    void report(const QString& message);
    void reportFailure(const QString& action, const QString& reason);
    // Records that a feature exists in the contract but is not wired yet, so a
    // caller gets an honest answer instead of silence. Anything still routed
    // here is listed as unimplemented in docs/PARITY.md.
    void reportUnimplemented(const QString& what);

    // Lazily-created Logos-Storage client for the store2: hosted-media path.
    StorageClient* storage();
    // Fetch + decrypt a hosted blob, then re-render the thread.
    void fetchHostedMedia(const QString& convoId, const QString& cid, const QString& keyB64,
                          const QString& cap, const QString& mime);

    // Persisted app state (settings, drafts, contacts, PIN verifier) under the
    // host-assigned instance directory.
    void loadState();
    void saveState();

    QString settingsPath() const;

    bool m_moduleInitialised = false;
    bool m_eventsSubscribed = false;
    bool m_initialSnapshotDone = false;

    // Local-only state the core does not carry.
    QHash<QString, QString> m_drafts;       // convoId → draft text
    QJsonObject m_settings;
    QJsonObject m_contacts;                 // address → {label, verified, avatar}
    QJsonObject m_pinnedByConvo;            // convoId → pinned message object
    // convoId → last RENDERABLE preview, so a folded control marker (reaction,
    // pin) as the newest message doesn't blank the conversation row.
    QHash<QString, QString> m_lastPreview;

    QTimer* m_healthTimer = nullptr;
    // Logos-Storage client for hosted media (the store2: path). Null until
    // first use.
    StorageClient* m_storage = nullptr;
    // Microphone capture for voice notes. Null until the first record.
    VoiceRecorder* m_recorder = nullptr;
    // convoId+cid already being fetched, so a re-render doesn't refetch.
    QSet<QString> m_fetching;
    // cid → local decrypted file, so a fetched blob is handed to the view
    // without going near the network again.
    QHash<QString, QString> m_mediaPaths;
    // key -> the RAW stored body of the loaded conversation's messages, so an
    // action (forward, copy, save) can work on what was actually sent rather
    // than on the decoded display text.
    QHash<QString, QString> m_rawByKey;
    // Keys hidden by "delete for me". LOCAL ONLY — Peers has no remote unsend,
    // so this must never be presented as deleting for anyone else.
    QJsonObject m_hiddenKeys;
};

#endif // PEERS_UI_BACKEND_H
