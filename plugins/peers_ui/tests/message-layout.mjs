import fs from "node:fs";
import path, { resolve } from "node:path";
import { pathToFileURL } from "node:url";

// Builder-native packaged-QML regression gate:
//   nix build .#integration-test --accept-flake-config -L
const framework = process.env.LOGOS_QT_MCP
  || new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(framework, "test-framework/framework.mjs"));

async function evalq(app, expression, objectId) {
  const reply = await app.inspector.send("evaluate", {
    expression, ...(objectId ? {objectId} : {}),
  });
  if (reply.error) throw new Error(reply.error);
  return reply.result !== undefined ? reply.result : reply.value;
}

function assert(ok, message) {
  if (!ok) throw new Error(message);
}

const fixtureDir = process.env.LOGOS_DATA_DIR || "/tmp";
// Hosted media cache files intentionally have no extension. Keep the fixture
// identical to that production shape so decoder sniffing is covered.
const animatedGifPath = path.join(fixtureDir, "peers-animated-fixture");
fs.mkdirSync(fixtureDir, {recursive: true});
fs.writeFileSync(animatedGifPath, Buffer.from(
  "R0lGODlhBAAEAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQADAAAACwAAAAABAAEAAAICQABCBxIsCCAgAAh+QQBDAABACwAAAAABAAEAIEAAP8AAAAAAAAAAAAICQABCBxIsCCAgAA7",
  "base64"));
const animatedGifUri = pathToFileURL(animatedGifPath).href;

const sender = "b950463e1234567890abcdef1234567890abcdef1234567890abcdef12345678";
const common = {
  state: "sent", sender, senderLabel: "Alice", senderHex: "b950463e",
  timestampMs: 1787695200000, reactions: [], folded: false,
};
const fixtures = [
  {...common, key: "text-in", kind: "text", fromSelf: false, text: "Short message"},
  {...common, key: "text-out", kind: "text", fromSelf: true, state: "pending", text: "Pending"},
  {...common, key: "failed", kind: "text", fromSelf: true, state: "failed", text: "Failed"},
  {...common, key: "reply", kind: "reply", fromSelf: false, text: "Reply body", quotedSender: "Bob", quotedText: "Original"},
  {...common, key: "photo-loading", kind: "media", fromSelf: true, text: "Photo", mime: "image/jpeg", width: 1920, height: 1080, imageUri: ""},
  {...common, key: "photo-error", kind: "media", fromSelf: false, text: "Photo", mime: "image/jpeg", width: 1920, height: 1080, imageUri: "", mediaError: "Fetch failed"},
  {...common, key: "file", kind: "media", fromSelf: false, text: "Document.pdf", mime: "application/pdf"},
  {...common, key: "voice", kind: "voice", fromSelf: false, text: "Voice message", durationMs: 127000, waveform: Array.from({length: 256}, (_, i) => (i * 37) % 101), localPath: "/tmp/fixture.m4a"},
  {...common, key: "location", kind: "location", fromSelf: true, lat: 52.52, lng: 13.405},
  {...common, key: "contact", kind: "contact", fromSelf: false, label: "Alice", address: sender},
  {...common, key: "video", kind: "media", fromSelf: true, text: "Video", mime: "video/mp4", width: 1920, height: 1080, localPath: "/tmp/fixture.mp4"},
];

test("peers_ui: packaged message delegates have bounded Android-parity geometry", async (app) => {
  await app.waitFor(async () => {
    const ready = await evalq(app, "typeof root !== 'undefined'");
    if (!ready) throw new Error("PeersView has not loaded");
  }, {timeout: 15000, interval: 250, description: "PeersView to load"});

  for (let index = 0; index < fixtures.length; index++) {
    const objectName = `peers-layout-fixture-${index}`;
    const created = await evalq(app, `(function(){
      var c=Qt.createComponent(Qt.resolvedUrl("MessageBubble.qml"));
      if(c.status!==Component.Ready)return "ERROR: "+c.errorString();
      var o=c.createObject(root,{objectName:${JSON.stringify(objectName)},msg:${JSON.stringify(fixtures[index])},width:640,x:400,y:80,visible:true,z:1000});
      return o?o.objectName:"ERROR: createObject returned null";
    })()`);
    assert(created === objectName, `${fixtures[index].key} creation failed: ${created}`);

    const match = await app.findByProperty("objectName", objectName);
    assert(!match.error && match.matches?.length, `${fixtures[index].key} object not found`);
    const objectId = match.matches[0].id;
    const row = JSON.parse(await evalq(app,
      "JSON.stringify({w:desiredBubbleWidth,max:maxBubbleWidth,h:implicitHeight,status:statusText,media:displayMediaWidth})",
      objectId));
    assert(Number.isFinite(row.w) && Number.isFinite(row.h), `${fixtures[index].key} has non-finite geometry`);
    assert(row.w > 0 && row.h > 0, `${fixtures[index].key} collapsed`);
    assert(row.w <= 640 * 0.78 + 1, `${fixtures[index].key} exceeds 78% cap`);
    if (fixtures[index].state === "sent")
      assert(/^\d{2}:\d{2}$/.test(row.status), `${fixtures[index].key} timestamp is not Android HH:mm: ${row.status}`);

    if (fixtures[index].key === "photo-loading") {
      const narrow = JSON.parse(await evalq(app,
        "width=160;JSON.stringify({w:desiredBubbleWidth,max:maxBubbleWidth,media:displayMediaWidth})",
        objectId));
      assert(narrow.w <= narrow.max, "narrow media bubble exceeds its cap");
      assert(narrow.media <= narrow.max - 4, "narrow media child exceeds the bubble interior");
    }
    if (fixtures[index].key === "text-in") {
      const bodyName = `${objectName}-body`;
      const bodyMatch = await app.findByProperty("objectName", bodyName);
      assert(!bodyMatch.error && bodyMatch.matches?.length,
        "message body is not exposed as a selectable text control");
      const bodyId = bodyMatch.matches[0].id;
      const body = JSON.parse(await evalq(app,
        "select(0,5);JSON.stringify({readOnly:readOnly,selectByMouse:selectByMouse,textFormat:textFormat,selectedText:selectedText})",
        bodyId));
      assert(body.readOnly === true, "message text must be read-only");
      assert(body.selectByMouse === true, "message text must support mouse selection");
      assert(body.textFormat === 0, "peer message text must remain plain text");
      assert(body.selectedText === "Short", `message selection failed: ${JSON.stringify(body)}`);
    }
    if (fixtures[index].key === "reply") {
      const quoteMatch = await app.findByProperty("objectName", `${objectName}-quote-body`);
      assert(!quoteMatch.error && quoteMatch.matches?.length,
        "quoted message body is not selectable");
      const quote = JSON.parse(await evalq(app,
        "selectAll();JSON.stringify({readOnly:readOnly,selectByMouse:selectByMouse,selectedText:selectedText})",
        quoteMatch.matches[0].id));
      assert(quote.readOnly && quote.selectByMouse && quote.selectedText === "Original",
        `quoted message selection failed: ${JSON.stringify(quote)}`);
    }
    if (fixtures[index].key === "video") {
      const playName = `${objectName}-video-play`;
      const playMatch = await app.findByProperty("objectName", playName);
      assert(!playMatch.error && playMatch.matches?.length,
        "video bubble has no dedicated play control");
      const play = JSON.parse(await evalq(app,
        "JSON.stringify({enabled:enabled,role:Accessible.role,name:Accessible.name})",
        playMatch.matches[0].id));
      assert(play.enabled === true, "downloaded video play control is disabled");
      assert(play.role > 0 && play.name === "Play video",
        `video play control is not accessible: ${JSON.stringify(play)}`);
    }
    await evalq(app, "destroy()", objectId);
  }

  const shot = await app.screenshot();
  assert(!shot.error && shot.image && shot.width > 0 && shot.height > 0, `screenshot failed: ${shot.error || "empty image"}`);
  const dir = path.join(process.env.LOGOS_DATA_DIR || "/extra/tmp/peers-layout", "screenshots", "message-layout");
  fs.mkdirSync(dir, {recursive: true});
  fs.writeFileSync(path.join(dir, "packaged-gallery.png"), Buffer.from(shot.image, "base64"));
});

test("peers_ui: media viewer keeps animated GIFs animated", async (app) => {
  const objectName = "peers-animated-media-viewer";
  const created = await evalq(app, `(function(){
    var c=Qt.createComponent(Qt.resolvedUrl("MediaViewer.qml"));
    if(c.status!==Component.Ready)return "ERROR: "+c.errorString();
    var o=c.createObject(root,{objectName:${JSON.stringify(objectName)},images:[{uri:${JSON.stringify(animatedGifUri)},key:"animated-fixture",animated:true,decodeWidth:4,decodeHeight:4}],index:0,width:320,height:240,x:20,y:20,visible:true,z:2000});
    return o?o.objectName:"ERROR: createObject returned null";
  })()`);
  assert(created === objectName, `animated viewer creation failed: ${created}`);

  const animationName = `${objectName}-animation`;
  const observedFrames = new Set();
  await app.waitFor(async () => {
    const match = await app.findByProperty("objectName", animationName);
    if (match.error || !match.matches?.length)
      throw new Error("media viewer has no AnimatedImage renderer");
    const state = JSON.parse(await evalq(app,
      "JSON.stringify({frameCount:frameCount,currentFrame:currentFrame,playing:playing})",
      match.matches[0].id));
    if (state.frameCount >= 2 && state.playing)
      observedFrames.add(state.currentFrame);
    if (observedFrames.size < 2)
      throw new Error(`GIF frame did not advance: ${JSON.stringify(state)}`);
  }, {timeout: 5000, interval: 50, description: "animated GIF viewer to advance frames"});

  const viewer = await app.findByProperty("objectName", objectName);
  await evalq(app, "destroy()", viewer.matches[0].id);
});

run();
