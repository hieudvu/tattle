# Tattle browser extensions

Tells Tattle which browser tab is playing sound, and lets it mute, unmute, pause, close or
focus that tab. Protocol: `docs/extension-protocol.md`.

```
Extensions/
  core/            shared logic (protocol, session, reconnect, tab adapters) + node --test suite
  chromium/        MV3 wrapper: manifest.json, background.js (Chrome, Edge, Brave, Opera, Vivaldi)
  firefox/         MV3 wrapper: manifest.json, background.js
  icons/           icon-16/32/48/128.png
  dist/            build output (git-ignored)
```

Wrappers only pick the browser and call `startBridge` from `core/src/bridge.js`. The wrapper
`background.js` files import `./core/src/...`, so the core is copied next to them at build time.
Loading `Extensions/chromium` or `Extensions/firefox` straight from the source tree will not work;
load the built copies instead.

## Build

From the repo root (needs the system `zip`; no npm install):

```sh
node scripts/build-extensions.mjs
```

This writes `Extensions/dist/chromium/`, `Extensions/dist/firefox/`, and
`Extensions/dist/tattle-chromium.zip` and `tattle-firefox.zip`.

## Test the core

```sh
cd Extensions/core && node --test
```

Tests use fakes only: no browser is started.

## Load unpacked

**Chrome, Edge, Brave, Opera, Vivaldi:** open `chrome://extensions` (or `edge://extensions`, etc.),
turn on Developer mode, click "Load unpacked", and pick `Extensions/dist/chromium`.
The Chromium `manifest.json` carries the `key` from `ExtensionIdentity.chromiumPublicKey`, so the
extension id is `bghfplclpgjikclebjcgpojhcpfoflag`, which the native-messaging host manifest allows.

**Firefox:** open `about:debugging#/runtime/this-firefox`, click "Load Temporary Add-on", and pick
`Extensions/dist/firefox/manifest.json`. The id is `tattle@hieuvd.dev`.

Both browsers look for the native host `dev.hieuvd.tattle` (production) and `dev.hieuvd.tattle.dev` (dev).
Missing hosts are retried with backoff and are harmless.
