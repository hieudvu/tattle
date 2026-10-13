# Tattle browser extension protocol (v1)

Tattle knows *which app* is playing sound from Core Audio. To know *which tab*,
and to mute / pause / close it, it talks to a small extension in the browser.

All messages are UTF-8 JSON objects with `"v": 1` and a `"type"`.

## Extension → Tattle

```json
{"v":1,"type":"hello","browser":"chrome","extensionVersion":"0.1.0"}
{"v":1,"type":"tabs","browser":"chrome","tabs":[
  {"id":"12:345","title":"Lo-fi beats","url":"https://youtube.com/…","audible":true,"muted":false}
]}
{"v":1,"type":"result","id":"<command id>","ok":true}
{"v":1,"type":"result","id":"<command id>","ok":false,"error":"tab not found"}
```

- `browser` is one of `chrome edge brave arc vivaldi opera chromium firefox safari`
  (matches `Browser.rawValue` in `TattleCore/Tabs.swift`). Chromium-family
  extensions detect the real brand (Edge/Brave/Arc/…) themselves.
- `tabs` is a **full snapshot**, never a delta. It contains every tab that is
  `audible` **or** `muted` (so a muted tab can still be unmuted). Send it on every
  relevant change (tab audible/muted/title/url/removed), debounced ~150 ms, and
  once right after `hello`.
- `id` is opaque: `"<windowId>:<tabId>"`.

## Tattle → extension

```json
{"v":1,"type":"command","id":"b2c1…","command":"mute","tabId":"12:345"}
```

`command` ∈ `mute unmute pause close focus` (`TabCommand` in `TattleCore/Tabs.swift`).
- `mute`/`unmute`: tab-level mute through the browser's own API.
- `pause`: pause every `<video>`/`<audio>` in every frame of the tab.
- `close`: close the tab. `focus`: activate the tab and its window.

The extension always answers with a `result` carrying the same `id`.

## Transports

| Browser | Transport |
|---|---|
| Chrome-family, Firefox | Native Messaging (stdio, 4-byte little-endian length prefix) to `tattle-bridge`, which relays to the Tattle app over a Unix socket. |
| Safari | `runtime.sendNativeMessage` to the containing app's Safari extension handler, which relays to the app. |

The extension *core* is transport-agnostic: it is handed a `transport`
(`send(message)`, `onMessage(cb)`, `onDisconnect(cb)`) and a `tabsApi` adapter, so
the same code runs everywhere and is unit-tested with fakes.

## Dev vs pro

The dev app (`Tattle Dev.app`, `dev.hieuvd.tattle.dev`) and the pro app
(`Tattle.app`, `dev.hieuvd.tattle`) must never talk to each other's extensions:
separate native-messaging host names (`dev.hieuvd.tattle[.dev]`), separate socket
paths, and the flavour is derived from the bundle the bridge lives in.
