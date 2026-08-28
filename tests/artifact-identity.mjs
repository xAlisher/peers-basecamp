#!/usr/bin/env node
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';

const repo = resolve(new URL('..', import.meta.url).pathname);
const reporter = resolve(repo, 'scripts/artifact_identity.py');
let failed = false;
const fail = message => { console.error(`FAIL: ${message}`); failed = true; };

if (!fs.existsSync(reporter)) {
  fail('artifact identity reporter is missing');
} else {
  const work = fs.mkdtempSync('/extra/tmp/peers-artifact-test-');
  try {
    const uiRoot = resolve(work, 'ui-package');
    const coreRoot = resolve(work, 'core-package');
    for (const root of [uiRoot, coreRoot]) {
      fs.mkdirSync(resolve(root, 'variants/linux-amd64'), {recursive: true});
    }
    fs.writeFileSync(resolve(uiRoot, 'manifest.json'), '{"name":"peers_ui"}\n');
    fs.writeFileSync(resolve(uiRoot, 'variants/linux-amd64/PeersView.qml'), 'Item {}\n');
    fs.writeFileSync(resolve(coreRoot, 'manifest.json'), '{"name":"peers_core"}\n');
    fs.writeFileSync(resolve(coreRoot, 'variants/linux-amd64/peers_core_plugin.so'), 'core-bytes\n');

    const uiLgx = resolve(work, 'peers-ui.lgx');
    const coreLgx = resolve(work, 'peers-core.lgx');
    for (const [archive, root] of [[uiLgx, uiRoot], [coreLgx, coreRoot]]) {
      const tar = spawnSync('tar', ['czf', archive, '-C', root, '.'], {encoding: 'utf8'});
      if (tar.status !== 0) fail(`fixture archive failed: ${tar.stderr.trim()}`);
    }

    const iso = resolve(work, 'iso');
    const gui = resolve(iso, 'data/Logos/LogosBasecamp');
    const installedUi = resolve(gui, 'plugins/peers_ui');
    const installedCore = resolve(gui, 'modules/peers_core');
    fs.mkdirSync(installedUi, {recursive: true});
    fs.mkdirSync(installedCore, {recursive: true});
    fs.cpSync(resolve(uiRoot, 'variants/linux-amd64'), installedUi, {recursive: true});
    fs.cpSync(resolve(coreRoot, 'variants/linux-amd64'), installedCore, {recursive: true});
    fs.copyFileSync(resolve(uiRoot, 'manifest.json'), resolve(installedUi, 'manifest.json'));
    fs.copyFileSync(resolve(coreRoot, 'manifest.json'), resolve(installedCore, 'manifest.json'));
    fs.writeFileSync(resolve(installedUi, 'variant'), 'linux-amd64');
    fs.writeFileSync(resolve(installedCore, 'variant'), 'linux-amd64');
    fs.mkdirSync(resolve(installedUi, 'media-cache'));
    fs.writeFileSync(resolve(installedUi, 'media-cache/private-runtime-object'), 'not release payload\n');
    const appImage = resolve(work, 'Basecamp.AppImage');
    fs.writeFileSync(appImage, 'basecamp\n');
    const output = resolve(work, 'identity.json');
    const coreRev = '1'.repeat(40);
    const args = [reporter, '--ui-lgx', uiLgx, '--core-lgx', coreLgx,
      '--iso', iso, '--appimage', appImage, '--core-rev', coreRev, '--output', output];

    const good = spawnSync('python3', args, {encoding: 'utf8'});
    if (good.status !== 0) fail(`matching payload rejected: ${good.stderr.trim()}`);
    if (!fs.existsSync(output)) fail('identity report was not written');
    else {
      const report = JSON.parse(fs.readFileSync(output, 'utf8'));
      if (report.schema !== 1 || report.peers_core_revision !== coreRev)
        fail('identity report schema or pinned revision is wrong');
      for (const key of ['basecamp_appimage', 'peers_ui_lgx', 'peers_core_lgx']) {
        if (!/^[0-9a-f]{64}$/.test(report.artifacts?.[key]?.sha256 ?? ''))
          fail(`${key} SHA-256 is missing`);
      }
      if (report.components?.peers_ui?.file_count !== 3
          || report.components?.peers_core?.file_count !== 3)
        fail('installed payload file counts are wrong');
      if (JSON.stringify(report).includes('private-runtime-object'))
        fail('runtime cache contents leaked into the identity report');
    }

    const previous = fs.readFileSync(output, 'utf8');
    fs.writeFileSync(resolve(installedUi, 'PeersView.qml'), 'changed\n');
    const changed = spawnSync('python3', args, {encoding: 'utf8'});
    if (changed.status === 0) fail('changed installed payload was accepted');
    if (fs.readFileSync(output, 'utf8') !== previous) fail('failed verification replaced the last good report');
    fs.writeFileSync(resolve(installedUi, 'PeersView.qml'), 'Item {}\n');

    fs.writeFileSync(resolve(installedCore, 'unexpected'), 'extra\n');
    const extra = spawnSync('python3', args, {encoding: 'utf8'});
    if (extra.status === 0) fail('extra installed payload was accepted');
    fs.rmSync(resolve(installedCore, 'unexpected'));

    fs.rmSync(resolve(installedCore, 'peers_core_plugin.so'));
    fs.symlinkSync('/etc/passwd', resolve(installedCore, 'peers_core_plugin.so'));
    const linked = spawnSync('python3', args, {encoding: 'utf8'});
    if (linked.status === 0) fail('symlinked installed payload was accepted');
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
}

if (failed) process.exit(1);
console.log('ok: final artifact identity is deterministic and matches installed payloads');
