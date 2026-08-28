#!/usr/bin/env node
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';

process.env.PYTHONDONTWRITEBYTECODE = '1';

const root = resolve(new URL('..', import.meta.url).pathname);
const installerPath = resolve(root, 'scripts/install-iso.sh');
const replacerPath = resolve(root, 'scripts/atomic_replace.py');
const validatorPath = resolve(root, 'scripts/validate_core_package.py');
const coreInstallerPath = resolve(root, 'scripts/install_core_package.py');
const uiValidatorPath = resolve(root, 'scripts/validate_ui_package.py');
const uiInstallerPath = resolve(root, 'scripts/install_ui_package.py');
const targetValidatorPath = resolve(root, 'scripts/validate_iso_target.py');
const source = fs.readFileSync(installerPath, 'utf8');
let failed = false;

function fail(message) {
  console.error(`FAIL: ${message}`);
  failed = true;
}
function requirePattern(pattern, message) {
  if (!pattern.test(source)) fail(message);
}

requirePattern(/set -euo pipefail/, 'installer is not fail-fast');
requirePattern(/flake\.lock[\s\S]*?peers_core[\s\S]*?rev/, 'installer does not resolve the pinned peers_core revision');
requirePattern(/github:xAlisher\/peers-core\/\$\{?CORE_REV\}?/, 'installer does not build the pinned peers_core revision');
requirePattern(/install_core_package\.py"?\s+"\$CORE_NEW"\s+"\$CORE_DEST"/, 'installer does not validate then atomically replace peers_core');
requirePattern(/install_ui_package\.py"?\s+"\$UI_NEW"\s+"\$UI_DEST"/, 'installer does not validate then atomically replace peers_ui');
requirePattern(/safe_extract_lgx\.py"?\s+"\$UI_LGX"\s+"\$SC"/, 'installer does not safely extract peers_ui');
requirePattern(/safe_extract_lgx\.py"?\s+"\$CORE_LGX"\s+"\$SC2"/, 'installer does not safely extract peers_core');
if (/tar\s+x/.test(source)) fail('installer still performs permissive archive extraction');
requirePattern(/ISO=\$\(python3 scripts\/validate_iso_target\.py "\$ISO"\)[\s\S]{0,120}?GUI="\$ISO\/data\/Logos\/LogosBasecamp"/, 'installer does not canonicalize and validate the isolated target');
requirePattern(/artifact_identity\.py[\s\S]{0,500}?--ui-lgx[\s\S]{0,500}?--core-lgx[\s\S]{0,500}?--appimage/, 'final install cannot generate an artifact identity report');
requirePattern(/\[ -s "\$CORE_NEW\/manifest\.json" \]/, 'installer does not validate its staged manifest');
if (/mv\s+"\$CORE_DEST"\s+"\$CORE_OLD"/.test(source))
  fail('installer still creates a window where peers_core is absent');
if (/already present[^\n]*leaving it/.test(source))
  fail('installer silently retains a stale peers_core package');

if (!fs.existsSync(replacerPath)) {
  fail('atomic directory replacement helper is missing');
} else {
  const work = fs.mkdtempSync('/extra/tmp/peers-install-test-');
  try {
    const dest = resolve(work, 'peers_core');
    const staged = resolve(work, '.peers_core.new');
    fs.mkdirSync(dest);
    fs.writeFileSync(resolve(dest, 'version'), 'old');
    fs.mkdirSync(staged);
    fs.writeFileSync(resolve(staged, 'version'), 'new');

    const swapped = spawnSync('python3', [replacerPath, staged, dest], {encoding: 'utf8'});
    if (swapped.status !== 0) fail(`atomic replacement failed: ${swapped.stderr.trim()}`);
    if (fs.readFileSync(resolve(dest, 'version'), 'utf8') !== 'new')
      fail('atomic replacement did not activate the staged core');
    if (fs.existsSync(staged)) fail('old core was not cleaned after atomic replacement');

    const failedStage = resolve(work, '.peers_core.failed');
    fs.mkdirSync(failedStage);
    fs.writeFileSync(resolve(failedStage, 'version'), 'broken');
    const injected = spawnSync('python3', [replacerPath, failedStage, dest], {
      encoding: 'utf8',
      env: {...process.env, PEERS_ATOMIC_REPLACE_TEST_FAIL: 'before-exchange'},
    });
    if (injected.status === 0) fail('injected pre-exchange failure unexpectedly succeeded');
    if (fs.readFileSync(resolve(dest, 'version'), 'utf8') !== 'new')
      fail('pre-exchange failure damaged the working core');

    fs.rmSync(failedStage, {recursive: true, force: true});
    const interruptedStage = resolve(work, '.peers_core.interrupted');
    fs.mkdirSync(interruptedStage);
    fs.writeFileSync(resolve(interruptedStage, 'version'), 'newest');
    const interrupted = spawnSync('python3', [replacerPath, interruptedStage, dest], {
      encoding: 'utf8',
      env: {...process.env, PEERS_ATOMIC_REPLACE_TEST_FAIL: 'after-exchange'},
    });
    if (interrupted.status === 0) fail('injected post-exchange interruption unexpectedly succeeded');
    if (!fs.existsSync(dest)
        || fs.readFileSync(resolve(dest, 'version'), 'utf8') !== 'newest')
      fail('post-exchange interruption left the core absent or rolled back the new core');
    if (!fs.existsSync(resolve(interruptedStage, 'version')))
      fail('post-exchange interruption lost the recoverable old core');
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
}

if (!fs.existsSync(validatorPath) || !fs.existsSync(coreInstallerPath)
    || !fs.existsSync(uiValidatorPath) || !fs.existsSync(uiInstallerPath)) {
  fail('package validator or validate-then-replace helper is missing');
} else {
  const work = fs.mkdtempSync('/extra/tmp/peers-package-test-');
  try {
    const dest = resolve(work, 'peers_core');
    fs.mkdirSync(dest);
    fs.writeFileSync(resolve(dest, 'version'), 'working');

    const valid = resolve(work, 'valid');
    fs.mkdirSync(valid);
    fs.writeFileSync(resolve(valid, 'manifest.json'), JSON.stringify({
      name: 'peers_core', type: 'core', dependencies: ['delivery_module'],
      main: {'linux-amd64': 'peers_core_plugin.so'},
    }));
    fs.writeFileSync(resolve(valid, 'variant'), 'linux-amd64');
    const compile = (output, source, extra = []) => spawnSync('cc', [
      '-shared', '-fPIC', '-x', 'c', '-', '-o', resolve(valid, output), ...extra,
    ], {input: source, encoding: 'utf8'});
    for (const [name, symbol] of [
      ['libssl.so.3', 'ssl_symbol'],
      ['libcrypto.so.3', 'crypto_symbol'],
      ['libboost_system.so.1.87.0', 'boost_symbol'],
    ]) {
      const built = compile(name, `int ${symbol}(void) { return 1; }`, [`-Wl,-soname,${name}`]);
      if (built.status !== 0) fail(`could not compile ${name}: ${built.stderr.trim()}`);
    }
    const plugin = compile('peers_core_plugin.so', `
      extern int ssl_symbol(void); extern int crypto_symbol(void); extern int boost_symbol(void);
      int peers_core_test(void) { return ssl_symbol() + crypto_symbol() + boost_symbol(); }
    `, [
      `-L${valid}`, '-Wl,--no-as-needed', '-Wl,-rpath,$ORIGIN',
      '-Wl,-l:libssl.so.3', '-Wl,-l:libcrypto.so.3', '-Wl,-l:libboost_system.so.1.87.0',
    ]);
    if (plugin.status !== 0) fail(`could not compile plugin: ${plugin.stderr.trim()}`);

    const validResult = spawnSync('python3', [validatorPath, valid], {encoding: 'utf8'});
    if (validResult.status !== 0) fail(`valid ELF package was rejected: ${validResult.stderr.trim()}`);

    let caseNumber = 0;
    function expectRejected(label, mutate) {
      const staged = resolve(work, `.peers_core.reject-${caseNumber++}`);
      fs.cpSync(valid, staged, {recursive: true});
      mutate(staged);
      const result = spawnSync('python3', [coreInstallerPath, staged, dest], {encoding: 'utf8'});
      if (result.status === 0) fail(`${label} reached atomic replacement`);
      if (!fs.existsSync(resolve(dest, 'version'))
          || fs.readFileSync(resolve(dest, 'version'), 'utf8') !== 'working')
        fail(`${label} damaged the working core`);
      fs.rmSync(staged, {recursive: true, force: true});
    }

    for (const name of ['peers_core_plugin.so', 'libssl.so.3', 'libcrypto.so.3',
      'libboost_system.so.1.87.0']) {
      expectRejected(`missing ${name}`, staged => fs.rmSync(resolve(staged, name)));
      expectRejected(`symlinked ${name}`, staged => {
        fs.rmSync(resolve(staged, name));
        fs.symlinkSync(resolve(valid, name), resolve(staged, name));
      });
    }
    expectRejected('unrelated package symlink', staged => {
      fs.symlinkSync(resolve(valid, 'manifest.json'), resolve(staged, 'extra-link'));
    });
    expectRejected('fake ELF payloads', staged => {
      for (const name of ['peers_core_plugin.so', 'libssl.so.3', 'libcrypto.so.3',
        'libboost_system.so.1.87.0']) fs.writeFileSync(resolve(staged, name), '\x7fELFjunk');
    });
    expectRejected('invalid manifest', staged => fs.writeFileSync(resolve(staged, 'manifest.json'), '{'));
    expectRejected('oversized manifest', staged => fs.writeFileSync(resolve(staged, 'manifest.json'), 'x'.repeat(65537)));
    expectRejected('wrong variant', staged => fs.writeFileSync(resolve(staged, 'variant'), 'other'));

    const installable = resolve(work, '.peers_core.valid');
    fs.cpSync(valid, installable, {recursive: true});
    const installed = spawnSync('python3', [coreInstallerPath, installable, dest], {encoding: 'utf8'});
    if (installed.status !== 0) fail(`valid package install failed: ${installed.stderr.trim()}`);
    if (!fs.existsSync(resolve(dest, 'peers_core_plugin.so')) || fs.existsSync(resolve(dest, 'version')))
      fail('valid package did not atomically replace the working core');

    const uiValid = resolve(work, 'valid-ui');
    fs.cpSync(valid, uiValid, {recursive: true});
    fs.renameSync(resolve(uiValid, 'peers_core_plugin.so'), resolve(uiValid, 'peers_ui_plugin.so'));
    const replica = spawnSync('cc', ['-shared', '-fPIC', '-x', 'c', '-', '-o',
      resolve(uiValid, 'peers_ui_replica_factory.so')], {input: 'int replica(void) { return 1; }', encoding: 'utf8'});
    if (replica.status !== 0) fail(`could not compile replica factory: ${replica.stderr.trim()}`);
    fs.mkdirSync(resolve(uiValid, 'qml'));
    const uiAssets = [
      'Peers_sidebar.png', 'metadata.json', 'qml/AddressCard.qml',
      'qml/BubbleActionMenu.qml', 'qml/ClipboardProxy.qml', 'qml/Composer.qml',
      'qml/ContactsPanel.qml', 'qml/ConversationRow.qml', 'qml/EmojiGrid.qml',
      'qml/EmptyState.qml', 'qml/ForwardPicker.qml', 'qml/GroupInfoPanel.qml',
      'qml/HexAvatar.qml', 'qml/Identicon.js', 'qml/MediaViewer.qml',
      'qml/MessageBubble.qml', 'qml/MessageLayout.js', 'qml/PeersIcon.qml',
      'qml/PeersView.qml', 'qml/PinnedBar.qml', 'qml/SettingsPanel.qml',
      'qml/Theme.js', 'qml/Toast.qml', 'qml/icons/Peers_sidebar.png', 'qml/qmldir',
    ];
    for (const relative of uiAssets) {
      const path = resolve(uiValid, relative);
      fs.mkdirSync(dirname(path), {recursive: true});
      fs.writeFileSync(path, relative.endsWith('.json') ? '{}' : 'runtime asset');
    }
    fs.writeFileSync(resolve(uiValid, 'manifest.json'), JSON.stringify({
      name: 'peers_ui', type: 'ui_qml', dependencies: ['peers_core', 'delivery_module'],
      main: {'linux-amd64': 'peers_ui_plugin.so'}, view: 'qml/PeersView.qml',
      icon: 'Peers_sidebar.png',
    }));
    const uiDest = resolve(work, 'peers_ui');
    fs.mkdirSync(uiDest);
    fs.writeFileSync(resolve(uiDest, 'version'), 'working');
    function expectUiRejected(label, mutate) {
      const staged = resolve(work, `.peers_ui.reject-${caseNumber++}`);
      fs.cpSync(uiValid, staged, {recursive: true});
      mutate(staged);
      const result = spawnSync('python3', [uiInstallerPath, staged, uiDest], {encoding: 'utf8'});
      if (result.status === 0) fail(`${label} reached UI atomic replacement`);
      if (fs.readFileSync(resolve(uiDest, 'version'), 'utf8') !== 'working')
        fail(`${label} damaged the working UI`);
      fs.rmSync(staged, {recursive: true, force: true});
    }
    expectUiRejected('missing UI plugin', staged => fs.rmSync(resolve(staged, 'peers_ui_plugin.so')));
    for (const name of ['peers_ui_replica_factory.so', 'libssl.so.3', 'libcrypto.so.3',
      'libboost_system.so.1.87.0', ...uiAssets]) {
      expectUiRejected(`missing UI runtime ${name}`, staged => fs.rmSync(resolve(staged, name)));
    }
    expectUiRejected('symlinked UI view', staged => {
      fs.rmSync(resolve(staged, 'qml/PeersView.qml'));
      fs.symlinkSync(resolve(uiValid, 'qml/PeersView.qml'), resolve(staged, 'qml/PeersView.qml'));
    });
    expectUiRejected('symlinked UI replica', staged => {
      fs.rmSync(resolve(staged, 'peers_ui_replica_factory.so'));
      fs.symlinkSync(resolve(uiValid, 'peers_ui_replica_factory.so'),
        resolve(staged, 'peers_ui_replica_factory.so'));
    });
    expectUiRejected('FIFO package node', staged => {
      const fifo = resolve(staged, 'unexpected-fifo');
      const made = spawnSync('mkfifo', [fifo], {encoding: 'utf8'});
      if (made.status !== 0) fail(`could not create FIFO fixture: ${made.stderr.trim()}`);
    });
    expectUiRejected('unexpected regular file', staged => fs.writeFileSync(resolve(staged, 'extra'), 'x'));
    expectUiRejected('wrong UI manifest', staged => fs.writeFileSync(resolve(staged, 'manifest.json'), '{}'));
    expectUiRejected('extra UI dependency', staged => {
      const manifest = JSON.parse(fs.readFileSync(resolve(staged, 'manifest.json')));
      manifest.dependencies.push('attacker_module');
      fs.writeFileSync(resolve(staged, 'manifest.json'), JSON.stringify(manifest));
    });
    expectUiRejected('extra UI platform entry', staged => {
      const manifest = JSON.parse(fs.readFileSync(resolve(staged, 'manifest.json')));
      manifest.main['evil-platform'] = 'evil.so';
      fs.writeFileSync(resolve(staged, 'manifest.json'), JSON.stringify(manifest));
    });
    expectUiRejected('oversized UI manifest', staged =>
      fs.writeFileSync(resolve(staged, 'manifest.json'), 'x'.repeat(65537)));
    expectUiRejected('wrong UI variant', staged => fs.writeFileSync(resolve(staged, 'variant'), 'other'));
    function corruptElf(staged, name, offset, value) {
      const path = resolve(staged, name);
      const bytes = fs.readFileSync(path);
      bytes[offset] = value;
      fs.writeFileSync(path, bytes);
    }
    expectUiRejected('wrong ELF class', staged => corruptElf(staged, 'peers_ui_plugin.so', 4, 1));
    expectUiRejected('wrong ELF type', staged => corruptElf(staged, 'peers_ui_plugin.so', 16, 2));
    expectUiRejected('wrong ELF architecture', staged => corruptElf(staged, 'peers_ui_plugin.so', 18, 40));
    expectUiRejected('invalid replica ELF', staged =>
      fs.writeFileSync(resolve(staged, 'peers_ui_replica_factory.so'), '\x7fELFjunk'));
    expectUiRejected('excess package entries', staged => {
      const extras = resolve(staged, 'excess');
      fs.mkdirSync(extras);
      for (let i = 0; i < 4097; ++i) fs.writeFileSync(resolve(extras, `${i}`), 'x');
    });
    const uiInstallable = resolve(work, '.peers_ui.valid');
    fs.cpSync(uiValid, uiInstallable, {recursive: true});
    const uiInstalled = spawnSync('python3', [uiInstallerPath, uiInstallable, uiDest], {encoding: 'utf8'});
    if (uiInstalled.status !== 0) fail(`valid UI package install failed: ${uiInstalled.stderr.trim()}`);
    if (!fs.existsSync(resolve(uiDest, 'peers_ui_plugin.so')) || fs.existsSync(resolve(uiDest, 'version')))
      fail('valid UI package did not atomically replace the working UI');
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
}

if (!fs.existsSync(targetValidatorPath)) {
  fail('canonical isolated-target validator is missing');
} else {
  const work = fs.mkdtempSync('/extra/tmp/peers-target-test-');
  try {
    const home = resolve(work, 'home');
    const live = resolve(home, '.local/share/Logos/LogosBasecamp');
    fs.mkdirSync(resolve(live, 'plugins'), {recursive: true});
    fs.mkdirSync(resolve(live, 'modules'));
    const env = {...process.env, HOME: home};

    const safeIso = resolve(work, 'safe-iso');
    const safeGui = resolve(safeIso, 'data/Logos/LogosBasecamp');
    fs.mkdirSync(resolve(safeGui, 'plugins'), {recursive: true});
    fs.mkdirSync(resolve(safeGui, 'modules'));
    const safe = spawnSync('python3', [targetValidatorPath, safeIso], {encoding: 'utf8', env});
    if (safe.status !== 0 || safe.stdout.trim() !== fs.realpathSync(safeIso))
      fail(`safe isolated target was rejected: ${safe.stderr.trim()}`);

    const aliasIso = resolve(work, 'alias-iso');
    fs.mkdirSync(aliasIso);
    fs.symlinkSync(resolve(home, '.local/share'), resolve(aliasIso, 'data'));
    const alias = spawnSync('python3', [targetValidatorPath, aliasIso], {encoding: 'utf8', env});
    if (alias.status === 0) fail('symlink alias to the live installation was accepted');

    const strippedIso = resolve(work, 'newline-iso');
    fs.mkdirSync(strippedIso);
    fs.symlinkSync(resolve(home, '.local/share'), resolve(strippedIso, 'data'));
    const newlineIso = `${strippedIso}\n`;
    const newlineGui = resolve(newlineIso, 'data/Logos/LogosBasecamp');
    fs.mkdirSync(resolve(newlineGui, 'plugins'), {recursive: true});
    fs.mkdirSync(resolve(newlineGui, 'modules'));
    const fakeBin = resolve(work, 'bin');
    const buildMarker = resolve(work, 'nix-was-called');
    fs.mkdirSync(fakeBin);
    fs.writeFileSync(resolve(fakeBin, 'nix'), `#!/bin/sh\ntouch '${buildMarker}'\nexit 99\n`, {mode: 0o755});
    const newline = spawnSync('bash', [installerPath, newlineIso], {
      encoding: 'utf8',
      env: {...env, PATH: `${fakeBin}:${process.env.PATH}`},
    });
    if (newline.status === 0 || fs.existsSync(buildMarker))
      fail('trailing-newline ISO path passed validation and reached the build step');

    const linkedIso = resolve(work, 'linked-child-iso');
    const linkedGui = resolve(linkedIso, 'data/Logos/LogosBasecamp');
    fs.mkdirSync(linkedGui, {recursive: true});
    fs.symlinkSync(resolve(safeGui, 'plugins'), resolve(linkedGui, 'plugins'));
    fs.mkdirSync(resolve(linkedGui, 'modules'));
    const linked = spawnSync('python3', [targetValidatorPath, linkedIso], {encoding: 'utf8', env});
    if (linked.status === 0) fail('symlinked plugin root was accepted');
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
}

if (failed) process.exit(1);
console.log('ok: isolated installer atomically updates validated peers_ui and pinned peers_core packages');
