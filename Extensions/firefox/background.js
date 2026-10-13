// Tattle, Firefox. Thin wrapper: all logic lives in the shared core, copied to ./core by scripts/build-extensions.mjs.
import { startBridge } from './core/src/bridge.js';

startBridge({
  api: globalThis.browser,
  browser: 'firefox',
  version: globalThis.browser.runtime.getManifest().version,
});
