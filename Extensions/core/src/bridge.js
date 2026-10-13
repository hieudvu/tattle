// Wires one reconnecting session per native host name. Shared by every browser wrapper.
import { createSession } from './session.js';
import { createReconnector } from './reconnect.js';
import { createWebExtTabsApi } from './webext/tabsApi.js';
import { createNativeTransport } from './webext/nativeTransport.js';
import { NATIVE_HOSTS } from './protocol.js';

// api: chrome or browser namespace. Returns the reconnectors so a caller can stop them.
export function startBridge({
  api,
  browser,
  version,
  hosts = NATIVE_HOSTS,
  backoff = {},
  resyncMs = 0,
  resyncIdleMs = resyncMs,
  tabsApi = createWebExtTabsApi(api),
  makeTransport = createNativeTransport,
  setTimeoutFn,
  clearTimeoutFn,
}) {
  return hosts.map((host) => {
    const reconnector = createReconnector({
      ...backoff,
      setTimeoutFn,
      clearTimeoutFn,
      open({ markAlive, lost }) {
        const transport = makeTransport(api, host);
        const session = createSession({ transport, tabsApi, browser, version, resyncMs, resyncIdleMs });
        transport.onMessage(() => markAlive());
        transport.onDisconnect(() => lost());
        session.start();
        return { close: () => session.stop() };
      },
    });
    reconnector.start();
    return reconnector;
  });
}
