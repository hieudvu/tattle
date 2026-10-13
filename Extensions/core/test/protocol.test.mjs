import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildHello, buildTabs, buildResult, validateCommand, NATIVE_HOSTS, COMMANDS } from '../src/protocol.js';

test('buildHello carries v:1 and the fields the protocol doc names', () => {
  assert.deepEqual(buildHello({ browser: 'chrome', extensionVersion: '0.1.0' }),
    { v: 1, type: 'hello', browser: 'chrome', extensionVersion: '0.1.0' });
});

test('buildTabs wraps a snapshot with v:1 and browser', () => {
  const tabs = [{ id: '1:2', title: 't', url: 'u', audible: true, muted: false }];
  assert.deepEqual(buildTabs({ browser: 'edge', tabs }), { v: 1, type: 'tabs', browser: 'edge', tabs });
});

test('buildResult ok and error shapes echo the command id', () => {
  assert.deepEqual(buildResult({ id: 'abc', ok: true }), { v: 1, type: 'result', id: 'abc', ok: true });
  assert.deepEqual(buildResult({ id: 'abc', ok: false, error: 'tab not found' }),
    { v: 1, type: 'result', id: 'abc', ok: false, error: 'tab not found' });
});

test('buildResult coerces a missing error into a string', () => {
  const r = buildResult({ id: 'x', ok: false });
  assert.equal(typeof r.error, 'string');
  assert.ok(r.error.length > 0);
});

test('validateCommand accepts every protocol command', () => {
  for (const command of COMMANDS) {
    const r = validateCommand({ v: 1, type: 'command', id: 'b2c1', command, tabId: '12:345' });
    assert.equal(r.ok, true, command);
    assert.deepEqual(r.command, { id: 'b2c1', command, tabId: '12:345' });
  }
  assert.deepEqual(COMMANDS, ['mute', 'unmute', 'pause', 'close', 'focus']);
});

test('validateCommand rejects a wrong protocol version but keeps the id for a reply', () => {
  const r = validateCommand({ v: 2, type: 'command', id: 'x', command: 'mute', tabId: '1:2' });
  assert.equal(r.ok, false);
  assert.equal(r.id, 'x');
  assert.match(r.error, /version/);
});

test('validateCommand rejects a missing version', () => {
  const r = validateCommand({ type: 'command', id: 'x', command: 'mute', tabId: '1:2' });
  assert.equal(r.ok, false);
});

test('validateCommand rejects an unexpected type', () => {
  const r = validateCommand({ v: 1, type: 'tabs', id: 'x', command: 'mute', tabId: '1:2' });
  assert.equal(r.ok, false);
  assert.equal(r.id, 'x');
});

test('validateCommand rejects an unknown command and still reports the id', () => {
  const r = validateCommand({ v: 1, type: 'command', id: 'x', command: 'explode', tabId: '1:2' });
  assert.equal(r.ok, false);
  assert.equal(r.id, 'x');
  assert.match(r.error, /unknown command/);
});

test('validateCommand rejects a missing or empty tabId', () => {
  assert.equal(validateCommand({ v: 1, type: 'command', id: 'x', command: 'mute' }).ok, false);
  assert.equal(validateCommand({ v: 1, type: 'command', id: 'x', command: 'mute', tabId: '' }).ok, false);
  assert.equal(validateCommand({ v: 1, type: 'command', id: 'x', command: 'mute', tabId: 7 }).ok, false);
});

test('validateCommand without an id cannot be answered, so id is undefined', () => {
  const r = validateCommand({ v: 1, type: 'command', command: 'mute', tabId: '1:2' });
  assert.equal(r.ok, false);
  assert.equal(r.id, undefined);
});

test('validateCommand never throws on junk input', () => {
  for (const junk of [null, undefined, 'string', 42, [], true]) {
    const r = validateCommand(junk);
    assert.equal(r.ok, false);
  }
});

test('NATIVE_HOSTS are the dev and production host names from ExtensionIdentity', () => {
  assert.deepEqual([...NATIVE_HOSTS], ['dev.hieuvd.tattle', 'dev.hieuvd.tattle.dev']);
});
