// Tattle, Safari. Thin wrapper: all logic lives in the shared core, copied to ./core by scripts/build-safari-extension.sh.
// Safari has no native-messaging port, so the session runs over the polling transport. One host
// ("safari"): the appex that contains this script only ever talks to its own app flavour (dev or production).
import { startBridge } from './core/src/bridge.js';
import { createPollingTransport } from './core/src/webext/pollingTransport.js';

const api = globalThis.browser;

startBridge({
  api,
  browser: 'safari',
  version: api.runtime.getManifest().version,
  hosts: ['safari'],
  makeTransport: (a) => createPollingTransport(a),
  // The handler answers at once when Tattle is not running, so retrying is cheap: 2s..60s.
  backoff: { minDelayMs: 2000, maxDelayMs: 60000 },
  // Safari delivers tab events late (or not at all) for background tabs, so also re-read them.
  resyncMs: 2000,      // while a tab is audible or muted
  resyncIdleMs: 10000, // otherwise
});

// Safety net: manifest v3 requires a non-persistent page ("persistent": false), so Safari may unload it
// at any time. A registered alarm listener makes Safari reload it, which re-runs
// startBridge() and therefore sends a fresh `hello` + full tab snapshot.
api.alarms.create('tattle-wake', { periodInMinutes: 1 });
api.alarms.onAlarm.addListener(() => {});
