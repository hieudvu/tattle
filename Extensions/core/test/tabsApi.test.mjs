import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createWebExtTabsApi, pauseMediaInFrame } from '../src/webext/tabsApi.js';

// Fake browser.* / chrome.* namespace. Every method returns a Promise, like Firefox and MV3 Chrome.
function fakeApi(tabs = {}) {
  const calls = [];
  const listeners = {};
  const evt = (name) => {
    listeners[name] = new Set();
    return {
      addListener: (cb) => listeners[name].add(cb),
      removeListener: (cb) => listeners[name].delete(cb),
    };
  };
  const api = {
    calls,
    listeners,
    tabs: {
      query: async (q) => { calls.push(['query', q]); return Object.values(tabs).map((t) => ({ ...t })); },
      get: async (id) => {
        calls.push(['get', id]);
        if (!tabs[id]) throw new Error(`No tab with id: ${id}.`);
        return { ...tabs[id] };
      },
      update: async (id, props) => { calls.push(['update', id, props]); return {}; },
      remove: async (id) => { calls.push(['remove', id]); },
      onUpdated: evt('updated'),
      onCreated: evt('created'),
      onRemoved: evt('removed'),
      onReplaced: evt('replaced'),
    },
    windows: {
      update: async (id, props) => { calls.push(['windows.update', id, props]); return {}; },
    },
    scripting: {
      executeScript: async (opts) => { calls.push(['executeScript', opts]); return [{ result: 1 }]; },
    },
  };
  return api;
}

const TABS = {
  345: { id: 345, windowId: 12, audible: true, mutedInfo: { muted: false } },
  7: { id: 7, windowId: 3, audible: false, mutedInfo: { muted: true } },
};

test('queryAll resolves the raw tab list via tabs.query({})', async () => {
  const api = fakeApi(TABS);
  const out = await createWebExtTabsApi(api).queryAll();
  assert.equal(out.length, 2);
  assert.deepEqual(api.calls[0], ['query', {}]);
});

test('setMuted updates the tab through tabs.update with the muted flag', async () => {
  const api = fakeApi(TABS);
  const tabs = createWebExtTabsApi(api);
  await tabs.setMuted('12:345', true);
  await tabs.setMuted('12:345', false);
  const updates = api.calls.filter((c) => c[0] === 'update');
  assert.deepEqual(updates, [
    ['update', 345, { muted: true }],
    ['update', 345, { muted: false }],
  ]);
});

test('commands on an unknown tab reject with "tab not found" and change nothing', async () => {
  const api = fakeApi(TABS);
  const tabs = createWebExtTabsApi(api);
  await assert.rejects(tabs.setMuted('12:999', true), /tab not found/);
  await assert.rejects(tabs.close('12:999'), /tab not found/);
  await assert.rejects(tabs.focus('12:999'), /tab not found/);
  await assert.rejects(tabs.pause('12:999'), /tab not found/);
  assert.equal(api.calls.filter((c) => ['update', 'remove', 'executeScript'].includes(c[0])).length, 0);
});

test('a malformed id rejects with "tab not found" without touching the browser', async () => {
  const api = fakeApi(TABS);
  await assert.rejects(createWebExtTabsApi(api).close('nonsense'), /tab not found/);
  assert.equal(api.calls.length, 0);
});

test('a stale id whose tab moved to another window is "tab not found"', async () => {
  const api = fakeApi(TABS);
  await assert.rejects(createWebExtTabsApi(api).close('99:345'), /tab not found/);
  assert.equal(api.calls.some((c) => c[0] === 'remove'), false);
});

test('close removes the tab by its numeric id', async () => {
  const api = fakeApi(TABS);
  await createWebExtTabsApi(api).close('12:345');
  assert.deepEqual(api.calls.at(-1), ['remove', 345]);
});

test('focus activates the tab and then focuses its window', async () => {
  const api = fakeApi(TABS);
  await createWebExtTabsApi(api).focus('12:345');
  const tail = api.calls.filter((c) => c[0] === 'update' || c[0] === 'windows.update');
  assert.deepEqual(tail, [
    ['update', 345, { active: true }],
    ['windows.update', 12, { focused: true }],
  ]);
});

test('pause runs pauseMediaInFrame in every frame of the tab', async () => {
  const api = fakeApi(TABS);
  await createWebExtTabsApi(api).pause('12:345');
  const [, opts] = api.calls.find((c) => c[0] === 'executeScript');
  assert.deepEqual(opts.target, { tabId: 345, allFrames: true });
  assert.equal(typeof opts.func, 'function');
  assert.equal(opts.func, pauseMediaInFrame);
});

test('an executeScript failure (restricted page) propagates as a rejection', async () => {
  const api = fakeApi(TABS);
  api.scripting.executeScript = async () => { throw new Error('Cannot access contents of url'); };
  await assert.rejects(createWebExtTabsApi(api).pause('12:345'), /Cannot access/);
});

test('onChanged fires for audible/muted/title/url updates, created, removed and replaced', () => {
  const api = fakeApi(TABS);
  let n = 0;
  createWebExtTabsApi(api).onChanged(() => { n += 1; });
  for (const cb of api.listeners.updated) {
    cb(1, { audible: true }, {});
    cb(1, { mutedInfo: { muted: true } }, {});
    cb(1, { title: 'x' }, {});
    cb(1, { url: 'https://y' }, {});
  }
  for (const cb of api.listeners.created) cb({});
  for (const cb of api.listeners.removed) cb(1, {});
  for (const cb of api.listeners.replaced) cb(2, 1);
  assert.equal(n, 7);
});

test('onChanged ignores noisy status-only updates', () => {
  const api = fakeApi(TABS);
  let n = 0;
  createWebExtTabsApi(api).onChanged(() => { n += 1; });
  for (const cb of api.listeners.updated) {
    cb(1, { status: 'loading' }, {});
    cb(1, { status: 'complete' }, {});
    cb(1, undefined, {});
  }
  assert.equal(n, 0);
});

test('the unsubscribe function removes every listener it added', () => {
  const api = fakeApi(TABS);
  const off = createWebExtTabsApi(api).onChanged(() => {});
  off();
  for (const name of ['updated', 'created', 'removed', 'replaced']) {
    assert.equal(api.listeners[name].size, 0, name);
  }
});

test('pauseMediaInFrame pauses playing media and returns the count (self-contained)', () => {
  const playing = { paused: false, pause() { this.paused = true; } };
  const alreadyPaused = { paused: true, pause() { throw new Error('should not be called'); } };
  globalThis.document = { querySelectorAll: (sel) => (sel === 'video, audio' ? [playing, alreadyPaused] : []) };
  try {
    assert.equal(pauseMediaInFrame(), 1);
    assert.equal(playing.paused, true);
  } finally {
    delete globalThis.document;
  }
});

test('pauseMediaInFrame survives an element that throws on pause()', () => {
  const bad = { paused: false, pause() { throw new Error('nope'); } };
  globalThis.document = { querySelectorAll: () => [bad] };
  try {
    assert.equal(pauseMediaInFrame(), 0);
  } finally {
    delete globalThis.document;
  }
});

test('a pause that paused nothing in any frame is reported as a failure', async () => {
  const api = fakeApi(TABS);
  api.scripting.executeScript = async () => [{ result: 0 }, { result: 0 }];
  await assert.rejects(createWebExtTabsApi(api).pause('12:345'), /nothing was playing/);
  api.scripting.executeScript = async () => [{ result: 0 }, { result: 2 }];
  await createWebExtTabsApi(api).pause('12:345');
});
