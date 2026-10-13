import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createReconnector } from '../src/reconnect.js';
import { fakeTimers } from './fakes.mjs';

function setup(opts = {}) {
  const timers = fakeTimers();
  const attempts = [];
  const conns = [];
  let failNext = 0;
  const rc = createReconnector({
    minDelayMs: 1000,
    maxDelayMs: 30000,
    stableMs: 10000,
    setTimeoutFn: timers.setTimeoutFn,
    clearTimeoutFn: timers.clearTimeoutFn,
    ...opts,
    open(hooks) {
      attempts.push(hooks);
      if (failNext > 0) { failNext -= 1; throw new Error('no host'); }
      const conn = { closed: 0, close() { this.closed += 1; } };
      conns.push(conn);
      return conn;
    },
  });
  return {
    rc, timers, attempts, conns,
    failNext(n) { failNext = n; },
  };
}

test('first attempt happens immediately on start', () => {
  const s = setup();
  s.rc.start();
  assert.equal(s.attempts.length, 1);
  assert.equal(s.rc.isRunning, true);
});

test('failed opens back off 1s, 2s, 4s, 8s, 16s, then cap at 30s', () => {
  const s = setup();
  s.failNext(100);
  s.rc.start();
  const expected = [1000, 2000, 4000, 8000, 16000, 30000, 30000];
  for (const [i, ms] of expected.entries()) {
    assert.equal(s.attempts.length, i + 1, 'attempt count before wait');
    s.timers.advance(ms - 1);
    const before = s.attempts.length;
    s.timers.advance(1);
    assert.equal(s.attempts.length, before + 1, `retry after ${ms}ms`);
  }
});

test('a lost connection schedules a retry and closes the old connection', () => {
  const s = setup();
  s.rc.start();
  s.attempts[0].lost();
  assert.equal(s.conns[0].closed, 1);
  assert.equal(s.attempts.length, 1);
  s.timers.advance(1000);
  assert.equal(s.attempts.length, 2);
});

test('markAlive resets the backoff after failures', () => {
  const s = setup();
  s.failNext(2);
  s.rc.start();        // fail -> wait 1s
  s.timers.advance(1000); // fail -> wait 2s
  s.timers.advance(2000); // success (attempt 3)
  assert.equal(s.conns.length, 1);
  s.attempts[2].markAlive();
  s.attempts[2].lost();
  s.timers.advance(999);
  assert.equal(s.attempts.length, 3);
  s.timers.advance(1);
  assert.equal(s.attempts.length, 4, 'delay back to minDelay');
});

test('a connection that stays up for stableMs also resets the backoff', () => {
  const s = setup();
  s.failNext(3);
  s.rc.start();
  s.timers.advance(1000);
  s.timers.advance(2000);
  s.timers.advance(4000); // attempt 4 succeeds
  assert.equal(s.conns.length, 1);
  s.timers.advance(10000); // stable
  s.attempts[3].lost();
  s.timers.advance(1000);
  assert.equal(s.attempts.length, 5, 'retry after minDelay');
});

test('a connection lost before stableMs does not reset the backoff', () => {
  const s = setup();
  s.failNext(1);
  s.rc.start();          // fail, wait 1s
  s.timers.advance(1000); // attempt 2 succeeds
  s.timers.advance(5000);
  s.attempts[1].lost();   // short-lived: next wait is 2s, not 1s
  s.timers.advance(1000);
  assert.equal(s.attempts.length, 2);
  s.timers.advance(1000);
  assert.equal(s.attempts.length, 3);
});

test('stale callbacks from a closed attempt are ignored', () => {
  const s = setup();
  s.rc.start();
  const first = s.attempts[0];
  first.lost();
  s.timers.advance(1000); // attempt 2
  first.lost();           // stale: must not schedule another retry or close attempt 2
  first.markAlive();
  assert.equal(s.conns[1].closed, 0);
  s.timers.advance(10000);
  assert.equal(s.attempts.length, 2, 'no extra attempts from stale lost()');
});

test('lost() is idempotent for the same attempt', () => {
  const s = setup();
  s.rc.start();
  s.attempts[0].lost();
  s.attempts[0].lost();
  assert.equal(s.conns[0].closed, 1);
  s.timers.advance(1000);
  assert.equal(s.attempts.length, 2);
  s.timers.advance(60000);
  assert.equal(s.attempts.length, 2, 'only one retry was scheduled');
});

test('stop cancels pending retries and closes the live connection', () => {
  const s = setup();
  s.rc.start();
  s.attempts[0].lost();
  s.rc.stop();
  assert.equal(s.rc.isRunning, false);
  s.timers.advance(60000);
  assert.equal(s.attempts.length, 1);
  assert.equal(s.timers.pendingCount, 0);
});

test('stop closes an open connection', () => {
  const s = setup();
  s.rc.start();
  s.rc.stop();
  assert.equal(s.conns[0].closed, 1);
});

test('stop is safe to call twice and start after stop reconnects', () => {
  const s = setup();
  s.rc.start();
  s.rc.stop();
  s.rc.stop();
  s.rc.start();
  assert.equal(s.attempts.length, 2);
  assert.equal(s.rc.isRunning, true);
});

test('a hook from a stopped run is ignored', () => {
  const s = setup();
  s.rc.start();
  const hooks = s.attempts[0];
  s.rc.stop();
  s.rc.start();
  hooks.lost();
  assert.equal(s.attempts.length, 2);
});

test('custom slow backoff (chromium host probing) is honoured', () => {
  const s = setup({ minDelayMs: 5000, maxDelayMs: 60000 });
  s.failNext(10);
  s.rc.start();
  s.timers.advance(4999);
  assert.equal(s.attempts.length, 1);
  s.timers.advance(1);
  assert.equal(s.attempts.length, 2);
  s.timers.advance(10000);
  assert.equal(s.attempts.length, 3);
  s.timers.advance(20000);
  assert.equal(s.attempts.length, 4);
  s.timers.advance(40000);
  assert.equal(s.attempts.length, 5);
  s.timers.advance(60000);
  assert.equal(s.attempts.length, 6, 'capped at 60s');
});
