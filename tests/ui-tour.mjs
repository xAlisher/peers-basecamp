//
// UI tour — screenshot every panel of the shell.
//
// The messaging scenarios only ever exercise the Chats section, so the Contacts
// and Settings panels could rot unseen. This drives the section switcher on ONE
// instance and captures each pane, and fails if a panel renders empty.
//
//   node tests/ui-tour.mjs [port]
//
// Exit codes: 0 pass · 1 a panel did not render.
//
import {
  Inspector,
  evalq,
  waitFor,
  waitOnline,
  step,
  shoot,
  dump,
  EXIT_OK,
  EXIT_FAIL,
} from "./inspector.mjs";

const PORT = Number(process.argv[2] ?? 5591);
const app = new Inspector(PORT, "app");

// Probe the PANEL, not the property we just set. Re-reading `root.section`
// proves only that the assignment worked — the first version of this test did
// exactly that and passed while the panel was blank.
async function assertVisible(what, id) {
  const ok = await evalq(app, `${id}.visible && ${id}.width > 0 && ${id}.height > 0`);
  if (!ok) throw new Error(`${what} is not visible (checked ${id}.visible/width/height)`);
  step(`  ${what}: visible`);
}

// The inspector grabs whatever frame is current, so a capture issued straight
// after a property change catches the PREVIOUS frame — the first run of this
// test filed "settings" screenshots that showed contacts. Let the scene settle.
async function settle(ms = 1200) {
  await new Promise((r) => setTimeout(r, ms));
}

async function main() {
  await app.connect();
  await waitOnline(app);
  step("Online");

  // ── chats (empty) ───────────────────────────────────────────────────────
  await evalq(app, 'root.section = "chats"');
  await settle();
  await shoot(app, "40-chats.png");

  // ── contacts ────────────────────────────────────────────────────────────
  await evalq(app, 'root.section = "contacts"');
  await waitFor(async () => await evalq(app, "contactsPanel.visible"), {
    timeout: 5000,
    what: "the contacts panel to become visible",
  });
  await assertVisible("contacts panel", "contactsPanel");
  await assertVisible("address card (right pane)", "addressCard");
  await settle();
  await shoot(app, "41-contacts.png");

  // ── settings ────────────────────────────────────────────────────────────
  await evalq(app, 'root.section = "settings"');
  await waitFor(async () => await evalq(app, "settingsPanel.visible"), {
    timeout: 5000,
    what: "the settings panel to become visible",
  });
  await assertVisible("settings panel", "settingsPanel");
  await settle();
  await shoot(app, "42-settings.png");

  // ── new-chat dialog ─────────────────────────────────────────────────────
  await evalq(app, 'root.section = "chats"');
  await evalq(app, "newChatDialog.open()");
  await waitFor(async () => (await evalq(app, "newChatDialog.visible")) === true, {
    timeout: 5000,
    what: "the new-chat dialog to open",
  });
  await settle();
  await shoot(app, "43-new-chat-dialog.png");
  step("  new-chat dialog: rendered");
  await evalq(app, "newChatDialog.close()");

  console.log("\nPASS: every panel rendered; screenshots 40-43.");
  app.disconnect();
  process.exit(EXIT_OK);
}

main().catch(async (e) => {
  console.error(`\nFAILED: ${e.message}`);
  try {
    await dump(app);
  } catch {
    /* best effort */
  }
  process.exit(EXIT_FAIL);
});
