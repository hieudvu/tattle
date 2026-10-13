// Backoff reconnect wrapper. Pure timing logic; timers are injectable for tests.
//
// open({ markAlive, lost }) is called for every attempt. It returns { close() } for a
// live connection, or throws. The connection must call lost() when it goes away.
//  - a failed open, or a lost connection, schedules the next attempt after an exponential delay
//    (minDelayMs, 2x, 4x, ... capped at maxDelayMs);
//  - the delay resets to minDelayMs once the connection proves healthy: markAlive() is called
//    (e.g. the host sent something) or the connection stayed up for stableMs.

export function createReconnector({
  open,
  minDelayMs = 1000,
  maxDelayMs = 30000,
  stableMs = 10000,
  setTimeoutFn = setTimeout,
  clearTimeoutFn = clearTimeout,
}) {
  let stopped = true;
  let failures = 0;
  let current = null; // { close }
  let attemptToken = 0;
  let retryTimer = null;
  let stableTimer = null;

  function delayForNextRetry() {
    const d = minDelayMs * 2 ** failures;
    return Math.min(maxDelayMs, d);
  }

  function clearTimers() {
    if (retryTimer !== null) clearTimeoutFn(retryTimer);
    if (stableTimer !== null) clearTimeoutFn(stableTimer);
    retryTimer = null;
    stableTimer = null;
  }

  function markAlive(token) {
    if (token !== attemptToken || stopped) return;
    failures = 0;
    if (stableTimer !== null) {
      clearTimeoutFn(stableTimer);
      stableTimer = null;
    }
  }

  function scheduleRetry() {
    if (stopped || retryTimer !== null) return;
    const delay = delayForNextRetry();
    failures += 1;
    retryTimer = setTimeoutFn(() => {
      retryTimer = null;
      attempt();
    }, delay);
  }

  function lost(token) {
    if (token !== attemptToken || stopped) return;
    attemptToken += 1; // invalidate this attempt's callbacks
    if (stableTimer !== null) {
      clearTimeoutFn(stableTimer);
      stableTimer = null;
    }
    const conn = current;
    current = null;
    if (conn) {
      try { conn.close(); } catch { /* already gone */ }
    }
    scheduleRetry();
  }

  function attempt() {
    if (stopped) return;
    attemptToken += 1;
    const token = attemptToken;
    let conn;
    try {
      conn = open({
        markAlive: () => markAlive(token),
        lost: () => lost(token),
      });
    } catch {
      conn = null;
    }
    if (!conn) {
      // Failure: undo the token bump so a late callback from this attempt is ignored.
      attemptToken += 1;
      scheduleRetry();
      return;
    }
    current = conn;
    stableTimer = setTimeoutFn(() => {
      stableTimer = null;
      markAlive(token);
    }, stableMs);
  }

  return {
    start() {
      if (!stopped) return;
      stopped = false;
      failures = 0;
      attempt();
    },
    stop() {
      stopped = true;
      clearTimers();
      attemptToken += 1;
      const conn = current;
      current = null;
      if (conn) {
        try { conn.close(); } catch { /* ignore */ }
      }
    },
    get isRunning() {
      return !stopped;
    },
  };
}
