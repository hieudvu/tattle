// One session = one connection to Tattle. Transport-agnostic and browser-agnostic:
// everything browser-specific arrives through `tabsApi`, everything wire-specific through `transport`.
//
// transport: { send(msg), onMessage(cb), onDisconnect(cb), close() }
// tabsApi:   { queryAll(), onChanged(cb) -> unsubscribe, setMuted(id, bool), pause(id),
//              close(id), focus(id) }   (ids are protocol ids "<windowId>:<tabId>")

import { buildHello, buildTabs, buildResult, validateCommand } from './protocol.js';
import { toProtocolTabs } from './tabSnapshot.js';

export function createSession({
  transport,
  tabsApi,
  browser,
  version,
  debounceMs = 150,
  // >0: also re-read the tabs on this period and send a snapshot only if it changed. For browsers
  // (Safari) whose tab events can be late or missing while the browser is in the background.
  resyncMs = 0,
  // Slower resync while no tab is audible or muted (nothing for Tattle to show): saves wake-ups.
  resyncIdleMs = resyncMs,
  setTimeoutFn = setTimeout,
  clearTimeoutFn = clearTimeout,
}) {
  let running = false;
  let timer = null;
  let resyncTimer = null;
  let lastSent = null;
  let anyTabs = false;
  let unsubscribeTabs = null;
  let unsubscribeMessages = null;
  let unsubscribeDisconnect = null;

  function send(msg) {
    if (!running) return;
    try {
      transport.send(msg);
    } catch {
      // The transport reports its own disconnects; a failed send is not fatal here.
    }
  }

  async function snapshot({ onlyIfChanged = false } = {}) {
    if (!running) return;
    let raw;
    try {
      raw = await tabsApi.queryAll();
    } catch {
      return; // cannot read tabs right now; the next tab event will retry
    }
    if (!running) return;
    const tabs = toProtocolTabs(raw);
    const key = JSON.stringify(tabs);
    if (onlyIfChanged && key === lastSent) return;
    lastSent = key;
    anyTabs = tabs.length > 0;
    send(buildTabs({ browser, tabs }));
  }

  function scheduleResync() {
    if (!running || !(resyncMs > 0)) return;
    resyncTimer = setTimeoutFn(async () => {
      resyncTimer = null;
      await snapshot({ onlyIfChanged: true });
      scheduleResync();
    }, anyTabs ? resyncMs : resyncIdleMs);
  }

  function scheduleSnapshot() {
    if (!running) return;
    if (timer !== null) clearTimeoutFn(timer);
    timer = setTimeoutFn(() => {
      timer = null;
      snapshot();
    }, debounceMs);
  }

  const executors = {
    mute: (id) => tabsApi.setMuted(id, true),
    unmute: (id) => tabsApi.setMuted(id, false),
    pause: (id) => tabsApi.pause(id),
    close: (id) => tabsApi.close(id),
    focus: (id) => tabsApi.focus(id),
  };

  async function runCommand({ id, command, tabId }) {
    try {
      await executors[command](tabId);
      send(buildResult({ id, ok: true }));
      scheduleSnapshot();  // the command changed the tabs: show it now, not at the next resync
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      send(buildResult({ id, ok: false, error: message || 'command failed' }));
    }
  }

  function handleMessage(raw) {
    if (!running) return;
    const checked = validateCommand(raw);
    if (!checked.ok) {
      if (checked.id !== undefined) {
        send(buildResult({ id: checked.id, ok: false, error: checked.error }));
      }
      return;
    }
    runCommand(checked.command);
  }

  const session = {
    start() {
      if (running) return;
      running = true;
      send(buildHello({ browser, extensionVersion: version }));
      unsubscribeMessages = transport.onMessage(handleMessage);
      unsubscribeDisconnect = transport.onDisconnect(() => session.stop());
      unsubscribeTabs = tabsApi.onChanged(scheduleSnapshot);
      snapshot();
      scheduleResync();
    },
    stop() {
      if (!running) return;
      running = false;
      if (timer !== null) clearTimeoutFn(timer);
      timer = null;
      if (resyncTimer !== null) clearTimeoutFn(resyncTimer);
      resyncTimer = null;
      for (const fn of [unsubscribeTabs, unsubscribeMessages, unsubscribeDisconnect]) {
        if (typeof fn === 'function') fn();
      }
      unsubscribeTabs = unsubscribeMessages = unsubscribeDisconnect = null;
      try { transport.close(); } catch { /* already closed */ }
    },
    get isRunning() {
      return running;
    },
  };
  return session;
}
