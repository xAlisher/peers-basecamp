//
// Print a running instance's identity, then keep watching its thread so a
// message arriving from a PHONE is visible without re-running anything.
//
//   node tests/whoami.mjs [port] [--watch]
//
import { Inspector, evalq, waitOnline, step, shoot } from "./inspector.mjs";

const PORT = Number(process.argv[2] ?? 5591);
const WATCH = process.argv.includes("--watch");
const app = new Inspector(PORT, "app");

async function main() {
  await app.connect();
  await waitOnline(app);

  const address = await evalq(app, "root.backend.myAddress");
  console.log(`\nADDRESS: ${address}`);
  console.log(`(short: ${await evalq(app, "root.backend.myLabel")})\n`);

  if (!WATCH) {
    app.disconnect();
    process.exit(0);
  }

  step("watching for an incoming conversation / message… (Ctrl-C to stop)");
  let lastConvos = -1;
  let lastMsgs = -1;
  for (;;) {
    const convos = await evalq(app, "root.conversations.length");
    if (convos !== lastConvos) {
      lastConvos = convos;
      step(`conversations: ${convos}`);
      if (convos > 0) {
        // Select the newest so its messages load.
        const id = await evalq(app, "root.conversations[0].convoId");
        await evalq(app, `root.backend.selectConversation(${JSON.stringify(id)})`);
      }
    }
    const msgs = await evalq(app, "root.messages.length");
    if (msgs !== lastMsgs) {
      lastMsgs = msgs;
      if (msgs > 0) {
        const texts = [];
        for (let i = 0; i < msgs; i++) {
          const t = await evalq(app, `root.messages[${i}].text`);
          const own = await evalq(app, `root.messages[${i}].fromSelf`);
          texts.push(`${own ? "me " : "them"}: ${t}`);
        }
        step(`messages (${msgs}):\n  ${texts.join("\n  ")}`);
        await shoot(app, "60-phone-interop.png");
      }
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
}

main().catch((e) => {
  console.error(`FAILED: ${e.message}`);
  process.exit(1);
});
