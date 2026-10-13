import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPollingTransport } from '../src/webext/pollingTransport.js';
import { fakeTimers, flushPromises } from './fakes.mjs';

// Fake runtime.sendNativeMessage with a scripted handler.
function fakeSafari(handler = () => ({ ok: true, messages: [] })) {
  const calls = [];
  let inFlight = 0;
  let maxInFlight = 0;
  const api = {
    runtime: {
      async sendNativeMessage(appId, msg) {
        calls.push({ appId, msg });
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        try {
          await flushPromises();
          return await handler(msg, calls.length);
        } finally {
          inFlight -= 1;
        }
      },
    },
  };
  return { api, calls, get maxInFlight() { return maxInFlight; } };
}

function setup(handler, opts = {}) {
  const timers = fakeTimers();
  const safari = fakeSafari(handler);
  const t = createPollingTransport(safari.api, { ...timers, ...opts });
  const received = [];
  const reasons = [];
  t.onMessage((m) => received.push(m));
  t.onDisconnect((r) => reasons.push(r));
  return { t, timers, safari, received, reasons };
}

test('send forwards the message with the application id', async () => {
  const { t, safari } = setup();
  assert.equal(t.send({ v: 1, type: 'hello' }), true);
  await flushPromises();
  assert.deepEqual(safari.calls[0], { appId: 'application.id', msg: { v: 1, type: 'hello' } });
});

test('outbound messages are serialized and keep their order', async () => {
  const { t, safari } = setup();
  t.send({ v: 1, type: 'hello' });
  t.send({ v: 1, type: 'tabs', tabs: [] });
  t.send({ v: 1, type: 'result', id: 'a', ok: true });
  await flushPromises(); await flushPromises(); await flushPromises(); await flushPromises();
  assert.deepEqual(safari.calls.map((c) => c.msg.type), ['hello', 'tabs', 'result']);
  assert.equal(safari.maxInFlight, 1);
});

test('commands piggybacked on a response reach every listener', async () => {
  const cmd = { v: 1, type: 'command', id: 'x', command: 'mute', tabId: '1:2' };
  const { t, received } = setup(() => ({ ok: true, messages: [cmd] }));
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.deepEqual(received, [cmd]);
});

test('with nothing to send it polls on a timer: 5s idle, 1s once a tab is audible', async () => {
  const { t, timers, safari } = setup();
  t.send({ v: 1, type: 'tabs', tabs: [] });
  await flushPromises(); await flushPromises();
  assert.equal(safari.calls.length, 1);
  timers.advance(4999); await flushPromises();
  assert.equal(safari.calls.length, 1);
  timers.advance(1); await flushPromises(); await flushPromises();
  assert.equal(safari.calls.length, 2);
  assert.equal(safari.calls[1].msg.type, 'poll');
  assert.equal(safari.calls[1].msg.browser, 'safari');

  t.send({ v: 1, type: 'tabs', tabs: [{ id: '1:2', audible: true }] });
  await flushPromises(); await flushPromises();
  const before = safari.calls.length;
  timers.advance(1000); await flushPromises(); await flushPromises();
  assert.equal(safari.calls.length, before + 1);
  assert.equal(safari.calls.at(-1).msg.type, 'poll');
});

test('a send while a poll timer is pending goes out immediately', async () => {
  const { t, timers, safari } = setup();
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.equal(timers.pendingCount, 1);
  t.send({ v: 1, type: 'tabs', tabs: [] });
  await flushPromises(); await flushPromises();
  assert.equal(safari.calls.at(-1).msg.type, 'tabs');
});

test('ok:false from the handler is a disconnect carrying its error, once, and stops polling', async () => {
  const { t, timers, safari, reasons } = setup(() => ({ ok: false, error: 'tattle-not-running' }));
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.deepEqual(reasons, ['tattle-not-running']);
  assert.equal(t.send({ v: 1 }), false);
  assert.equal(timers.pendingCount, 0);
  timers.advance(60000); await flushPromises();
  assert.equal(safari.calls.length, 1);
});

test('a rejected sendNativeMessage is a disconnect with the error text', async () => {
  const { t, reasons } = setup(() => { throw new Error('native messaging unavailable'); });
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.deepEqual(reasons, ['native messaging unavailable']);
});

test('a non-object response is a disconnect', async () => {
  const { t, reasons } = setup(() => undefined);
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.equal(reasons.length, 1);
});

test('a throwing listener does not stop delivery to others or the pump', async () => {
  const cmd = { v: 1, type: 'command', id: 'x', command: 'mute', tabId: '1:2' };
  const { t, received, timers } = setup(() => ({ ok: true, messages: [cmd] }));
  t.onMessage(() => { throw new Error('bad listener'); });
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.equal(received.length, 1);
  assert.equal(timers.pendingCount, 1);
});

test('unsubscribe stops delivery', async () => {
  const cmd = { v: 1, type: 'command', id: 'x', command: 'mute', tabId: '1:2' };
  const timers = fakeTimers();
  const safari = fakeSafari(() => ({ ok: true, messages: [cmd] }));
  const t = createPollingTransport(safari.api, timers);
  const got = [];
  const off = t.onMessage((m) => got.push(m));
  off();
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  assert.deepEqual(got, []);
});

test('close sends bye once, stops the timer, blocks later sends and never reports a disconnect', async () => {
  const { t, timers, safari, reasons } = setup();
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  t.close(); t.close();
  await flushPromises();
  assert.equal(safari.calls.filter((c) => c.msg.type === 'bye').length, 1);
  assert.equal(timers.pendingCount, 0);
  assert.equal(t.send({ v: 1 }), false);
  assert.deepEqual(reasons, []);
});

test('close after a failure does not send bye', async () => {
  const { t, safari } = setup(() => ({ ok: false, error: 'gone' }));
  t.send({ v: 1, type: 'hello' });
  await flushPromises(); await flushPromises();
  t.close();
  await flushPromises();
  assert.equal(safari.calls.some((c) => c.msg.type === 'bye'), false);
});

test('works end to end under startBridge: hello is sent, a command runs, ok:false triggers a backoff retry', async () => {
  const { startBridge } = await import('../src/bridge.js');
  const { fakeTabsApi } = await import('./fakes.mjs');
  const timers = fakeTimers();
  let appUp = false;
  const seen = [];
  const safari = fakeSafari((msg) => {
    seen.push(msg.type);
    if (!appUp) return { ok: false, error: 'tattle-not-running' };
    if (msg.type === 'hello') return { ok: true, messages: [{ v: 1, type: 'command', id: 'c1', command: 'mute', tabId: '1:2' }] };
    return { ok: true, messages: [] };
  });
  const tabs = fakeTabsApi([{ id: 2, windowId: 1, audible: true, title: 't', url: 'https://x', mutedInfo: { muted: false } }]);
  startBridge({
    api: safari.api, browser: 'safari', version: '0.1.0', hosts: ['safari'], tabsApi: tabs,
    backoff: { minDelayMs: 2000, maxDelayMs: 60000 },
    makeTransport: (api) => createPollingTransport(api, timers),
    ...timers,
  });
  await flushPromises(); await flushPromises(); await flushPromises();
  assert.deepEqual(seen, ['hello']); // app down: one failed attempt
  appUp = true;
  timers.advance(2000);
  for (let i = 0; i < 8; i += 1) await flushPromises();
  assert.equal(seen.filter((x) => x === 'hello').length, 2);
  assert.deepEqual(tabs.calls, [['setMuted', '1:2', true]]);
  assert.ok(seen.includes('result'));
});
