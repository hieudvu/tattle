// Wire protocol v1 between the browser extension and Tattle (see docs/extension-protocol.md).
// Pure functions only: no browser APIs here.

export const PROTOCOL_VERSION = 1;
export const COMMANDS = Object.freeze(['mute', 'unmute', 'pause', 'close', 'focus']);
export const BROWSERS = Object.freeze([
  'chrome', 'edge', 'brave', 'arc', 'vivaldi', 'opera', 'chromium', 'firefox', 'safari',
]);
// Native-messaging host names. Dev and pro never share one.
export const NATIVE_HOSTS = Object.freeze(['dev.hieuvd.tattle', 'dev.hieuvd.tattle.dev']);

export function buildHello({ browser, extensionVersion }) {
  return { v: PROTOCOL_VERSION, type: 'hello', browser, extensionVersion };
}

export function buildTabs({ browser, tabs }) {
  return { v: PROTOCOL_VERSION, type: 'tabs', browser, tabs };
}

export function buildResult({ id, ok, error }) {
  if (ok) return { v: PROTOCOL_VERSION, type: 'result', id, ok: true };
  return { v: PROTOCOL_VERSION, type: 'result', id, ok: false, error: String(error ?? 'failed') };
}

// Validates a message received from Tattle. Never throws.
// Returns { ok: true, command: { id, command, tabId } } or
// { ok: false, id, error } where `id` is present whenever the bad message carried a usable id,
// so the caller can still answer with a `result`.
export function validateCommand(raw) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return { ok: false, id: undefined, error: 'message is not an object' };
  }
  const id = typeof raw.id === 'string' && raw.id.length > 0 ? raw.id : undefined;
  if (raw.v !== PROTOCOL_VERSION) {
    return { ok: false, id, error: `unsupported protocol version ${JSON.stringify(raw.v)}` };
  }
  if (raw.type !== 'command') {
    return { ok: false, id, error: `unexpected message type ${JSON.stringify(raw.type)}` };
  }
  if (id === undefined) {
    return { ok: false, id: undefined, error: 'command has no id' };
  }
  if (!COMMANDS.includes(raw.command)) {
    return { ok: false, id, error: `unknown command ${JSON.stringify(raw.command)}` };
  }
  if (typeof raw.tabId !== 'string' || raw.tabId.length === 0) {
    return { ok: false, id, error: 'command has no tabId' };
  }
  return { ok: true, command: { id, command: raw.command, tabId: raw.tabId } };
}
