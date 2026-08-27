#!/usr/bin/env node
// Message layout parity gate. The Android implementation is the visual source of
// truth; this test lifts its media/voice limits and checks the QML layout helper
// and component wiring against them.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const android = process.env.PEERS_ANDROID_SRC ?? resolve(root, '../../../projects/logos-chat-android');
const chatTsx = resolve(android, 'src/screens/ChatScreen.tsx');
const voiceTsx = resolve(android, 'src/components/VoiceBubble.tsx');
const helperPath = resolve(root, 'plugins/peers_ui/src/qml/MessageLayout.js');
const bubblePath = resolve(root, 'plugins/peers_ui/src/qml/MessageBubble.qml');
const backendPath = resolve(root, 'plugins/peers_ui/src/PeersUiBackend.cpp');
const mediaToolsPath = resolve(root, 'plugins/peers_ui/src/MediaTools.cpp');
const storageClientPath = resolve(root, 'plugins/peers_ui/src/StorageClient.cpp');

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}
function mustMatch(text, re, label) {
  const match = text.match(re);
  if (!match) throw new Error(`could not lift Android ${label}`);
  return Number(match[1]);
}

if (!existsSync(helperPath)) {
  fail('MessageLayout.js is missing');
  process.exit();
}

const expected = {
  imageMaxWidth: 230, imageMaxHeight: 300, bubbleMaxRatio: 0.78,
  voiceBubbleRatio: 0.72, voiceReserved: 96, voiceMinWave: 96,
  voiceBarWidth: 2, voiceBarGap: 2,
};
// The checked contract keeps this gate effective in standalone checkouts. When
// Android is adjacent, prove the contract still matches its implementation.
if (existsSync(chatTsx) && existsSync(voiceTsx)) {
  const chat = readFileSync(chatTsx, 'utf8');
  const voice = readFileSync(voiceTsx, 'utf8');
  const lifted = {
    imageMaxWidth: mustMatch(chat, /const IMG_MAX_W = (\d+);/, 'IMG_MAX_W'),
    imageMaxHeight: mustMatch(chat, /const IMG_MAX_H = (\d+);/, 'IMG_MAX_H'),
    bubbleMaxRatio: mustMatch(readFileSync(resolve(android, 'src/theme/spacing.ts'), 'utf8'), /bubbleMaxWidthPct: '(\d+)%'/, 'bubble max width') / 100,
    voiceBubbleRatio: mustMatch(voice, /const MAX_BUBBLE_FRACTION = ([\d.]+);/, 'voice bubble fraction'),
    voiceReserved: mustMatch(voice, /const RESERVED_PX = (\d+);/, 'voice reserved width'),
    voiceMinWave: mustMatch(voice, /const MIN_WAVE_PX = (\d+);/, 'voice minimum waveform width'),
    voiceBarWidth: mustMatch(voice, /const BAR_W = (\d+);/, 'voice bar width'),
    voiceBarGap: mustMatch(voice, /const BAR_GAP = (\d+);/, 'voice bar gap'),
  };
  for (const [name, value] of Object.entries(lifted))
    if (expected[name] !== value) fail(`${name}: checked contract ${expected[name]} != Android ${value}`);
}

const source = readFileSync(helperPath, 'utf8').replace(/^\.pragma library\s*$/m, '');
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, {filename: helperPath});

for (const [name, value] of Object.entries(expected)) {
  if (sandbox[name] !== value) fail(`${name}: QML ${sandbox[name]} != Android ${value}`);
}

const cases = [
  [0, 0, 1, 1],
  [100, 100, 100, 100],
  [400, 200, 230, 115],
  [200, 600, 100, 300],
  [1920, 1080, 230, 129],
];
for (const [w, h, ew, eh] of cases) {
  const got = sandbox.fitMedia(w, h);
  if (got.width !== ew || got.height !== eh)
    fail(`fitMedia(${w}, ${h}) = ${JSON.stringify(got)}, expected ${ew}x${eh}`);
}

const samples = Array.from({length: 200}, (_, i) => i % 101);
const maxWave = sandbox.voiceWaveWidth(1000);
const bars = sandbox.downsampleWaveform(samples, maxWave);
const maxBars = Math.max(1, Math.floor(maxWave / (expected.voiceBarWidth + expected.voiceBarGap)));
if (bars.length !== maxBars) fail(`voice downsample emitted ${bars.length} bars, expected ${maxBars}`);
if (sandbox.downsampleWaveform([8, 16, 24], maxWave).join(',') !== '8,16,24')
  fail('short voice waveform was changed instead of staying compact');
for (const pane of [120, 160, 200, 240]) {
  const maxBubble = Math.floor(pane * expected.bubbleMaxRatio);
  const wave = sandbox.voiceWaveWidth(pane);
  const bubble = Math.min(maxBubble, wave + expected.voiceReserved);
  if (bubble - 24 < wave + 58)
    fail(`voice controls overflow ${pane}px pane: ${bubble - 24}px inner < ${wave + 58}px content`);
}

const qml = readFileSync(bubblePath, 'utf8');
const backend = readFileSync(backendPath, 'utf8');
const mediaTools = readFileSync(mediaToolsPath, 'utf8');
const storageClient = readFileSync(storageClientPath, 'utf8');
if (!qml.includes('import "MessageLayout.js" as MessageLayout')) fail('MessageBubble does not import MessageLayout');
if (!qml.includes('MessageLayout.fitMedia')) fail('message media dimensions do not use the stable fit helper');
if (!qml.includes('MessageLayout.downsampleWaveform')) fail('voice waveform is not bounded/downsampled');
if (!qml.includes('displayMediaWidth') || !qml.includes('Math.min(maxBubbleWidth, displayMediaWidth'))
  fail('rendered media is not capped to the current pane width');
if (!qml.includes('gif.status === Image.Error') || !qml.includes('photo.status === Image.Error'))
  fail('image/GIF decoder failures have no visible state');
if (!/AnimatedImage\s*\{[\s\S]{0,900}?sourceSize\.width:\s*640[\s\S]{0,200}?cache:\s*false/.test(qml))
  fail('animated GIF decoding is not bounded and cache-disabled');
if (!qml.includes('enabled: root.voiceReady')) fail('voice playback is enabled without local media');
if (!/id:\s*attributionAvatar[\s\S]*?size:\s*16/.test(qml)) fail('incoming attribution does not contain Android-sized 16px avatar');
if (/HexAvatar\s*\{[\s\S]{0,180}?size:\s*28\b/.test(qml))
  fail('detached 28px message avatar is still present');
if (!/clip:\s*true/.test(qml)) fail('media frame does not clip images/GIFs to its rounded bubble');
if (!/bool PeersUiBackend::playVideo\([\s\S]*?"ffplay"[\s\S]*?"-autoexit"/.test(backend))
  fail('video playback does not use the managed ffplay path');
if (!/bool PeersUiBackend::playVideo\([\s\S]*?"-protocol_whitelist"[\s\S]*?"file,crypto,data"/.test(backend))
  fail('video playback does not restrict nested media protocols to local data');
const audioPlayerSource = backend.match(/bool PeersUiBackend::playAudio\([\s\S]*?\n}\n\nbool PeersUiBackend::playVideo/)?.[0] ?? '';
if (!/"ffplay"[\s\S]*?"-protocol_whitelist"[\s\S]*?"file,crypto,data"/.test(audioPlayerSource)
    || /\{\s*"mpv"/.test(audioPlayerSource))
  fail('voice playback retains an unrestricted network-capable player path');
if (!/isVideo[\s\S]{0,500}?playVideo\(path, messageId\)/.test(backend))
  fail('video attachments do not route through managed playback');
if (!/if \(isVideo\)[\s\S]{0,500}?No supported video player found[\s\S]{0,500}?return;/.test(backend))
  fail('video playback failure can fall through to an unrestricted external opener');
const openMediaSource = backend.match(/void PeersUiBackend::openMedia\([\s\S]*?\n}\n\nvoid PeersUiBackend::saveMedia/)?.[0] ?? '';
if (/xdg-open|startDetached/.test(openMediaSource))
  fail('peer-controlled attachment can reach an unrestricted desktop opener');
if (!/const bool isVideo[\s\S]{0,1200}?MediaTools::probeMediaSize\(localPath, &w, &h\)/.test(backend))
  fail('video send does not probe real dimensions before encoding store2');
if (!/if \(\(isImage \|\| isVideo\) && \(w < 1 \|\| h < 1\)\)[\s\S]{0,300}?Could not determine media dimensions[\s\S]{0,200}?return;/.test(backend))
  fail('media send can still emit an unreadable 0x0 marker');
if (!/QStringLiteral\("ffprobe"\)[\s\S]{0,700}?"-protocol_whitelist"[\s\S]{0,200}?"file,crypto,data"[\s\S]{0,300}?"-select_streams"[\s\S]{0,100}?"v:0"/.test(mediaTools))
  fail('media dimension probing is absent or permits network protocols');
const downloadSource = storageClient.match(/void StorageClient::downloadDecrypt\([\s\S]*?\n}\n?$/)?.[0] ?? '';
if (!/if \(storageToken\(\)\.isEmpty\(\) && cap\.isEmpty\(\)\)/.test(downloadSource))
  fail('hosted downloads still require a shared bearer even when a per-blob capability exists');
if (!/if \(!storageToken\(\)\.isEmpty\(\) && cap\.isEmpty\(\)\)[\s\S]{0,160}?setRawHeader\("Authorization"/.test(downloadSource))
  fail('hosted download still transmits the legacy bearer with a per-blob capability');
if (!/ContentLengthHeader/.test(downloadSource)
    || !/&QIODevice::readyRead/.test(downloadSource)
    || !/reply->abort\(\)/.test(downloadSource)
    || /const QByteArray blob = reply->readAll\(\)/.test(downloadSource))
  fail('hosted downloads are not bounded before peer-controlled response buffering');
if (!/QString StorageClient::cacheFileFor\(const QString& cid, const QString& mime\)/.test(storageClient)
    || !/cacheFileFor\(cid, mime\)/.test(downloadSource))
  fail('hosted media cache paths do not retain a decoder-safe MIME suffix');
const cachePathSource = storageClient.match(/QString StorageClient::cacheFileFor\([\s\S]*?\n}\n/)?.[0] ?? '';
if (!/MediaTools::mediaCacheDir\(\)/.test(cachePathSource))
  fail('hosted media is materialized outside the module-local QML-readable cache');
const cacheSuffixSource = storageClient.match(/QString StorageClient::cacheSuffixForMime\([\s\S]*?\n}\n/)?.[0] ?? '';
if (!/image\/jpeg[\s\S]*?\.jpg/.test(cacheSuffixSource)
    || !/image\/png[\s\S]*?\.png/.test(cacheSuffixSource)
    || !/return QStringLiteral\("\.bin"\)/.test(cacheSuffixSource))
  fail('hosted cache suffixes are not fixed/allowlisted with a safe .bin fallback');
const uploadSource = storageClient.match(/void StorageClient::uploadEncrypted\([\s\S]*?\n}\n\n\/\/ ── download/)?.[0] ?? '';
if (!/\/data\/upload-challenges/.test(uploadSource)
    || !/\/data\/upload-grants/.test(uploadSource)
    || !/X-Upload-Grant/.test(uploadSource))
  fail('hosted uploads do not use the one-use upload-grant protocol');
if (/setRawHeader\("Authorization"/.test(uploadSource) || /if \(!uploadConfigured\(\)\)/.test(uploadSource))
  fail('hosted uploads still depend on a reusable bearer credential');
if (!/QThread::create/.test(uploadSource))
  fail('upload proof-of-work is not kept off the Basecamp UI thread');
if (/exactInteger\(const QJsonValue&/.test(storageClient)
    || !/exactIntegerToken\(const QByteArray& token/.test(storageClient)
    || !/toLongLong\(&ok, 10\)/.test(storageClient))
  fail('upload grant integers are not validated from exact integral JSON tokens');
if (/globalMatch\(QString::fromUtf8\(body\)\)/.test(storageClient)
    || !/challengeTokens\.value\(QStringLiteral\("difficulty"\)\)/.test(storageClient)
    || !/grantTokens\.value\(QStringLiteral\("max_bytes"\)\)/.test(storageClient))
  fail('upload grant integers are not bound to their decoded top-level members');
if (/QString::fromUtf8\(uploadBody\)\.trimmed\(\)/.test(uploadSource)
    || !/QString::fromUtf8\(uploadBody\)/.test(uploadSource))
  fail('upload response accepts whitespace instead of the exact cid:cap form');
if (!/info\.size\(\).*maxHostedPlaintextBytes/s.test(backend))
  fail('hosted media size is not rejected before reading the selected file');
if (!/f\.read\(StorageClient::maxHostedPlaintextBytes\(\) \+ 1\)/.test(backend)
    || /const QByteArray bytes = f\.readAll\(\)/.test(backend))
  fail('hosted file reads are not bounded against metadata and symlink races');
if (!/readError != QFile::NoError/.test(backend))
  fail('partial hosted file reads are not rejected');
if (!/QElapsedTimer/.test(storageClient) || !/std::numeric_limits<qint64>::max\(\)/.test(storageClient))
  fail('upload proof work lacks monotonic and overflow-safe bounds');
if (!/uniqueTopLevelObjectKeys/.test(storageClient)
    || !/if \(!keys\.insert\(key\)\.second\)/.test(storageClient))
  fail('upload grant JSON does not reject duplicate members independent of value type');

if (!process.exitCode) console.log('ok: message layout matches Android sizing and avatar/media contracts');
