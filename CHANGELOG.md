# Changelog

All notable changes to Tattle are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/). Pushing a `v<version>` tag publishes the matching section
below as the GitHub Release notes and as the release notes in Tattle's update window, so a release
cannot be cut without one.

## [Unreleased]

## [0.1.1] - 2026-10-13

### Fixed
- Tattle no longer quits when you press Grant in Settings ▸ Permissions to allow System Audio Recording.

## [0.1.0] - 2026-10-13

First public release. Requires macOS 15 or later (Apple silicon and Intel).

### Added

**See what is making noise**

- A menu bar list of every app playing sound right now. Helper processes are folded into the app that owns them, so Chrome's helpers show up as Chrome and Safari's WebKit GPU process shows up as Safari.
- Now Playing titles and artists next to the app, as macOS shows them, with previous, play/pause and next buttons. Only shown when the title belongs to a tab that is really audible.
- The same live list in Settings ▸ Sound, for people who prefer not to keep Tattle in the menu bar.
- An animated whistle in the menu bar while something is audible. It stays still under Reduce Motion and can be switched off.

**Control it**

- Mute any app without quitting it, and unmute it again. Muted apps stay listed until they exit.
- Quit a noisy app from its row, with an optional confirmation (Settings ▸ General). Tattle re-checks the process right before quitting, so a reused process ID can never be hit by mistake.
- Tab-level control with browser extensions for Chrome, Edge, Brave, Arc, Vivaldi, Opera and other Chromium browsers, Firefox and Safari: mute, pause, close or jump to the exact tab. One noisy tab folds into its app row; two or more get a row each.
- Auto-quit for headless browsers that have been noisy for too long (Settings ▸ Behavior).

**Settings**

- Settings ▸ General: show or hide the menu bar icon, animate it, confirm before quitting apps, show Now Playing titles, open at login. Open Tattle again to bring Settings back when the icon is hidden.
- Settings ▸ Browsers: one-click setup of the browser connection, step-by-step instructions for loading the extension, and live connection status for every installed browser.
- Settings ▸ Permissions: shows whether System Audio Recording is granted and lets you request it.
- Settings ▸ About, with automatic update checks for the Apple silicon and Intel builds.
- "Reset to Defaults" on the panes that have settings.

**Light on resources**

- Scans once a second only while the list is on screen, every five seconds in the background while the icon or auto-quit needs it, and not at all otherwise.

**Privacy**

- Everything stays on your Mac. The extensions read tab titles and addresses only to show them in Tattle and talk to it over a local connection; nothing is recorded or sent anywhere.
