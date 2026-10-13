import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createNativeTransport } from '../src/webext/nativeTransport.js';

function fakeChrome() {
  const port = {
    posted: [],
    disconnected: 0,
    error: undefined,
    onMessage: { listeners: new Set(), addListener(cb) { this.listeners.add(cb); } },
    onDisconnect: { listeners: new Set(), addListener(cb) { this.listeners.add(cb); } },
    postMessage(m) { this.posted.push(m); },
    disconnect() { this.disconnected += 1; },
  };
  const api = {
    connectedWith: [],
    lastError: undefined,
    runtime: {
      connectNative(name) { api.connectedWith.push(name); return port; },
    },
  };
  return { api, port };
}

test('connects to the given native host and posts messages to the port', () => {
  const { api, port } = fakeChrome();
  const t = createNativeTransport(api, 'dev.hieuvd.tattle');
  assert.deepEqual(api.connectedWith, ['dev.hieuvd.tattle']);
  assert.equal(t.send({ v: 1, type: 'hello' }), true);
  assert.deepEqual(port.posted, [{ v: 1, type: 'hello' }]);
});

test('onMessage delivers host messages to every subscriber and unsubscribe works', () => {
  const { api, port } = fakeChrome();
  const t = createNativeTransport(api, 'h');
  const a = [];
  const b = [];
  const offA = t.onMessage((m) => a.push(m));
  t.onMessage((m) => b.push(m));
  for (const cb of port.onMessage.listeners) cb({ v: 1, type: 'command' });
  offA();
  for (const cb of port.onMessage.listeners) cb({ v: 1, type: 'x' });
  assert.deepEqual(a, [{ v: 1, type: 'command' }]);
  assert.equal(b.length, 2);
});

test('onDisconnect reports the port error, fires once, and blocks later sends', () => {
  const { api, port } = fakeChrome();
  const t = createNativeTransport(api, 'h');
  const reasons = [];
  t.onDisconnect((r) => reasons.push(r));
  port.error = { message: 'Specified native messaging host not found.' };
  for (const cb of port.onDisconnect.listeners) cb();
  for (const cb of port.onDisconnect.listeners) cb();
  assert.deepEqual(reasons, ['Specified native messaging host not found.']);
  assert.equal(t.send({ v: 1 }), false);
  assert.equal(port.posted.length, 0);
});

test('falls back to runtime.lastError when the port has no error', () => {
  const { api, port } = fakeChrome();
  api.runtime.lastError = { message: 'lastError text' };
  const t = createNativeTransport(api, 'h');
  const reasons = [];
  t.onDisconnect((r) => reasons.push(r));
  for (const cb of port.onDisconnect.listeners) cb();
  assert.deepEqual(reasons, ['lastError text']);
});

test('close disconnects the port once and tolerates a port that already went away', () => {
  const { api, port } = fakeChrome();
  const t = createNativeTransport(api, 'h');
  t.close();
  t.close();
  assert.equal(port.disconnected, 1);
  assert.equal(t.send({}), false);

  const second = fakeChrome();
  second.port.disconnect = () => { throw new Error('already disconnected'); };
  const t2 = createNativeTransport(second.api, 'h');
  assert.doesNotThrow(() => t2.close());
});
