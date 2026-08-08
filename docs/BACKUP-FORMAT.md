# Peers mobile encrypted backup (`.peersenc`) — ground truth for a desktop reader

Extracted by reading the Android sources at `<logos-chat-android>`.
Every value below is cited as `path:line`. Paths are repo-relative. Nothing here is inferred
from docs alone; where the source does not determine a behaviour it is called out under
**Ambiguities** at the end.

Files read (full or the cited regions):

- `android/app/src/main/java/com/logoschat/BackupCrypto.kt` (whole file, 134 lines)
- `android/app/src/main/java/com/logoschat/BackupImport.kt` (whole file, 59 lines)
- `android/app/src/main/java/com/logoschat/ChatDb.kt` (1–250, 1020–1210)
- `android/app/src/main/java/com/logoschat/LogosChatModule.kt` (1370–1500)
- `android/app/src/main/java/com/logoschat/NodeRuntime.kt` (80–210, 255–300, 430–540)
- `android/app/src/main/java/com/logoschat/NodeBridge.kt` (40–69)
- `android/app/src/main/java/com/logoschat/ImagePickerModule.kt` (`pickAndImportBackup`, from line 228)
- `android/app/src/main/cpp/include/liblogoschat.h` (35–69)
- `android/app/src/test/java/com/logoschat/BackupCryptoTest.kt`,
  `android/app/src/test/java/com/logoschat/ChatBackupImportTest.kt`
- JS/TS: `src/native/LogosChat.ts`, `src/native/ImagePicker.ts`,
  `src/components/BackupPassphraseModal.tsx`, `src/screens/AboutScreen.tsx`,
  `src/lib/restoreOutcome.ts`, `src/stores/settingsStore.ts`, `src/stores/avatarStore.ts`,
  `src/stores/nodeStore.ts`, `src/stores/securityStore.ts`
- `docs/m1prime-log.md` (1–40), `docs/TESTING.md` (158–196)

---

## 1. The file

| Property | Value | Source |
|---|---|---|
| Extension | `.peersenc` | `BackupCrypto.kt:38` (`FILE_EXT`) |
| Filename prefix | `logos-chat-backup-` | `BackupCrypto.kt:37` (`FILE_PREFIX`) |
| Canonical name | `logos-chat-backup-<ts>.peersenc`, `ts` = `yyyyMMdd-HHmmss` (Locale.US, device local time) | `BackupCrypto.kt:41`, `LogosChatModule.kt:1413-1416` |
| Actual on-disk name | `File.createTempFile("logos-chat-backup-<ts>-", ".peersenc", dir)` → an extra random infix before `.peersenc` | `BackupCrypto.kt:50-53`, `LogosChatModule.kt:1416` |
| Contents | **A single UTF-8 JSON object, ASCII text — not a binary container.** Written with `file.writeText(envelope, Charsets.UTF_8)` | `LogosChatModule.kt:1417` |
| Share MIME | `application/octet-stream` (ACTION_SEND) | `LogosChatModule.kt:1423` |
| Import picker filter | `ACTION_OPEN_DOCUMENT`, `type = "*/*"`, `CATEGORY_OPENABLE` — the file is chosen by the user, extension is not enforced | `ImagePickerModule.kt:241-246` |

There is **no magic byte prefix, no length header, no framing**. A desktop reader can simply
`read_text(path, "utf-8")` and `json.loads` it. The only identity check is the `format` string
inside the JSON (§2.2).

Legacy note: pre-#361 exports were **plaintext `.json`** with the same `logos-chat-backup-` prefix
(`BackupCrypto.kt:59-63` comment + `isBackupFile`, and `BackupCryptoTest.kt:95`). Those files are the §4 plaintext
JSON *unencrypted*, and they have **no `identity` field** (identity was added in #440). A robust
desktop reader may try `json.loads` first: if the top-level `format` is `logos-chat-backup` it is a
legacy plaintext backup; if it is `peers-backup-enc` it is an encrypted envelope.

---

## 2. The `.peersenc` envelope JSON

Built at `BackupCrypto.kt:92-102` (`encrypt`), consumed at `BackupCrypto.kt:109-120` (`decrypt`).

### 2.1 Fields

| Key | JSON type | Value / encoding | Decoded byte length | Source |
|---|---|---|---|---|
| `format` | string | Constant `"peers-backup-enc"` | — | `BackupCrypto.kt:27`, written `:94` |
| `v` | number (int) | Constant `1` | — | `BackupCrypto.kt:28`, written `:95` |
| `kdf` | string | Constant `"pbkdf2-hmac-sha256"` | — | `BackupCrypto.kt:29`, written `:96` |
| `iters` | number (int) | Constant `600000` on write | — | `BackupCrypto.kt:30`, written `:97` |
| `salt` | string | Base64, `Base64.NO_WRAP` (standard RFC 4648 alphabet `A–Za–z0–9+/`, `=` padding, **no line breaks**) | **16 bytes** | `BackupCrypto.kt:32` (`SALT_LEN`), `:86`, `:98`, `:131` |
| `iv` | string | Base64 `NO_WRAP` | **12 bytes** | `BackupCrypto.kt:33` (`IV_LEN`), `:87`, `:99` |
| `ct` | string | Base64 `NO_WRAP` | `len(plaintext_utf8) + 16` — **ciphertext with the 16-byte GCM tag APPENDED** | `BackupCrypto.kt:34` (`TAG_BITS=128`), `:89-91`, `:100` |

There are exactly **seven** keys. There is no `tag` field, no `aad` field, no `mac` field, no
`version` string, no filename/timestamp metadata in the envelope.

**Key order in the file is not guaranteed** — `org.json.JSONObject` is used
(`BackupCrypto.kt:10, 92`). Parse by name, never by position.

### 2.2 What `decrypt` actually validates (important for interop)

`BackupCrypto.kt:110-119`:

- `format` **must** equal `"peers-backup-enc"` — `require(o.optString("format") == FORMAT)`
  (`:111`). This is the only identity gate. Note `optString`, so a *missing* `format` yields `""`
  and fails the same `require` (`IllegalArgumentException`, not `JSONException`).
- `iters` is read with `getInt` and must satisfy `1..10_000_000` (`:112`). **`iters` is mandatory**
  — `getInt` throws `JSONException` when the key is absent or not int-coercible; out of range
  throws `IllegalArgumentException`. There is no default.
- `salt`, `iv`, `ct` are read with `getString` (missing → `JSONException`) and Base64-decoded
  (`:113-115`). All three are mandatory.
- The whole envelope must parse as a JSON **object** first (`JSONObject(envelope)`, `:110`).
- **`v` is never read.** **`kdf` is never read.** A decryptor that honours `kdf` would diverge from
  the app; the Android reader hard-codes PBKDF2-HMAC-SHA256 regardless. A desktop reader *should*
  still assert `kdf == "pbkdf2-hmac-sha256"` and refuse anything else — but be aware the phone
  would happily decrypt a file whose `kdf` said something different.
- Salt and IV lengths are **not** validated on read; whatever length is in the file is passed
  through to PBKDF2 / `GCMParameterSpec`. (A 12-byte IV is what the writer always produces.)

---

## 3. Cryptography — exact parameters

### 3.1 KDF

`BackupCrypto.kt:122-129`:

```
PBEKeySpec(passphrase.toCharArray(), salt, iters, 256)
SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
```

| Parameter | Value | Source |
|---|---|---|
| Algorithm | PBKDF2 with HMAC-SHA-256 | `BackupCrypto.kt:125` |
| Iterations (write) | `600000` | `BackupCrypto.kt:30` |
| Iterations (read) | taken from the envelope's `iters`, bounded `1..10_000_000` | `BackupCrypto.kt:112, 116` |
| Salt | 16 random bytes from `SecureRandom` | `BackupCrypto.kt:32, 85-86` |
| Derived key length | `KEY_BITS = 256` → **32 bytes** | `BackupCrypto.kt:31, 123` |
| Password → bytes | `char[]` handed to `PBEKeySpec`; the byte encoding is done by the JCE provider (see Ambiguities §8.1) | `BackupCrypto.kt:123` |

The whole 32-byte PBKDF2 output is the AES key; there is no HKDF/split/info step.

### 3.2 AEAD

`BackupCrypto.kt:89-91` (encrypt) and `:117-119` (decrypt):

| Parameter | Value | Source |
|---|---|---|
| Transformation | `AES/GCM/NoPadding` | `BackupCrypto.kt:89, 117` |
| Key | the 32-byte PBKDF2 output → AES-256 | `BackupCrypto.kt:90` (`SecretKeySpec(key, "AES")`) |
| IV / nonce | 12 random bytes, fresh per encryption | `BackupCrypto.kt:33, 87` |
| Tag length | `TAG_BITS = 128` → **16 bytes** | `BackupCrypto.kt:34, 90, 118` |
| Tag placement | **Appended to the ciphertext** (JCE convention: `Cipher.doFinal` returns `ct‖tag`), and the whole thing is base64'd into `ct` | `BackupCrypto.kt:91, 100` |
| Associated data (AAD) | **NONE.** `updateAAD` is never called anywhere in the file | absence throughout `BackupCrypto.kt` |
| Plaintext encoding | UTF-8 (`plaintext.toByteArray(Charsets.UTF_8)` / `String(..., Charsets.UTF_8)`) | `BackupCrypto.kt:91, 119` |

So: `ct_b64 = b64(AES-256-GCM_{K,IV}(utf8(plaintext_json)))` with the tag appended, no AAD.
Python's `AESGCM.encrypt(iv, data, None)` / `.decrypt(iv, data, None)` is byte-for-byte compatible
(verified, §7).

Wrong passphrase and tampering are indistinguishable: both surface as a GCM tag failure
(`AEADBadTagException`), which `BackupImport` maps to the single user-facing message
`"wrong passphrase, or not a Peers backup"` (`BackupImport.kt:41-44`).

### 3.3 Passphrase policy

- Export: rejected if `passphrase.length < 8` (UTF-16 code units — Kotlin `String.length`),
  `LogosChatModule.kt:1392-1394`.
- `BackupCrypto.encrypt` itself only requires non-empty (`BackupCrypto.kt:84`).
- Import: **no length check at all** on the native side — `BackupCrypto.decrypt` does not even
  require non-empty, so an empty passphrase is derived and simply fails the GCM tag. The JS restore
  modal enforces `MIN_PASSPHRASE_LEN = 8` client-side only
  (`src/components/BackupPassphraseModal.tsx:9`, gate at `:37` (`tooShort`) and `:41-43`
  (`canExport`)).
- The passphrase is never stored; `PBEKeySpec.clearPassword()` is called in a `finally`
  (`BackupCrypto.kt:126-128`).

---

## 4. The plaintext JSON (what is inside the envelope)

The plaintext is a single JSON object built in two steps:

1. `ChatDb.exportJson()` produces the base object — `ChatDb.kt:1040-1057`.
2. `LogosChatModule.exportChatData` parses that string back into a `JSONObject` and **adds one key,
   `identity`** — `LogosChatModule.kt:1400-1404`.

### 4.1 Top-level keys

| Key | Type | Value | Source |
|---|---|---|---|
| `format` | string | `"logos-chat-backup"` (constant `BACKUP_FORMAT`) — note this is a **different** string from the envelope's `"peers-backup-enc"` | `ChatDb.kt:61`, written `:1044` |
| `version` | number | literal `1` (hard-coded; unrelated to `schemaVersion`) | `ChatDb.kt:1045` |
| `schemaVersion` | number | `DB_VERSION`, currently **10** | `ChatDb.kt:58`, written `:1046` |
| `exportedAt` | number (int64) | `System.currentTimeMillis()` — ms since epoch | `ChatDb.kt:1047` |
| `kv` | array of objects | `kv` table, minus excluded keys | `ChatDb.kt:1049` |
| `conversations` | array of objects | `conversations` table | `ChatDb.kt:1050` |
| `messages` | array of objects | `messages` table | `ChatDb.kt:1051` |
| `group_members` | array of objects | `group_members` table | `ChatDb.kt:1052` |
| `mesh_map` | array of objects | `mesh_map` table | `ChatDb.kt:1053` |
| `mesh_contacts` | array of objects | `mesh_contacts` table | `ChatDb.kt:1054` |
| `identity` | string | Base64 `NO_WRAP` of the raw identity seed — **64 bytes in practice, but the export path does not check** (§5.1). **Optional** — absent when no identity is provisioned or the Keystore unwrap failed | `LogosChatModule.kt:1401-1403`, `NodeRuntime.kt:445-457` |

That is the complete set — ten keys plus the optional `identity`. Key order is
`org.json`-determined; do not rely on it.

### 4.2 Row encoding (applies to every table array)

`ChatDb.dumpTable` — `ChatDb.kt:1182-1207`:

- `SELECT * FROM <table>`; one JSON object per row; keys are the SQLite column names, in
  `cursor.columnNames` order (which is the physical column order and therefore **differs between a
  fresh v10 DB and one upgraded from v1** — irrelevant for a keyed reader).
- Type mapping (`ChatDb.kt:1196-1201`):
  - `FIELD_TYPE_NULL` → JSON `null`
  - `FIELD_TYPE_INTEGER` → JSON number via `getLong` (integer, may exceed 2^31)
  - `FIELD_TYPE_FLOAT` → JSON number via `getDouble`
  - everything else (TEXT and BLOB) → JSON string via `getString`
- All columns of every row are emitted, nulls preserved. No column is renamed.

### 4.3 Table schemas (fresh install, `DB_VERSION = 10`)

From `ChatDb.createSchema` — `ChatDb.kt:107-161`.

**`kv`** — `ChatDb.kt:108`
```sql
kv(key TEXT PRIMARY KEY, value TEXT)
```
Rows are `{"key": <string>, "value": <string|null>}`.
Two keys are **never exported**: `pinVerifier` and `duressVerifier`
(`EXPORT_EXCLUDED_KV`, `ChatDb.kt:97`; applied at `ChatDb.kt:1049` via
`skipKeyColumn = "key"`). A restore therefore comes back with no screen-lock PIN set.

Known `kv` keys written by the app (for a desktop reader that wants to interpret settings; all
values are strings):

| Key | Meaning | Source |
|---|---|---|
| `displayName` | local device label | `src/stores/settingsStore.ts:41` |
| `myAddress` | cached own hex address | `src/stores/nodeStore.ts:9, 78` |
| `myAvatar` | JSON string of own avatar `MediaRef` (or `''` when cleared) | `src/stores/avatarStore.ts:18, 83` |
| `avatar:<key>` | per-contact avatar `MediaRef` JSON | `src/stores/avatarStore.ts:16, 64` |
| `navState` | serialized navigation state | `src/navigation/RootNavigator.tsx:39, 45` |
| `nodeAutoRestart` | `"1"`/other | `NodeRuntime.kt:26` |
| `deliveryServiceNode`, `deliveryRelayNode` | self-hosted delivery multiaddrs | `NodeRuntime.kt:31, 36` |
| `meshConfigured`, `lastRadioAddress`, `bleConfigured`, `bleAdvertiseIdentity`, `bleEngagedPref`, `lockOnBackground`, `mediaOverTor` | `'true'`/`'false'` (or an address) | `src/stores/settingsStore.ts:45–77` |
| `notifLocal`, `notifInApp`, `notifSound`, `notifVibrate`, `notifShowContent` | `'true'`/`'false'` | `src/stores/settingsStore.ts:80–90`, `MessageNotifier.kt:39` |
| `readdCursor`, `readdOwed` | group re-add bookkeeping | `src/stores/chatStore.ts:448, 451` |
| `pinVerifier`, `duressVerifier` | **excluded from backups** | `ChatDb.kt:97`, `src/stores/securityStore.ts:20, 22` |

**`conversations`** (15 columns) — `ChatDb.kt:110-123`
```sql
conversations(
  convo_pk INTEGER PRIMARY KEY AUTOINCREMENT,
  peer_address TEXT,
  lib_convo_id TEXT,
  nickname TEXT,
  is_group INT DEFAULT 0,
  group_name TEXT,
  created_by_me INT DEFAULT 0,
  verified INT DEFAULT 0,
  transport TEXT DEFAULT 'logos',
  mesh_mode INT DEFAULT 0,
  mesh_channel_idx INT,
  mesh_channel_key TEXT,
  created_at INT, last_message_at INT, unread INT DEFAULT 0)
```
`peer_address` is 64 lowercase hex chars = the 32-byte Ed25519 account pubkey
(`src/native/LogosChat.ts:298`). `transport` ∈ `'logos'|'mesh'` (`ChatDb.kt:191-193`).
Timestamps are ms since epoch (`ChatDb.kt:29`).

**`messages`** (8 columns) — `ChatDb.kt:125-131`
```sql
messages(
  msg_pk INTEGER PRIMARY KEY AUTOINCREMENT,
  convo_pk INT REFERENCES conversations,
  direction TEXT CHECK(direction IN ('in','out')),
  content TEXT, sent_at INT, sender_account TEXT,
  sent_via TEXT DEFAULT 'logos',
  status TEXT CHECK(status IN ('pending','sent','failed','received')))
```
`content` is UTF-8 text (`ChatDb.kt:29`). It is **not always human text**: the app overloads it with
line-prefixed app-level markers, which a desktop renderer must recognise:

| Prefix | Meaning | Source |
|---|---|---|
| `img1:` / `img1v:` | image, wire / local form | `src/native/imageMsg.ts:15-16` |
| `voc1:` / `voc1v:` | voice note, wire / local | `src/native/voiceMsg.ts:9-10` |
| `store1:` / `store2:` | stored media ref v1 / v2 | `src/messages/media.ts:15, 21` |
| `loc1:` | location | `src/native/locMsg.ts:8` |
| `reply1:` | reply envelope | `src/messages/reply.ts:13` |
| `pin1:` | pin control | `src/messages/pins.ts:11` |
| `pfp1:` (`pfp1:clear`) | avatar broadcast | `src/messages/pfp.ts:15, 18` |
| `addr1:` | shared contact | `src/messages/address.ts:10` |
| `gcfg1:` | group config | `src/messages/groupcfg.ts:17` |
| `leave1:` | group leave | `src/messages/leave.ts:14` |
| `readd1:` | group re-add | `src/messages/readd.ts:14` |
| `frg1:` | BLE fragment | `src/native/bleFrag.ts:22` |
| `lr1:` | relay | `src/native/relay.ts:16` |

(These prefixes are message-content semantics, **not** part of the backup format itself. Media
*bytes* referenced by `store2:`/`img1:` live in app storage and are **not** in the backup.)

**`group_members`** — `ChatDb.kt:136-139`
```sql
group_members(
  convo_pk INT REFERENCES conversations,
  address TEXT, is_self INT DEFAULT 0, added_at INT,
  PRIMARY KEY(convo_pk, address))
```

**`mesh_map`** — `ChatDb.kt:145-149`
```sql
mesh_map(logos_address TEXT PRIMARY KEY, mesh_pubkey TEXT NOT NULL, mesh_name TEXT, mapped_at INT)
```

**`mesh_contacts`** — `ChatDb.kt:154-157`
```sql
mesh_contacts(pubkey_hex TEXT PRIMARY KEY, name TEXT, last_seen INT)
```
`pubkey_hex` is the full 32-byte account pubkey as 64 hex (`ChatDb.kt:150-152`).

### 4.4 What is NOT in the backup

- The lib's MLS crypto/ratchet state and encrypted store (`logoschat-store`) — explicitly excluded
  and explicitly *not* restored (`ChatDb.kt:1031-1034`, `NodeRuntime.kt:464-465`,
  `LogosChatModule.kt:1381-1384`). Groups are re-formed by re-invite.
- Media blobs / images (`chat-images` is wiped on restore, `NodeRuntime.kt:494`).
- `pinVerifier` / `duressVerifier` (`ChatDb.kt:94-97`).
- The store-encryption key (SharedPreferences is cleared on restore, `NodeRuntime.kt:493`).

### 4.5 Validation the phone applies before importing

`ChatDb.validateImportJson` — `ChatDb.kt:1073-1115` (also re-run at the top of `importJson`,
`:1141`). A desktop *writer* of `.peersenc` files must satisfy all of these:

1. Parses as a JSON object, else `"not a Peers backup (unreadable contents)"` (`:1074-1079`).
2. `format == "logos-chat-backup"`, else `"not a Peers backup (format='…')"` (`:1080-1083`).
3. `schemaVersion` read as `optInt("schemaVersion", -1)` and must be `>= 0`, else
   `"backup has no schemaVersion"` (`:1086-1089`). Because it is `optInt`, a missing key **or** a
   non-numeric value both land on `-1` and are refused — no exception leaks out.
4. `schemaVersion <= DB_VERSION` of the reading build, else refused as
   `"backup was made by a newer version of Peers…"` (`:1090-1094`). `format` is likewise read with
   `optString("format", "")` (`:1080`), so a missing key becomes `""` and reports
   `"not a Peers backup (format='')"`.
5. For each of `RESTORABLE_TABLES = ["kv","conversations","messages","group_members","mesh_map","mesh_contacts"]`
   (`ChatDb.kt:68-69`): the value, if present, must be a JSON array of JSON objects, and **every key
   in every row must be a real column of that table in the reading build** (`PRAGMA table_info`,
   `ChatDb.kt:1096-1126`). Three details a reimplementer must mirror:
   - A missing table key is skipped (`root.opt(table) ?: continue`, `:1097`) — tables are optional.
   - A present-but-**empty** array short-circuits before the column check
     (`if (arr.length() == 0) continue`, `:1101`), so an empty array never touches the schema.
   - `columnsOf` throws `"this build has no table '<t>'"` if `PRAGMA table_info` comes back empty
     (`:1118-1126`) — i.e. a non-empty array for a table the reading build lacks is refused, not
     ignored.
   Rows are typed via `arr.opt(i) as? JSONObject` — a non-object row →
   `"backup table '<t>' row <i> is malformed"` (`:1104-1106`); a non-array value →
   `"backup table '<t>' is malformed"` (`:1098-1100`).
6. Import inserts with `INSERT OR REPLACE`, parent table first, in **one transaction**
   (`ChatDb.kt:1140-1154`); JSON→SQLite binding: `null`→NULL, Int/Long→INTEGER, Double→REAL,
   Boolean→1/0, anything else→`toString()` TEXT (`ChatDb.kt:1157-1175`).

Note `identity`, `format`, `version`, `schemaVersion`, `exportedAt` are simply ignored by
`importJson` (it only iterates `RESTORABLE_TABLES`).

---

## 5. The `identity` value — exactly what it is

### 5.1 On export

`LogosChatModule.kt:1400-1404`:

```kotlin
val root = org.json.JSONObject(ChatRepo.requireDb().exportJson())
NodeRuntime.readIdentitySeed(ctx)?.let {
  root.put("identity", android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP))
}
```

`NodeRuntime.readIdentitySeed(context)` — `NodeRuntime.kt:445-457` — returns the **raw bytes of the
identity seed file**, obtained one of two ways:

- If `filesDir/logoschat-identity.enc` exists (the normal case while the node is up): the file's
  text is a Keystore-wrapped blob; `KeystoreCrypto.unwrap` yields a Base64 `NO_WRAP` string, which is
  `Base64.decode`d back to the raw bytes (`NodeRuntime.kt:446-454`; the wrap side is
  `sealIdentity`, `NodeRuntime.kt:195-210`, which base64s the plaintext file bytes before wrapping).
- Else if `filesDir/logoschat-identity.bin` exists (the plaintext window): its bytes verbatim
  (`NodeRuntime.kt:455-456`). File names: `NodeRuntime.kt:40, 43`; path via
  `identityPath()`, `NodeRuntime.kt:97-98`.

So:

> **`identity` = `base64(NO_WRAP)` of the exact, unmodified 64 bytes of the file the Rust chat core
> reads as `identity_path`.**

Base64 of 64 bytes is an **88-character** string ending in **two** `=` padding characters:
`ceil(64/3)*4 = 88` chars, and because `64 mod 3 == 1` the last group carries one data byte → two
pad chars (`AAAA…AA==`). A desktop reader should assert `len(b64decode(identity)) == 64`.

Caveat: **nothing on the export side enforces 64.** `readIdentitySeed` returns the file's bytes
verbatim (`NodeRuntime.kt:445-457`) and `exportChatData` base64s whatever it gets
(`LogosChatModule.kt:1401-1403`). The 64-byte gate exists **only on the import path**
(`NodeRuntime.kt:476`). So "64 bytes" is what the wrapper writes and what a restore demands — not
something the writer validates.

### 5.2 What those 64 bytes are

`account seed ‖ delegate seed`, per the native header:

> "Open with a PERSISTENT identity loaded (or created) from identity_path **(a 64-byte seed file:
> account seed || delegate seed)**" — `android/app/src/main/cpp/include/liblogoschat.h:46-50`

Same wording at `NodeRuntime.kt:88` ("The identity seed (64 bytes, account||delegate)"),
`NodeRuntime.kt:439`, `BackupImport.kt:10`, and `docs/m1prime-log.md:19`.

The implied split is 32 + 32 (two Ed25519 seeds; the account address is the 32-byte Ed25519 account
verifying key rendered as 64 hex — `src/native/LogosChat.ts:298`,
`docs/mls-rebuild-scoping.md:117`; the account→delegate structure that motivates the second seed is
`docs/mls-rebuild-scoping.md:119`).
**The 32/32 split itself is documentation, not code, in this repo** — the Rust wrapper that parses
the file is not vendored here (no `.rs` sources exist in the tree; only the prebuilt `.so` and the C
header). See Ambiguities §8.2. For a desktop port this does not matter as long as the desktop core
is the same `open_persistent` API: you hand it the **whole 64 bytes**, opaque.

### 5.3 How Android feeds it back into the chat core

Chain: `BackupImport.runBlocking` → `NodeRuntime.importAndRestart` → `NodeBridge.chatOpenPersistent`.

1. `BackupImport.kt:45-52`
   ```kotlin
   val root = JSONObject(json)
   val idB64 = root.optString("identity", "")
   if (idB64.isEmpty()) throw IllegalArgumentException(
       "this backup has no identity (it was made before identity backup existed)")
   val seed = Base64.decode(idB64, Base64.NO_WRAP)
   NodeRuntime.importAndRestart(seed, json) { … }
   ```
   Note the **whole decrypted plaintext string `json`** (identity key included) is passed as the
   chat payload; `ChatDb.importJson` ignores the extra key.

2. `NodeRuntime.importAndRestart(seed, chatJson, onDone)` — `NodeRuntime.kt:472-522`, on the node
   executor:
   - `seed.size != 64` → error `"bad identity seed (N bytes, expected 64)"` (`:476`).
   - **Validate first, wipe second** (`:479-487`): `ChatDb.validateImportJson(chatJson)`; failure →
     `"<reason> — nothing on this device was changed"`, nothing destroyed.
   - `stopBlocking()` (`:488`), then delete `logoschat-identity.bin`, `logoschat-identity.enc`,
     the store file `logoschat-store.db` (each via `deleteWithSiblings`, which also removes the
     SQLite `-wal`/`-shm`/`-journal` siblings, `NodeRuntime.kt:374-381`), clear the
     `logoschat_secure` SharedPreferences, delete
     `filesDir/chat-images` recursively, `ChatRepo.wipeAndReinit(context)` (`:490-495`;
     file-name constants `NodeRuntime.kt:40, 43, 44`, prefs name `:37`).
   - **Install the seed:** `File(identityPath(context)).writeBytes(seed)` (`:499`) — i.e. the raw 64
     bytes are written to `filesDir/logoschat-identity.bin` (`NodeRuntime.kt:40, 97-98`).
   - `ChatDb.importJson(chatJson)` (`:507`); a throw here yields the *partial* outcome
     (`PARTIAL_RESTORE_PREFIX = "identity restored, but the chat history was not: "`,
     `NodeRuntime.kt:52`).
   - `startBlocking()` (`:514`) → `prepareIdentity` no-ops (no `.enc` present) →
     ```kotlin
     NodeBridge.chatOpenPersistent(storePath(context), dbKey(context), null, identityPath(context))
     ```
     `NodeRuntime.kt:278-280`.

**The parameter that receives the identity is `chatOpenPersistent`'s 4th argument,
`identityPath: String`** (`NodeBridge.kt:56-61`) → native `logoschat_open_persistent(db_path,
db_key, registry_url, identity_path)` (`liblogoschat.h:51-53`). The seed is **never passed as bytes
across the FFI** — it is passed as a *filesystem path to a 64-byte file*. A desktop port must do the
same: write `b64decode(identity)` (64 bytes, no header, no trailing newline) to a file and pass that
path to `open_persistent`. Afterwards `sealIdentity` re-encrypts it and deletes the plaintext
(`NodeRuntime.kt:291, 195-210`) — that is Android-Keystore-specific and has no bearing on the file
format.

Restore is destructive and irreversible; the address that comes back is
`NodeRuntime.address` = `chatGetAddress(handle)` (`NodeRuntime.kt:289`), returned to JS as the
promise value (`BackupImport.kt:53`, `LogosChatModule.kt:1466`).

---

## 6. Worked description — writing an independent decryptor

```python
import base64, hashlib, json
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

def read_peersenc(path: str, passphrase: str) -> dict:
    env = json.loads(open(path, "r", encoding="utf-8").read())

    if env.get("format") != "peers-backup-enc":
        raise ValueError("not a Peers encrypted backup")
    # 'v' and 'kdf' are NOT checked by the phone; check them anyway.
    if env.get("kdf", "pbkdf2-hmac-sha256") != "pbkdf2-hmac-sha256":
        raise ValueError("unsupported KDF")
    iters = int(env["iters"])
    if not (1 <= iters <= 10_000_000):
        raise ValueError("bad iters")

    salt = base64.b64decode(env["salt"])   # 16 bytes as written
    iv   = base64.b64decode(env["iv"])     # 12 bytes as written
    blob = base64.b64decode(env["ct"])     # ciphertext || 16-byte GCM tag

    key = hashlib.pbkdf2_hmac("sha256", passphrase.encode("utf-8"), salt, iters, 32)
    pt  = AESGCM(key).decrypt(iv, blob, None)   # None = no AAD; raises on wrong pass/tamper
    root = json.loads(pt.decode("utf-8"))

    if root.get("format") != "logos-chat-backup":
        raise ValueError("decrypted payload is not a Peers backup")
    if root.get("schemaVersion") is None:
        raise ValueError("backup has no schemaVersion")
    return root

def identity_seed(root: dict) -> bytes | None:
    b64 = root.get("identity") or ""
    if not b64:
        return None                              # pre-#440 backup: data only
    seed = base64.b64decode(b64)
    assert len(seed) == 64, f"identity seed must be 64 bytes, got {len(seed)}"
    return seed                                  # account seed || delegate seed
```

To restore on desktop: `open(identity_path, "wb").write(identity_seed(root))` then call the desktop
chat core's `open_persistent(db_path, db_key, registry_url_or_null, identity_path)`. Then replay
`root["kv"] / ["conversations"] / ["messages"] / ["group_members"] / ["mesh_map"] /
["mesh_contacts"]` into the desktop store, parent table first, tolerating a missing table key and
refusing rows with unknown columns (mirror `validateImportJson`).

To **write** a `.peersenc` the phone will accept: emit exactly the seven envelope keys with
`format="peers-backup-enc"`, and inside emit `format="logos-chat-backup"` plus a `schemaVersion`
that is `<= 10` (the reading build's `DB_VERSION`), with no row column the phone's schema lacks.

Cost note: 600 000 PBKDF2-HMAC-SHA256 iterations is ~0.3–1 s on a desktop CPU; run it off the UI
thread (Android does — `BackupImport.kt:22-24` runs it on the node executor).

---

## 7. Test-vector plan

### 7.1 Self-consistency vector (generated from this spec, round-trip verified)

Produced with the algorithm above using fixed salt/IV (i.e. it validates that the spec is
internally consistent and that Python's AESGCM matches the described construction — it is **not**
captured from a device):

- passphrase: `correct horse battery staple`
- salt (hex): `000102030405060708090a0b0c0d0e0f` → `AAECAwQFBgcICQoLDA0ODw==`
- iv (hex): `202122232425262728292a2b` → `ICEiIyQlJicoKSor`
- iters: `600000`
- derived key (hex): `ef177144eec9420cbc1093d2a8b344a92bc506d0d4ec9c028dd19f8324d8c1e6`
- plaintext (61 bytes): `{"format":"logos-chat-backup","version":1,"schemaVersion":10}`
- ct blob: 77 bytes = 61 + 16 (tag)

```json
{"format":"peers-backup-enc","v":1,"kdf":"pbkdf2-hmac-sha256","iters":600000,
 "salt":"AAECAwQFBgcICQoLDA0ODw==","iv":"ICEiIyQlJicoKSor",
 "ct":"MbW7Lf9XXbmi5LhtV7iQF0nkWTqkuiXu1gOFqdAB6pOkOMbdoEcIbquF7laB7z8U3FgYzIhj0yV5yREDUkmvdDIpYuVO0/lENyB/l7s="}
```

A desktop decryptor must return exactly the 61-byte plaintext above. (Script kept at
`/extra/tmp/claude-1000/-home-alisher/fad1636f-73f8-4939-ab63-cfcb0c0f59b9/scratchpad/vec.py`.)

### 7.2 Device-captured vectors — the real gate

The repo has **no committed test vector / golden file** for `.peersenc` (searched
`android/app/src/test/**`; `BackupCryptoTest.kt` only does property round-trips). So capture these
from a real phone:

1. **ASCII passphrase, real export.** Export from a phone with ≥1 conversation and ≥2 messages;
   decrypt with the desktop reader; assert `format`, `version==1`, `schemaVersion==10`,
   `len(b64decode(identity))==64`, and that message rows round-trip.
2. **Non-ASCII passphrase** (e.g. `pässwörd-Ω-日本語`). This is the one vector that resolves
   Ambiguity §8.1 — if the desktop decryptor (UTF-8) fails on it, the JCE provider is not using
   UTF-8.
3. **Passphrase with a non-BMP character** (e.g. an emoji, surrogate pair) — same purpose, harder
   case (UTF-16 surrogates vs UTF-8).
4. **Empty tables.** A fresh install with no conversations: assert the arrays are `[]` and that a
   missing/empty table does not break the reader.
5. **No-identity backup.** Not reproducible on a running phone (identity always exists once the node
   opened); synthesise by deleting the `identity` key — assert the desktop reader reports
   "data-only backup" rather than crashing, mirroring `BackupImport.kt:47-50`.
6. **Legacy plaintext `.json`** backup (pre-#361) — assert the reader detects
   `format=="logos-chat-backup"` at the top level and skips decryption.
7. **Negative:** flip one base64 char of `ct` → must fail (tag); wrong passphrase → must fail;
   `format` set to anything else → must be refused before any KDF work.
8. **Round-trip into the phone:** have the desktop write a `.peersenc` and restore it on Android;
   assert the address matches and `validateImportJson` accepts it (this is the only way to prove the
   writer side).
9. **`iters` bound:** `iters = 0` and `iters = 10_000_001` must be refused (matches
   `BackupCrypto.kt:112`).

---

## 8. Ambiguities / things the source does not settle

**8.1 Passphrase → bytes encoding (the one real interop risk).**
`BackupCrypto.deriveKey` passes a `char[]` to `PBEKeySpec` and lets
`SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")` decide how to turn characters into bytes
(`BackupCrypto.kt:122-129`). That conversion is **provider behaviour, not in this repo** — the
Android JCE provider (Conscrypt/BouncyCastle, version-dependent) is not vendored here. For pure
ASCII passphrases every candidate encoding agrees, so ASCII backups are safe. For non-ASCII
passphrases, UTF-8 is the near-certain answer but **must be confirmed empirically** with test
vectors 7.2/2 and 7.2/3 before shipping a desktop reader that claims full compatibility.

**8.2 The internal layout of the 64-byte seed.** Every mention in this repo says
`account seed || delegate seed` (`liblogoschat.h:47`, `NodeRuntime.kt:88`, `docs/m1prime-log.md:19`),
and the surrounding docs imply two Ed25519 32-byte seeds — but the code that parses the file is in
the Rust `libchat` wrapper, which is **not present in this tree** (no `.rs` files; only the prebuilt
`.so` + C header). The 32/32 boundary, byte order, and whether the stored value is a seed vs an
expanded secret key are therefore **not verifiable here**. Treat the 64 bytes as opaque and pass
them whole.

**8.3 JSON key ordering.** Both the envelope and the plaintext are `org.json.JSONObject`
serializations (`BackupCrypto.kt:92`, `ChatDb.kt:1043`, `LogosChatModule.kt:1400`). Nothing in the
source guarantees insertion order in the output. Never parse positionally, and do not attempt to
byte-reproduce a phone-written file.

**8.4 `v` and `kdf` are decorative on read.** `BackupCrypto.decrypt` never reads them
(`BackupCrypto.kt:109-120`). A future format bump would therefore *not* be rejected by an old
Android build in the way the field names suggest — it would fail later at the GCM tag or the JSON
parse. A desktop reader should be stricter than the phone here.

**8.5 Salt/IV length are not validated on read.** The writer always emits 16/12, but a hand-made
file with other lengths would be accepted by `Cipher`/`GCMParameterSpec` (`BackupCrypto.kt:113-118`).
Recommend the desktop reader assert 16 and 12 and reject otherwise.

**8.6 No AAD, so envelope metadata is unauthenticated.** `format`, `v`, `kdf`, `iters` can be
tampered with without a tag failure; only `salt`/`iv`/`ct` are effectively bound (a changed
salt/iters simply derives a wrong key → tag failure). This is a property of the format, not a
reading bug — note it, do not "fix" it in a reader that must stay compatible.

**8.7 Passphrase length asymmetry.** Export enforces ≥8 natively (`LogosChatModule.kt:1392-1394`)
and non-empty inside `encrypt` (`BackupCrypto.kt:84`); import enforces **nothing** natively —
`decrypt` has no passphrase precondition at all, so even `""` derives a key and simply fails the GCM
tag. Only the JS modal gates length on the restore side. A desktop importer may accept any
passphrase, including empty.

**8.8 `schemaVersion` is the reader's gate, and `DB_VERSION` is a moving target** — currently 10
(`ChatDb.kt:58`). A desktop reader must implement the same `schemaVersion > mine → refuse` rule
(`ChatDb.kt:1090-1094`), and must decide its own equivalent of the per-column check
(`ChatDb.kt:1102-1113`) against whatever schema the desktop store uses. The Android rule refuses
**unknown columns**, not missing ones.
