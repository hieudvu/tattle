import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toProtocolTabs, tabProtocolId, parseTabProtocolId } from '../src/tabSnapshot.js';

test('tabProtocolId joins window and tab ids', () => {
  assert.equal(tabProtocolId(12, 345), '12:345');
});

test('parseTabProtocolId round-trips and rejects malformed ids', () => {
  assert.deepEqual(parseTabProtocolId('12:345'), { windowId: 12, tabId: 345 });
  for (const bad of ['', '12', '12:', ':3', 'a:b', '12:345:6', '-1:2', null, 5]) {
    assert.equal(parseTabProtocolId(bad), null, String(bad));
  }
});

test('keeps audible tabs and muted tabs, drops silent unmuted ones', () => {
  const raw = [
    { id: 1, windowId: 10, title: 'Playing', url: 'https://a', audible: true, mutedInfo: { muted: false } },
    { id: 2, windowId: 10, title: 'Muted', url: 'https://b', audible: false, mutedInfo: { muted: true } },
    { id: 3, windowId: 10, title: 'Quiet', url: 'https://c', audible: false, mutedInfo: { muted: false } },
  ];
  assert.deepEqual(toProtocolTabs(raw), [
    { id: '10:1', title: 'Playing', url: 'https://a', audible: true, muted: false },
    { id: '10:2', title: 'Muted', url: 'https://b', audible: false, muted: true },
  ]);
});

test('audible and muted at once is reported with both flags set', () => {
  const [t] = toProtocolTabs([{ id: 4, windowId: 1, audible: true, mutedInfo: { muted: true } }]);
  assert.equal(t.audible, true);
  assert.equal(t.muted, true);
});

test('falls back to a boolean muted field when mutedInfo is absent', () => {
  const out = toProtocolTabs([{ id: 5, windowId: 1, audible: false, muted: true }]);
  assert.equal(out.length, 1);
  assert.equal(out[0].muted, true);
});

test('missing title or url become empty strings', () => {
  const [t] = toProtocolTabs([{ id: 6, windowId: 1, audible: true }]);
  assert.equal(t.title, '');
  assert.equal(t.url, '');
});

test('skips tabs without numeric ids and junk entries', () => {
  const out = toProtocolTabs([
    null,
    'x',
    { windowId: 1, audible: true },
    { id: 2, audible: true },
    { id: '3', windowId: 1, audible: true },
    { id: 4, windowId: 1, audible: true },
  ]);
  assert.deepEqual(out.map((t) => t.id), ['1:4']);
});

test('non-array input yields an empty snapshot', () => {
  assert.deepEqual(toProtocolTabs(undefined), []);
  assert.deepEqual(toProtocolTabs(null), []);
});

test('preserves input order', () => {
  const out = toProtocolTabs([
    { id: 9, windowId: 2, audible: true },
    { id: 1, windowId: 1, audible: true },
  ]);
  assert.deepEqual(out.map((t) => t.id), ['2:9', '1:1']);
});
