// Tattle, Chromium family (Chrome, Edge, Brave, Opera, Vivaldi, ...).
// Thin wrapper: all logic lives in the shared core, copied to ./core by scripts/build-extensions.mjs.
import { startBridge } from './core/src/bridge.js';
import { detectChromiumBrand } from './core/src/webext/brand.js';

// An MV3 service worker is killed after ~30s idle, taking the reconnect timers with it (so a
// bridge that was down at first would never be retried). An alarm wakes the worker, which
// re-runs this script and therefore reconnects. Listener must be registered synchronously.
globalThis.chrome.alarms.create('tattle-wake', { periodInMinutes: 0.5 });
globalThis.chrome.alarms.onAlarm.addListener(() => {});

// No top-level await: it is forbidden in a service worker and makes registration fail
// (Chrome: "Service worker registration failed. Status code: 15"), so the worker never ran.
(async () => {
  const browser = await detectChromiumBrand(globalThis.navigator);
  startBridge({
    api: globalThis.chrome,
    browser,
    version: globalThis.chrome.runtime.getManifest().version,
    // A native host that is not installed simply fails, so probe it slowly (5s..60s).
    backoff: { minDelayMs: 5000, maxDelayMs: 60000 },
  });
})();
