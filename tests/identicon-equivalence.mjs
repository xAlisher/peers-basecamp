//
// Proves the QML identicon port is byte-for-byte equivalent to the Peers Android
// implementation, rather than merely "looks similar".
//
// It extracts the real `rng` + `identiconCells` bodies out of the Android
// source (`src/components/HexAvatar.tsx`) at run time, evaluates both that and
// our QML JS library, and diffs their cell lists over a large seed corpus.
//
//   node tests/identicon-equivalence.mjs [path-to-logos-chat-android]
//
// Exits non-zero on any divergence. If the Android checkout is not present, it
// says so and skips rather than silently passing.
//
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const androidRepo =
  process.argv[2] ??
  process.env.PEERS_ANDROID_REPO ??
  resolve(here, '../../../../projects/logos-chat-android');
const androidSrc = resolve(androidRepo, 'src/components/HexAvatar.tsx');
const ourSrc = resolve(here, '../plugins/peers_ui/src/qml/Peers/Identicon.js');

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
}

if (!existsSync(ourSrc)) fail(`our port not found at ${ourSrc}`);

if (!existsSync(androidSrc)) {
  console.error(
    `SKIP: Peers Android checkout not found at ${androidSrc}.\n` +
      `      Pass its path as argv[1] to run the equivalence check.`,
  );
  process.exit(2); // distinct from pass(0) and fail(1) — never a silent pass
}

// ── the reference implementation, lifted verbatim out of the .tsx ────────────
// We slice the source between the ramp declarations and the end of
// identiconCells, strip the TypeScript annotations that plain JS can't parse,
// and evaluate it. Lifting beats copy-pasting: if Android changes the algorithm,
// this test starts failing instead of quietly comparing against a stale copy.
const tsx = readFileSync(androidSrc, 'utf8');

function slice(from, to) {
  const a = tsx.indexOf(from);
  const b = tsx.indexOf(to, a);
  if (a < 0 || b < 0) fail(`could not locate '${from}' … '${to}' in HexAvatar.tsx`);
  return tsx.slice(a, b);
}

const rampBlock = slice("const LOGOS_RAMP", "/** Identity kinds");
const prefixBlock = slice("const PREFIX", "// mulberry32");
const rngBlock = slice("function rng(", "export const AVATAR_N");
const cellsBlock = slice("export function identiconCells(", "\nexport function HexAvatar");

const rampsBlock = `
const RAMPS = { contact: LOGOS_RAMP, group: LOGOS_RAMP, mesh: MESH_RAMP, ble: BLE_RAMP };
`;

const referenceSource = [
  rampBlock,
  rampsBlock,
  prefixBlock,
  rngBlock,
  'const AVATAR_N = 5;',
  cellsBlock,
  'globalThis.__ref_identiconCells = identiconCells;',
]
  .join('\n');

// Strip the TypeScript annotations the lifted blocks carry. Order matters:
// the compound forms must go before the bare `: string` / `: number` rules,
// or those leave a dangling colon behind.
const stripped = referenceSource
  .replace(/:\s*\(\)\s*=>\s*number/g, '')      // rng's return type
  .replace(/:\s*Record<[^>]*>/g, '')            // PREFIX / RAMPS maps
  .replace(/:\s*IdenticonCell\[\]/g, '')        // identiconCells return + locals
  .replace(/:\s*AvatarKind/g, '')               // kind parameter
  .replace(/:\s*string\[\]/g, '')
  .replace(/:\s*string\b/g, '')
  .replace(/:\s*number\b/g, '')
  .replace(/\bexport\s+/g, '');

try {
  // eslint-disable-next-line no-eval
  (0, eval)(stripped);
} catch (e) {
  fail(`could not evaluate the lifted Android implementation: ${e.message}`);
}
const refCells = globalThis.__ref_identiconCells;
if (typeof refCells !== 'function') fail('lifted reference did not define identiconCells');

// ── our port ────────────────────────────────────────────────────────────────
const ourJs = readFileSync(ourSrc, 'utf8').replace(/^\.pragma library\s*$/m, '');
let ourCells;
try {
  // eslint-disable-next-line no-eval
  (0, eval)(`${ourJs}\nglobalThis.__our_identiconCells = identiconCells;`);
  ourCells = globalThis.__our_identiconCells;
} catch (e) {
  fail(`could not evaluate our port: ${e.message}`);
}
if (typeof ourCells !== 'function') fail('our port did not define identiconCells');

// ── corpus ──────────────────────────────────────────────────────────────────
// Real-shaped hex addresses, plus adversarial seeds: empty, unicode, very long,
// and ones differing in a single character (the case a weak hash collapses).
const seeds = [];
for (let i = 0; i < 4000; i++) {
  seeds.push(createHash('sha256').update(`peer-${i}`).digest('hex'));
}
seeds.push(
  '',
  '0',
  '00',
  'a',
  'A',
  'ff'.repeat(32),
  '0'.repeat(64),
  'e'.repeat(1000),
  'héllo-wörld',
  '😀😀',
  'aaaaaaaaaaaaaaaa',
  'aaaaaaaaaaaaaaab',
  'aaaaaaaaaaaaaaac',
);

const kinds = ['contact', 'group'];

let compared = 0;
for (const seed of seeds) {
  for (const kind of kinds) {
    const a = JSON.stringify(refCells(seed, kind));
    const b = JSON.stringify(ourCells(seed, kind));
    if (a !== b) {
      fail(
        `divergence for kind=${kind} seed=${JSON.stringify(seed.slice(0, 40))}\n` +
          `  android: ${a.slice(0, 400)}\n` +
          `  ours   : ${b.slice(0, 400)}`,
      );
    }
    compared++;
  }
}

// ── invariants the port must hold regardless of the reference ───────────────
for (const seed of seeds.slice(0, 200)) {
  const cells = ourCells(seed, 'contact');
  const grid = new Map();
  for (const c of cells) {
    if (!Number.isInteger(c.x) || c.x < 0 || c.x > 4) fail(`x out of range: ${c.x}`);
    if (!Number.isInteger(c.y) || c.y < 0 || c.y > 4) fail(`y out of range: ${c.y}`);
    if (!/^#[0-9A-F]{6}$/i.test(c.fill)) fail(`bad fill: ${c.fill}`);
    const key = `${c.x},${c.y}`;
    if (grid.has(key)) fail(`duplicate cell at ${key} for seed ${seed}`);
    grid.set(key, c.fill);
  }
  // left-right symmetry, including colour
  for (const [key, fill] of grid) {
    const [x, y] = key.split(',').map(Number);
    const mirror = `${4 - x},${y}`;
    if (grid.get(mirror) !== fill) {
      fail(`asymmetry for seed ${seed}: (${x},${y})=${fill} vs (${4 - x},${y})=${grid.get(mirror)}`);
    }
  }
}

// determinism
for (const seed of seeds.slice(0, 100)) {
  if (JSON.stringify(ourCells(seed, 'contact')) !== JSON.stringify(ourCells(seed, 'contact'))) {
    fail(`non-deterministic output for seed ${seed}`);
  }
}

// contact and group must differ (different PREFIX), for most seeds
let differing = 0;
for (const seed of seeds.slice(0, 500)) {
  if (JSON.stringify(ourCells(seed, 'contact')) !== JSON.stringify(ourCells(seed, 'group'))) {
    differing++;
  }
}
if (differing < 400) {
  fail(`contact and group patterns collide too often (${differing}/500 differ) — PREFIX not applied?`);
}

console.log(
  `PASS: identicon port matches Peers Android over ${compared} (seed, kind) pairs; ` +
    `symmetry, determinism, range and prefix invariants hold.`,
);
