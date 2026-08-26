#!/usr/bin/env node
// Deterministic live gallery for every bubble kind. It injects decoded view-model
// rows directly into PeersView, so layout regressions do not depend on delivery.
import { Inspector, evalq, shoot, sleep } from './inspector.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const port = Number(process.argv[2] || 5591);
const outDir = process.env.OUT_DIR || '/extra/tmp/peers-layout';
mkdirSync(outDir, { recursive: true });
const imagePath = `${outDir}/portrait-fixture.png`;
const gifPath = `${outDir}/layout-fixture.gif`;
// A tiny raster fixture avoids exercising the host's unrelated SVG decoder;
// message metadata below remains the source of the portrait aspect ratio.
writeFileSync(imagePath, Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAQAAAAICAIAAABRUclSAAAAE0lEQVR42mP878sAB0wMDLTiAACI7wFcYdlWnAAAAABJRU5ErkJggg==', 'base64'));
// A valid one-pixel GIF exercises AnimatedImage without another checkout or
// the delivery network.
writeFileSync(gifPath, Buffer.from('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==', 'base64'));
const image = pathToFileURL(imagePath).href;
const gif = pathToFileURL(gifPath).href;
const sender = 'b950463e1234567890abcdef1234567890abcdef1234567890abcdef12345678';
const at = 1787695200000;
const common = {state: 'sent', sender, senderLabel: 'Alice', senderHex: 'b950463e', timestampMs: at};
const messages = [
  {...common, key: 'text-short', kind: 'text', fromSelf: false, text: 'Short message'},
  {...common, key: 'text-long', kind: 'text', fromSelf: true, text: 'A long message wraps predictably instead of stretching the bubble beyond the Android seventy-eight percent cap. It remains readable at every pane width.'},
  {...common, key: 'reply', kind: 'reply', fromSelf: false, text: 'Reply body', quotedSender: 'Bob', quotedText: 'The original message stays visually separate.', reactions: [{emoji: '👍', count: 2, mine: true}]},
  {...common, key: 'photo', kind: 'photo', fromSelf: true, text: '📷 Photo', mime: 'image/png', width: 1080, height: 2400, imageUri: image},
  {...common, key: 'gif', kind: 'media', fromSelf: false, text: 'GIF', mime: 'image/gif', width: 320, height: 240, imageUri: gif, localPath: '/tmp/spin.gif'},
  {...common, key: 'loading', kind: 'media', fromSelf: true, text: 'GIF', mime: 'image/gif', width: 1920, height: 1080, imageUri: ''},
  {...common, key: 'fetch-error', kind: 'media', fromSelf: false, text: 'Photo', mime: 'image/jpeg', width: 1920, height: 1080, imageUri: '', mediaError: 'Fetch failed'},
  {...common, key: 'decode-error', kind: 'media', fromSelf: true, text: 'Photo', mime: 'image/jpeg', width: 1920, height: 1080, imageUri: 'file:///does/not-exist-layout-test.jpg'},
  {...common, key: 'file', kind: 'media', fromSelf: false, text: 'Document.pdf', mime: 'application/pdf', width: 0, height: 0},
  {...common, key: 'voice', kind: 'voice', fromSelf: false, text: 'Voice message', durationMs: 127000, waveform: Array.from({length: 200}, (_, i) => (i * 37) % 101), localPath: '/tmp/fake.m4a'},
  {...common, key: 'location', kind: 'location', fromSelf: true, text: 'Location', lat: 52.52, lng: 13.405},
  {...common, key: 'contact', kind: 'contact', fromSelf: false, text: 'Contact: Alice', address: sender, label: 'Alice'},
  {...common, key: 'video', kind: 'media', fromSelf: true, text: 'Video', mime: 'video/mp4', width: 1920, height: 1080, localPath: '/tmp/video.mp4'},
];

function assert(ok, message) {
  if (!ok) throw new Error(message);
}

const app = new Inspector(port, 'layout-gallery');
try {
  await app.connect();
  await evalq(app, `root.messages = ${JSON.stringify(messages)}; thread.visible = true; thread.z = 100; thread.positionViewAtEnd()`);
  await sleep(1200);

  const count = Number(await evalq(app, 'thread.count'));
  assert(count === messages.length, `gallery has ${count} delegates, expected ${messages.length}`);
  const threadWidth = Number(await evalq(app, 'thread.width'));
  const rows = [];
  for (let index = 0; index < count; index++) {
    await evalq(app, `thread.positionViewAtIndex(${index}, ListView.Center)`);
    await sleep(80);
    const row = JSON.parse(await evalq(app, `JSON.stringify((function(){var d=thread.itemAtIndex(${index}); return d ? {w:d.desiredBubbleWidth,max:d.maxBubbleWidth,h:d.implicitHeight,bars:d.voiceBars.length,media:d.mediaSize,displayMediaWidth:d.displayMediaWidth,mediaError:d.mediaError,voiceReady:d.voiceReady} : null})())`));
    assert(row != null, `delegate ${index} was not materialized`);
    assert(row.w > 0 && row.h > 0, `${messages[index].key} has non-positive geometry ${JSON.stringify(row)}`);
    assert(row.w <= threadWidth * 0.78 + 1, `${messages[index].key} exceeds 78% bubble cap`);
    if (messages[index].kind === 'voice') assert(row.bars <= 104, `voice emitted ${row.bars} bars`);
    rows.push({bubble: row.w, height: row.h});
  }

  assert(rows[0].bubble < 180, `short text bubble expanded to ${rows[0].bubble}px`);
  assert(rows[2].bubble >= 230, `reply bubble collapsed to ${rows[2].bubble}px`);
  assert(rows[5].height <= 170, `loading placeholder reserved duplicate media height (${rows[5].height}px)`);
  assert(rows[6].height <= 170, `fetch error reserved duplicate media height (${rows[6].height}px)`);
  assert(rows[7].height <= 170, `decode error reserved duplicate media height (${rows[7].height}px)`);
  assert(rows[8].bubble >= 180, `generic attachment collapsed to ${rows[8].bubble}px`);
  assert(rows[12].height <= 170, `video reserved duplicate media height (${rows[12].height}px)`);

  // Runtime resizing must cap both the bubble and the actual child frame.
  await evalq(app, 'thread.positionViewAtIndex(3, ListView.Center)');
  await sleep(80);
  const narrow = JSON.parse(await evalq(app, `JSON.stringify((function(){var d=thread.itemAtIndex(3); d.width=160; return {w:d.desiredBubbleWidth,max:d.maxBubbleWidth,media:d.displayMediaWidth};})())`));
  assert(narrow.w <= narrow.max, `narrow media bubble ${narrow.w}px exceeds ${narrow.max}px cap`);
  assert(narrow.media <= narrow.max - 4, `narrow media child ${narrow.media}px exceeds bubble interior`);
  await evalq(app, `thread.itemAtIndex(3).width=${threadWidth}`);

  await evalq(app, 'thread.positionViewAtIndex(3, ListView.Center)');
  await sleep(100);
  const photo = JSON.parse(await evalq(app, 'JSON.stringify(thread.itemAtIndex(3).mediaSize)'));
  assert(photo.width === 135 && photo.height === 300, `portrait fit is ${JSON.stringify(photo)}, expected 135x300`);
  await evalq(app, 'thread.positionViewAtIndex(5, ListView.Center)');
  await sleep(100);
  const loading = JSON.parse(await evalq(app, 'JSON.stringify(thread.itemAtIndex(5).mediaSize)'));
  assert(loading.width === 230 && loading.height === 129, `landscape fit is ${JSON.stringify(loading)}, expected 230x129`);

  for (const [index, name] of [[0, 'text-reply'], [3, 'photo'], [4, 'gif'],
                               [6, 'media-errors'], [8, 'generic-file'],
                               [12, 'voice-cards-video']]) {
    await evalq(app, `thread.positionViewAtIndex(${index}, ListView.Center)`);
    await sleep(200);
    await shoot(app, `message-layout-${name}.png`, outDir);
  }
  console.log(`PASS: ${messages.length} bubble variants have bounded, positive geometry; screenshots in ${outDir}`);
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exitCode = 1;
} finally {
  app.disconnect();
}
