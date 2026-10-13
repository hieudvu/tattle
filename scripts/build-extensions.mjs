#!/usr/bin/env node
// Lays out the browser extensions under Extensions/dist/ and zips them.
//   Extensions/dist/chromium/  manifest.json, background.js, icons/, core/src/
//   Extensions/dist/firefox/   manifest.json, background.js, icons/, core/src/
//   Extensions/dist/tattle-chromium.zip, Extensions/dist/tattle-firefox.zip
// The wrappers import ./core/src/..., so core/src is copied next to them (one shared copy of the logic).
// Uses only node built-ins and the system `zip`. Run from anywhere: node scripts/build-extensions.mjs

import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const extDir = join(root, 'Extensions');
const distDir = join(extDir, 'dist');
const BROWSERS = ['chromium', 'firefox'];

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

function buildBrowser(name) {
  const src = join(extDir, name);
  const out = join(distDir, name);
  mkdirSync(out, { recursive: true });
  for (const file of ['manifest.json', 'background.js']) {
    cpSync(join(src, file), join(out, file));
  }
  cpSync(join(extDir, 'icons'), join(out, 'icons'), { recursive: true });
  cpSync(join(extDir, 'core', 'src'), join(out, 'core', 'src'), { recursive: true });

  const manifest = readJson(join(out, 'manifest.json'));
  assert.equal(manifest.manifest_version, 3, `${name}: manifest_version`);
  assert.equal(manifest.name, 'Tattle', `${name}: name`);
  assert.ok(manifest.permissions.includes('tabs'), `${name}: tabs permission`);
  assert.ok(manifest.permissions.includes('nativeMessaging'), `${name}: nativeMessaging permission`);
  assert.ok(manifest.permissions.includes('scripting'), `${name}: scripting permission`);
  assert.deepEqual(manifest.host_permissions, ['<all_urls>'], `${name}: host_permissions`);
  for (const size of ['16', '32', '48', '128']) {
    const icon = manifest.icons[size];
    assert.ok(existsSync(join(out, icon)), `${name}: icon ${icon} exists`);
  }
  if (name === 'chromium') {
    assert.equal(manifest.background.service_worker, 'background.js');
    assert.equal(manifest.background.type, 'module');
    assert.ok(typeof manifest.key === 'string' && manifest.key.length > 100, 'chromium: key present');
  } else {
    assert.deepEqual(manifest.background.scripts, ['background.js']);
    assert.equal(manifest.background.type, 'module');
    assert.equal(manifest.browser_specific_settings.gecko.id, 'tattle@hieuvd.dev', 'firefox: gecko id');
  }

  const zipPath = join(distDir, `tattle-${name}.zip`);
  rmSync(zipPath, { force: true });
  execFileSync('zip', ['-r', '-X', '-q', zipPath, '.'], { cwd: out, stdio: 'inherit' });
  return { name, out, zipPath, size: statSync(zipPath).size };
}

rmSync(distDir, { recursive: true, force: true });
mkdirSync(distDir, { recursive: true });
for (const name of BROWSERS) {
  const r = buildBrowser(name);
  console.log(`${r.name}: ${r.out}`);
  console.log(`${r.name}: ${r.zipPath} (${r.size} bytes)`);
}
