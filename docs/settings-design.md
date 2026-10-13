# Settings design

Reference: Continuo's Settings (`SettingsRootView`, `SettingsWindowPresenter`, `ContinuoSettings`).

## Adopted from Continuo
- **Sidebar + detail**: `NavigationSplitView(columnVisibility: .constant(.all))` with a
  `List(selection:)` of `Label`s (SF Symbols), sidebar toggle removed, nil selection ignored,
  sidebar width pinned with the same `SidebarWidthLock` constraint trick (the SwiftUI
  column-width modifier is ignored on macOS 26). Detail is a grouped `Form`.
- **Window owned by AppKit**: `NSHostingController` with `sizingOptions = []`, style
  `.titled/.closable/.resizable/.fullSizeContentView`, `contentMinSize`, `setContentSize`;
  SwiftUI has no `.frame(min/ideal)` at the root, so moving displays never resizes it.
- **Accessory-app presentation**: flip to `.regular` + `activate` when shown, back to
  `.accessory` on `windowWillClose`; one reusable window, `shared.show()` is the only entry.
- **Settings as a key catalog + defaults**: typed `PreferenceKeys` with defaults next to the key
  (Continuo: `SettingsKey` + `SettingsDefaults`); Restore Defaults = remove the keys.
- **Tab enum owns title + symbol** (`SettingsTabID`, like `SettingsTab`).

## Adapted
- Defaults live on `PreferenceKey` (missing value reads as default) instead of
  `registerDefaults`, so the pure core needs no UserDefaults and tests use a fake store.
- Observation: an `@Observable` model writes through to the store on every change (Continuo
  uses `@AppStorage`, which would drag UserDefaults into the views and tests).
- Launch at login reads `SMAppService` status as the source of truth, behind a protocol.

## Skipped on purpose
- `ChromelessWindow` / tall transparent titlebar, hand-drawn pane header and opaque
  background, `SettingsStepRow` tiles and `Brand` colours: custom chrome; we use system
  grouped Form, `navigationTitle`, and system colours.
- Per-pane reset button, Pro gating, licence/devtools panes, deep-link `settingsTargetTab`
  (Tattle has one Restore Defaults button on General and no tiers yet).
