# Tattle for Safari

Safari Web Extensions are app extensions (`.appex`) embedded in a containing app, and they have no
Native Messaging stdio. So:

```
Safari tab APIs <-> background.js (shared core session)
   --browser.runtime.sendNativeMessage-->  SafariWebExtensionHandler (the appex, sandboxed)
   --Unix socket, 4-byte LE length + JSON-->  Tattle app (same socket tattle-bridge uses)
```

- `manifest.json`, `background.js`: thin wrapper like `chromium/` and `firefox/` (`browser="safari"`).
  The session runs over `core/src/webext/pollingTransport.js` (one `sendNativeMessage` per outbound
  message plus a poll timer; the handler piggybacks queued commands on every response).
- `App/SafariRelay.swift`: all handler logic, pure (the app link is a protocol). `UnixSocketLink.swift`:
  thin POSIX client. `SafariWebExtensionHandler.swift`: the `NSExtensionRequestHandling` shell.
- `test/run-tests.sh`: standalone checks of relay + framing + a real socket in a temp dir.
  JS side: `cd Extensions/core && node --test`.

## Build

```sh
scripts/build-safari-extension.sh <dev|pro> "build/Tattle Dev.app"   # after scripts/bundle.sh
```

Embeds `Contents/PlugIns/TattleSafari[ Dev].appex` (ids `dev.hieuvd.tattle[.dev].safari`) and re-signs the
app. `SIGN_IDENTITY` (default ad-hoc `-`) and `ARCHS` (default host arch) are overridable.

### Why swiftc and not safari-web-extension-converter + xcodebuild
The converter needs a generated Xcode project (a throwaway app target, its own bundle ids/signing)
that would then have to be merged into our SPM-assembled app. An appex is just a bundle: `swiftc` with
`-application-extension` and entry `_NSExtensionMain`, an Info.plist with
`com.apple.Safari.web-extension`, resources in `Contents/Resources`, and `codesign` with the sandbox
entitlements. That is reproducible from one script with no Xcode project.

## Design notes
- **Polling.** Commands are user clicks, so ~1 s latency is invisible. Poll every 1 s while the last
  snapshot held an audible/muted tab, every 5 s otherwise; a tab event sends a snapshot immediately
  (which also drains commands). Failures (`tattle-not-running`, handler gone) are a disconnect and the
  shared reconnector backs off 2 s..60 s; each retry is one cheap local call.
- **Unloaded pages.** `"persistent": false` (required by manifest v3) lets Safari unload the page at any time; a
  1-minute `alarms` listener (registered at top level) makes Safari reload it, and `startBridge()` sends a
  fresh `hello` + full snapshot. Worst-case command gap after an unload is one alarm period.
- **No App Group.** App Groups need a team-prefixed id (breaks ad-hoc/dev builds) and the app already
  serves this socket. The sandboxed appex gets `network.client` plus temporary exceptions for only
  `~/Library/Application Support/Tattle[ Dev]/`. Temporary exceptions are fine for Developer ID, not for
  the Mac App Store (that would need an App Group and a socket/XPC moved into the group container).
- **Dev/pro isolation.** The flavour is stamped into the appex Info.plist (`TattleFlavour`); a dev appex
  can only open the "Tattle Dev" socket.

## Using it
1. Launch the app once (registers the embedded appex), then Safari > Settings > Extensions > enable Tattle.
2. Grant website access ("Always Allow on Every Website"); needed for pausing media and for tab titles/URLs.
3. Ad-hoc or unsigned builds: Safari > Develop > Allow Unsigned Extensions (resets each Safari launch;
   enable the Develop menu in Settings > Advanced).

A real build uses `SIGN_IDENTITY="Developer ID Application: ..."` plus hardened runtime and notarization
(add `--options runtime` to the codesign calls), and Safari then needs no Develop setting.

## Not verified here (no Safari UI access)
Safari loading/enabling the appex, `type:"module"` + `persistent:false` background pages, the sandbox
exceptions actually permitting the `connect()` to the app's socket (the sbpl rule is the likeliest thing
to need tuning), `tabs` audible/mutedInfo events and `scripting.executeScript` behaviour in Safari.
