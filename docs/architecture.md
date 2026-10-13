# Tattle architecture

```
TattleCore     pure logic + protocols (audio source, inspector, terminator, muter,
               tabs, browser integrations, preferences). No system calls. Tested with fakes.
TattleSystem   real implementations: Core Audio HAL, sysctl, kill, process taps,
               tab bridge socket server, native-messaging installer.
TattleBridge   `tattle-bridge`: native-messaging host (stdio) <-> app (unix socket).
TattleApp      SwiftUI menu bar app + Settings window.
Extensions/    browser extensions: core/ (shared JS) + chromium/ firefox/ safari/.
```

Rules:
- Tests link `TattleCore` only (plus pure JS tests under `Extensions/core`). Nothing
  in a test may touch the host: no Core Audio, no signals, no real sockets/files
  outside a temp dir, no real browser.
- Dev (`Tattle Dev`) and pro (`Tattle`) differ only by name/bundle id; the pro
  bundle is verified to carry no dev suffix (`make p`).
- Warning-clean builds (`swift build`) and green `swift test` before a commit.
