// Shared test doubles. No real browser is involved anywhere.

export function fakeTimers() {
  let now = 0;
  let nextId = 1;
  const pending = new Map(); // id -> { at, fn }
  return {
    setTimeoutFn(fn, ms) {
      const id = nextId++;
      pending.set(id, { at: now + ms, fn });
      return id;
    },
    clearTimeoutFn(id) {
      pending.delete(id);
    },
    // Runs every timer due within `ms`, in time order, including timers they schedule.
    advance(ms) {
      const end = now + ms;
      for (;;) {
        let nextId2 = null;
        let nextAt = Infinity;
        for (const [id, t] of pending) {
          if (t.at <= end && t.at < nextAt) { nextAt = t.at; nextId2 = id; }
        }
        if (nextId2 === null) break;
        const t = pending.get(nextId2);
        pending.delete(nextId2);
        now = t.at;
        t.fn();
      }
      now = end;
    },
    get pendingCount() {
      return pending.size;
    },
    get now() {
      return now;
    },
  };
}

export function fakeTransport() {
  const sent = [];
  const messageCbs = new Set();
  const disconnectCbs = new Set();
  let closed = 0;
  return {
    sent,
    get closedCount() { return closed; },
    send(msg) { sent.push(msg); return true; },
    onMessage(cb) { messageCbs.add(cb); return () => messageCbs.delete(cb); },
    onDisconnect(cb) { disconnectCbs.add(cb); return () => disconnectCbs.delete(cb); },
    close() { closed += 1; },
    // test helpers
    receive(msg) { for (const cb of [...messageCbs]) cb(msg); },
    disconnect(err = '') { for (const cb of [...disconnectCbs]) cb(err); },
    get listenerCounts() { return { message: messageCbs.size, disconnect: disconnectCbs.size }; },
  };
}

// Fake tabsApi with an in-memory tab list. Methods return promises like the real adapter.
export function fakeTabsApi(initialTabs = []) {
  const state = { tabs: initialTabs.map((t) => ({ ...t })) };
  const changeCbs = new Set();
  const calls = [];
  const failures = new Map(); // command -> Error
  const api = {
    calls,
    state,
    failNext(command, error = new Error('boom')) { failures.set(command, error); },
    queryAll: async () => state.tabs.map((t) => ({ ...t })),
    onChanged(cb) { changeCbs.add(cb); return () => changeCbs.delete(cb); },
    emitChange() { for (const cb of [...changeCbs]) cb(); },
    get listenerCount() { return changeCbs.size; },
  };
  for (const name of ['setMuted', 'pause', 'close', 'focus']) {
    api[name] = async (...args) => {
      calls.push([name, ...args]);
      if (failures.has(name)) {
        const e = failures.get(name);
        failures.delete(name);
        throw e;
      }
      return undefined;
    };
  }
  return api;
}

export function flushPromises() {
  return new Promise((resolve) => setImmediate(resolve));
}
