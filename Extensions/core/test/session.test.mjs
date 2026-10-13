import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSession } from '../src/session.js';
import { fakeTimers, fakeTransport, fakeTabsApi, flushPromises } from './fakes.mjs';

const SAMPLE = [
  { id: 345, windowId: 12, title: 'Lo-fi', url: 'https://youtube.com/x', audible: true, mutedInfo: { muted: false } },
  { id: 346, windowId: 12, title: 'Silent', url: 'https://example.com', audible: false, mutedInfo: { muted: false } },
];

function setup({ tabs = SAMPLE, browser = 'chrome', version = '0.1.0' } = {}) {
  const timers = fakeTimers();
  const transport = fakeTransport();
  const tabsApi = fakeTabsApi(tabs);
  const session = createSession({
    transport, tabsApi, browser, version,
    debounceMs: 150,
    setTimeoutFn: timers.setTimeoutFn,
    clearTimeoutFn: timers.clearTimeoutFn,
  });
  return { timers, transport, tabsApi, session };
}

const lastResult = (t) => t.sent.filter((m) => m.type === 'result').at(-1);

test('start sends hello (v:1) first, then a snapshot of audible or muted tabs only', async () => {
  const s = setup();
  s.session.start();
  await flushPromises();
  assert.deepEqual(s.transport.sent[0], { v: 1, type: 'hello', browser: 'chrome', extensionVersion: '0.1.0' });
  assert.equal(s.transport.sent[1].type, 'tabs');
  assert.equal(s.transport.sent[1].v, 1);
  assert.equal(s.transport.sent[1].browser, 'chrome');
  assert.deepEqual(s.transport.sent[1].tabs, [
    { id: '12:345', title: 'Lo-fi', url: 'https://youtube.com/x', audible: true, muted: false },
  ]);
});

test('start subscribes to messages, disconnects and tab changes', () => {
  const s = setup();
  s.session.start();
  assert.equal(s.transport.listenerCounts.message, 1);
  assert.equal(s.transport.listenerCounts.disconnect, 1);
  assert.equal(s.tabsApi.listenerCount, 1);
  assert.equal(s.session.isRunning, true);
});

test('start is idempotent', async () => {
  const s = setup();
  s.session.start();
  s.session.start();
  await flushPromises();
  assert.equal(s.transport.sent.filter((m) => m.type === 'hello').length, 1);
});

test('tab changes are debounced to one snapshot ~150ms after the last event', async () => {
  const s = setup();
  s.session.start();
  await flushPromises();
  const base = s.transport.sent.length;
  s.tabsApi.emitChange();
  s.timers.advance(100);
  s.tabsApi.emitChange();
  s.timers.advance(100);
  s.tabsApi.emitChange();
  s.timers.advance(149);
  await flushPromises();
  assert.equal(s.transport.sent.length, base, 'nothing sent before the quiet period ends');
  s.timers.advance(1);
  await flushPromises();
  assert.equal(s.transport.sent.length, base + 1, 'exactly one snapshot');
  assert.equal(s.transport.sent.at(-1).type, 'tabs');
});

test('a snapshot reflects the tab state at send time (full snapshot, not a delta)', async () => {
  const s = setup();
  s.session.start();
  await flushPromises();
  s.tabsApi.state.tabs = [];
  s.tabsApi.emitChange();
  s.timers.advance(150);
  await flushPromises();
  assert.deepEqual(s.transport.sent.at(-1), { v: 1, type: 'tabs', browser: 'chrome', tabs: [] });
});

test('a muted tab stays in the snapshot so it can be unmuted', async () => {
  const s = setup({ tabs: [{ id: 9, windowId: 1, title: 'M', url: 'u', audible: false, mutedInfo: { muted: true } }] });
  s.session.start();
  await flushPromises();
  assert.deepEqual(s.transport.sent.at(-1).tabs, [
    { id: '1:9', title: 'M', url: 'u', audible: false, muted: true },
  ]);
});

test('mute command runs setMuted(true) and answers ok with the same id', async () => {
  const s = setup();
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'b2c1', command: 'mute', tabId: '12:345' });
  await flushPromises();
  assert.deepEqual(s.tabsApi.calls.at(-1), ['setMuted', '12:345', true]);
  assert.deepEqual(lastResult(s.transport), { v: 1, type: 'result', id: 'b2c1', ok: true });
});

test('unmute command runs setMuted(false)', async () => {
  const s = setup();
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'u1', command: 'unmute', tabId: '12:345' });
  await flushPromises();
  assert.deepEqual(s.tabsApi.calls.at(-1), ['setMuted', '12:345', false]);
  assert.equal(lastResult(s.transport).ok, true);
});

test('pause, close and focus dispatch to the matching tabsApi method', async () => {
  const s = setup();
  s.session.start();
  for (const command of ['pause', 'close', 'focus']) {
    s.transport.receive({ v: 1, type: 'command', id: `id-${command}`, command, tabId: '12:345' });
  }
  await flushPromises();
  assert.deepEqual(s.tabsApi.calls.map((c) => c[0]), ['pause', 'close', 'focus']);
  for (const c of s.tabsApi.calls) assert.equal(c[1], '12:345');
  const results = s.transport.sent.filter((m) => m.type === 'result');
  assert.deepEqual(results.map((r) => r.id), ['id-pause', 'id-close', 'id-focus']);
  assert.ok(results.every((r) => r.ok === true));
});

test('a failing command replies ok:false with the error text and the same id', async () => {
  const s = setup();
  s.tabsApi.failNext('close', new Error('tab not found'));
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'c9', command: 'close', tabId: '12:999' });
  await flushPromises();
  assert.deepEqual(lastResult(s.transport), { v: 1, type: 'result', id: 'c9', ok: false, error: 'tab not found' });
});

test('a failing command with an empty message still gets a non-empty error', async () => {
  const s = setup();
  s.tabsApi.failNext('setMuted', new Error(''));
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'e1', command: 'mute', tabId: '12:345' });
  await flushPromises();
  const r = lastResult(s.transport);
  assert.equal(r.ok, false);
  assert.ok(r.error.length > 0);
});

test('a non-Error rejection is still reported as a string error', async () => {
  const s = setup();
  s.tabsApi.failNext('pause', 'weird');
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'p1', command: 'pause', tabId: '12:345' });
  await flushPromises();
  assert.deepEqual(lastResult(s.transport), { v: 1, type: 'result', id: 'p1', ok: false, error: 'weird' });
});

test('a bad protocol version is answered with ok:false when an id is present', () => {
  const s = setup();
  s.session.start();
  s.transport.receive({ v: 9, type: 'command', id: 'z', command: 'mute', tabId: '12:345' });
  assert.equal(lastResult(s.transport).ok, false);
  assert.equal(lastResult(s.transport).id, 'z');
  assert.equal(s.tabsApi.calls.length, 0);
});

test('an unknown command is answered with ok:false and never executed', () => {
  const s = setup();
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'q', command: 'delete', tabId: '12:345' });
  assert.equal(lastResult(s.transport).ok, false);
  assert.match(lastResult(s.transport).error, /unknown command/);
  assert.equal(s.tabsApi.calls.length, 0);
});

test('a junk message with no id gets no reply and runs nothing', () => {
  const s = setup();
  s.session.start();
  const before = s.transport.sent.length;
  s.transport.receive(null);
  s.transport.receive({ v: 1, type: 'command', command: 'mute', tabId: '12:345' });
  assert.equal(s.transport.sent.length, before);
  assert.equal(s.tabsApi.calls.length, 0);
});

test('concurrent commands are each answered with their own id', async () => {
  const s = setup();
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'a', command: 'mute', tabId: '12:345' });
  s.transport.receive({ v: 1, type: 'command', id: 'b', command: 'unmute', tabId: '12:345' });
  await flushPromises();
  const ids = s.transport.sent.filter((m) => m.type === 'result').map((r) => r.id).sort();
  assert.deepEqual(ids, ['a', 'b']);
});

test('a failed tab read sends no snapshot and does not throw', async () => {
  const s = setup();
  s.tabsApi.queryAll = async () => { throw new Error('tabs api gone'); };
  s.session.start();
  await flushPromises();
  assert.deepEqual(s.transport.sent.map((m) => m.type), ['hello']);
});

test('a transport send that throws does not break the session', async () => {
  const s = setup();
  s.transport.send = () => { throw new Error('port closed'); };
  s.session.start();
  s.transport.receive({ v: 1, type: 'command', id: 'x', command: 'mute', tabId: '12:345' });
  await flushPromises();
  assert.equal(s.tabsApi.calls.length, 1);
  assert.equal(s.session.isRunning, true);
});

test('transport disconnect stops the session and closes the transport', () => {
  const s = setup();
  s.session.start();
  s.transport.disconnect('host gone');
  assert.equal(s.session.isRunning, false);
  assert.equal(s.transport.closedCount, 1);
  assert.equal(s.transport.listenerCounts.message, 0);
  assert.equal(s.tabsApi.listenerCount, 0);
});

test('stop unsubscribes everything, cancels a pending snapshot and sends nothing more', async () => {
  const s = setup();
  s.session.start();
  await flushPromises();
  s.tabsApi.emitChange();
  s.session.stop();
  assert.equal(s.timers.pendingCount, 0);
  assert.equal(s.tabsApi.listenerCount, 0);
  assert.equal(s.transport.listenerCounts.message, 0);
  const before = s.transport.sent.length;
  s.timers.advance(1000);
  s.transport.receive({ v: 1, type: 'command', id: 'late', command: 'mute', tabId: '12:345' });
  await flushPromises();
  assert.equal(s.transport.sent.length, before);
  assert.equal(s.tabsApi.calls.length, 0);
  assert.equal(s.transport.closedCount, 1);
});

test('stop is idempotent and a stopped session can be inspected', () => {
  const s = setup();
  s.session.start();
  s.session.stop();
  s.session.stop();
  assert.equal(s.session.isRunning, false);
  assert.equal(s.transport.closedCount, 1);
});

test('the hello uses the browser name passed in (firefox here)', () => {
  const s = setup({ browser: 'firefox', version: '2.0.0' });
  s.session.start();
  assert.deepEqual(s.transport.sent[0], { v: 1, type: 'hello', browser: 'firefox', extensionVersion: '2.0.0' });
});

test('a finished command schedules a fresh snapshot', async () => {
  const s = setup();
  s.session.start();
  await flushPromises();
  const base = s.transport.sent.length;
  s.transport.receive({ v: 1, type: 'command', id: 'c1', command: 'pause', tabId: '12:345' });
  await flushPromises();
  s.timers.advance(150);
  await flushPromises();
  const after = s.transport.sent.slice(base).map((m) => m.type);
  assert.deepEqual(after, ['result', 'tabs']);
});

test('resync re-reads the tabs and sends only when they changed', async () => {
  const timers = fakeTimers();
  const transport = fakeTransport();
  const tabsApi = fakeTabsApi(SAMPLE);
  const session = createSession({ transport, tabsApi, browser: 'safari', version: '0.1.0',
    resyncMs: 2000, setTimeoutFn: timers.setTimeoutFn, clearTimeoutFn: timers.clearTimeoutFn });
  session.start();
  await flushPromises();
  const base = transport.sent.length;
  timers.advance(2000);
  await flushPromises();
  assert.equal(transport.sent.length, base, 'unchanged tabs: nothing sent');
  tabsApi.state.tabs = [...SAMPLE, { id: 347, windowId: 12, title: 'New', url: 'https://y.com', audible: true, mutedInfo: { muted: false } }];
  timers.advance(2000);
  await flushPromises();
  assert.equal(transport.sent.length, base + 1);
  assert.ok(transport.sent.at(-1).tabs.some((t) => t.id === '12:347'));
  session.stop();
  assert.equal(timers.pendingCount, 0);
});

test('resync slows down while no tab is audible or muted', async () => {
  const timers = fakeTimers();
  const transport = fakeTransport();
  const tabsApi = fakeTabsApi([]);
  const session = createSession({ transport, tabsApi, browser: 'safari', version: '0.1.0',
    resyncMs: 2000, resyncIdleMs: 10000, setTimeoutFn: timers.setTimeoutFn, clearTimeoutFn: timers.clearTimeoutFn });
  session.start();
  await flushPromises();
  tabsApi.state.tabs = [{ id: 1, windowId: 1, title: 'A', url: 'https://a.com', audible: true, mutedInfo: { muted: false } }];
  timers.advance(9999);
  await flushPromises();
  assert.equal(transport.sent.filter((m) => m.type === 'tabs').length, 1, 'idle: not re-read before 10 s');
  timers.advance(1);
  await flushPromises();
  assert.equal(transport.sent.filter((m) => m.type === 'tabs').length, 2);
  session.stop();
});
