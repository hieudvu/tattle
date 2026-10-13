// Transport for browsers without a persistent native port (Safari). Same contract as
// nativeTransport.js: send, onMessage, onDisconnect, close.
//
// Safari only offers runtime.sendNativeMessage(appId, message) -> Promise<response>: one request, one
// response, and the containing app's extension handler cannot push. So:
//  - every outbound message is one sendNativeMessage call, serialized (hello must reach the app before tabs);
//  - the handler piggybacks any queued Tattle commands on EVERY response: `{ ok: true, messages: [...] }`;
//  - when nothing is waiting to be sent, we send `{ v:1, type:'poll' }` on a timer to fetch commands.
//
// Poll interval: a command is a user click ("mute this tab"), so latency under ~1 s feels instant, and
// a poll is one cheap local IPC round trip. We poll every `activeIntervalMs` (1 s) only while the last
// `tabs` snapshot we sent was non-empty (someone is audible or muted, i.e. there is something Tattle
// could act on). With no such tab we slow to `idleIntervalMs` (5 s); a tab event sends a snapshot
// right away, which also drains pending commands, so idle polling is just a safety net.
//
// Failure: a rejected call, or `{ ok:false, error }`, is a disconnect (the app is not running, the
// handler is gone, ...). The reconnector above us backs off and opens a fresh transport, whose
// first message is a new `hello` (that is also how a background page that Safari unloaded recovers:
// reloading it runs startBridge again).

export const POLL_MESSAGE = Object.freeze({ v: 1, type: 'poll' });

export function createPollingTransport(api, {
  appId = 'application.id', // Safari ignores the id and always targets the containing app's handler
  browser = 'safari',
  activeIntervalMs = 1000,
  idleIntervalMs = 5000,
  setTimeoutFn = setTimeout,
  clearTimeoutFn = clearTimeout,
} = {}) {
  const messageListeners = new Set();
  const disconnectListeners = new Set();
  const outbox = [];
  let disconnected = false;
  let inFlight = false;
  let timer = null;
  let active = false;

  function stopTimer() {
    if (timer !== null) clearTimeoutFn(timer);
    timer = null;
  }

  function fail(reason) {
    if (disconnected) return;
    disconnected = true;
    stopTimer();
    outbox.length = 0;
    for (const cb of [...disconnectListeners]) cb(reason);
  }

  function deliver(response) {
    if (response === null || typeof response !== 'object') {
      fail('invalid response from the Tattle extension handler');
      return false;
    }
    if (response.ok === false) {
      fail(typeof response.error === 'string' && response.error ? response.error : 'Tattle is not running');
      return false;
    }
    const messages = Array.isArray(response.messages) ? response.messages : [];
    for (const msg of messages) {
      for (const cb of [...messageListeners]) {
        try { cb(msg); } catch { /* a bad listener must not break the pump */ }
      }
    }
    return true;
  }

  async function pump() {
    if (disconnected || inFlight) return;
    stopTimer();
    const isPoll = outbox.length === 0;
    const message = isPoll ? { ...POLL_MESSAGE, browser } : outbox.shift();
    inFlight = true;
    let ok = false;
    try {
      const response = await api.runtime.sendNativeMessage(appId, message);
      inFlight = false;
      if (disconnected) return;
      ok = deliver(response);
    } catch (err) {
      inFlight = false;
      fail((err && err.message) || String(err) || 'sendNativeMessage failed');
      return;
    }
    if (!ok || disconnected) return;
    if (outbox.length > 0) {
      pump();
    } else {
      timer = setTimeoutFn(() => { timer = null; pump(); }, active ? activeIntervalMs : idleIntervalMs);
    }
  }

  const transport = {
    send(message) {
      if (disconnected) return false;
      if (message && message.type === 'tabs' && Array.isArray(message.tabs)) active = message.tabs.length > 0;
      outbox.push(message);
      pump();
      return true;
    },
    onMessage(cb) {
      messageListeners.add(cb);
      return () => messageListeners.delete(cb);
    },
    onDisconnect(cb) {
      disconnectListeners.add(cb);
      return () => disconnectListeners.delete(cb);
    },
    close() {
      if (disconnected) return;
      disconnected = true;
      stopTimer();
      outbox.length = 0;
      // Best effort: tell the handler to drop its link so the app forgets this browser's tabs now.
      Promise.resolve()
        .then(() => api.runtime.sendNativeMessage(appId, { v: 1, type: 'bye', browser }))
        .catch(() => {});
    },
  };

  // The first poll/send is driven by the session's hello; if nothing is ever sent, still poll.
  timer = setTimeoutFn(() => { timer = null; pump(); }, idleIntervalMs);
  return transport;
}
