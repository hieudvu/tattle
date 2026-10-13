// Native Messaging transport over runtime.connectNative (chrome.* and browser.* both).
// Exposes the transport contract used by session.js: send, onMessage, onDisconnect, close.

export function createNativeTransport(api, hostName) {
  const port = api.runtime.connectNative(hostName);
  const messageListeners = new Set();
  const disconnectListeners = new Set();
  let disconnected = false;

  port.onMessage.addListener((msg) => {
    for (const cb of [...messageListeners]) cb(msg);
  });

  port.onDisconnect.addListener(() => {
    if (disconnected) return;
    disconnected = true;
    const err = (port.error && port.error.message) || (api.runtime.lastError && api.runtime.lastError.message) || '';
    for (const cb of [...disconnectListeners]) cb(err);
  });

  return {
    send(message) {
      if (disconnected) return false;
      port.postMessage(message);
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
      try { port.disconnect(); } catch { /* already gone */ }
    },
  };
}
