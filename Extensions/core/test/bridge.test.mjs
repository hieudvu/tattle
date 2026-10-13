import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startBridge } from '../src/bridge.js';
import { fakeTimers, fakeTransport, fakeTabsApi, flushPromises } from './fakes.mjs';

function setup(opts = {}) {
  const timers = fakeTimers();
  const transports = [];
  const tabsApi = fakeTabsApi([{ id: 1, windowId: 2, audible: true }]);
  const makeTransport = (api, host) => {
    const t = fakeTransport();
    t.host = host;
    t.api = api;
    transports.push(t);
    return t;
  };
  const reconnectors = startBridge({
    api: { name: 'fake-api' },
    browser: 'brave',
    version: '3.1.4',
    tabsApi,
    makeTransport,
    setTimeoutFn: timers.setTimeoutFn,
    clearTimeoutFn: timers.clearTimeoutFn,
    ...opts,
  });
  return { timers, transports, reconnectors, tabsApi };
}

test('starts one reconnecting session per native host (dev and pro)', () => {
  const s = setup();
  assert.equal(s.reconnectors.length, 2);
  assert.deepEqual(s.transports.map((t) => t.host), ['dev.hieuvd.tattle', 'dev.hieuvd.tattle.dev']);
  assert.equal(s.transports[0].api.name, 'fake-api');
});

test('each session says hello with the browser and version it was given', async () => {
  const s = setup();
  await flushPromises();
  for (const t of s.transports) {
    assert.deepEqual(t.sent[0], { v: 1, type: 'hello', browser: 'brave', extensionVersion: '3.1.4' });
    assert.equal(t.sent[1].type, 'tabs');
  }
});

test('a host that is not installed fails and is retried on the backoff schedule', () => {
  const s = setup({ backoff: { minDelayMs: 5000, maxDelayMs: 60000 } });
  // Simulate the host missing: the port disconnects straight away.
  s.transports[0].disconnect('Specified native messaging host not found.');
  assert.equal(s.transports.length, 2, 'no retry before the delay');
  s.timers.advance(4999);
  assert.equal(s.transports.length, 2);
  s.timers.advance(1);
  assert.equal(s.transports.length, 3, 'the dev host is retried after 5s');
  assert.equal(s.transports[2].host, 'dev.hieuvd.tattle');
});

test('a message from the host resets that host backoff', () => {
  const s = setup({ backoff: { minDelayMs: 1000, maxDelayMs: 30000 } });
  s.transports[1].disconnect('gone');
  s.timers.advance(1000);
  const retry = s.transports[2];
  retry.receive({ v: 1, type: 'command', id: 'x', command: 'focus', tabId: '2:1' });
  retry.disconnect('gone');
  s.timers.advance(1000);
  assert.equal(s.transports.length, 4, 'backoff was reset, so the retry is again 1s');
});

test('stop closes every session and stops retrying', () => {
  const s = setup();
  for (const r of s.reconnectors) r.stop();
  assert.equal(s.transports.every((t) => t.closedCount === 1), true);
  s.timers.advance(120000);
  assert.equal(s.transports.length, 2);
});
