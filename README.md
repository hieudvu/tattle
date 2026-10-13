<p align="center"><img src="docs/images/icon.png" alt="Tattle" width="128"></p>

<h1 align="center">Tattle</h1>

<p align="center">
  Tells you which app, and which browser tab, is making noise on your Mac,<br>
  and lets you mute, pause, skip, close or quit it from the menu bar.
</p>

<p align="center">
  <a href="https://github.com/hieudvu/tattle/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-111111?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS"></a>
</p>

<p align="center">
  <a href="https://github.com/hieudvu/tattle/releases/latest"><img src="https://img.shields.io/github/v/release/hieudvu/tattle?label=release" alt="Latest release"></a>
  <a href="https://github.com/hieudvu/tattle/releases"><img src="https://img.shields.io/github/downloads/hieudvu/tattle/total?label=downloads" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/hieudvu/tattle" alt="MIT license"></a>
</p>

<p align="center"><img src="docs/images/panel.png" alt="Tattle's menu bar panel listing Microsoft Edge with two noisy tabs and Safari playing a muted song" width="560"></p>

## Features

- See every app that is playing sound, live. Helper processes fold into their app.
- See the exact browser tab (title and site) with the browser extension.
- Mute, pause, skip, close a tab or quit the app, right from the menu bar.
- Shows what is playing next to the app.
- Private and light: nothing leaves your Mac, and it only scans while the panel is open.

## Install

1. Download the zip for your Mac from the [latest release](https://github.com/hieudvu/tattle/releases/latest):
   `arm64` for Apple silicon, `x86_64` for Intel.
2. Unzip and drag **Tattle** to Applications. Requires macOS 15+.
3. To mute whole apps, press **Grant** in Settings ▸ Permissions.

Tattle is signed, notarized and updates itself.

## Browser extension

Optional. It adds tab titles and per-tab controls. Open **Settings ▸ Browsers** and set up your browser:

| Browser | Steps |
| --- | --- |
| Chrome, Edge, Brave, Arc, Vivaldi, Opera | **Set Up**, then **Show Extension Folder** and **Open Extensions Page**. Turn on Developer mode, **Load unpacked**, pick the folder. |
| Firefox | **Show Extension Folder**, **Open Extensions Page**, **Load Temporary Add-on**, pick `manifest.json`. Repeat after Firefox restarts. |
| Safari | Safari ▸ Settings ▸ Extensions, tick **Tattle**, allow on all websites. |

The row turns **Connected** when it works. Chrome and Edge may nag about developer mode extensions; dismiss it.

## Development

See [docs/development.md](docs/development.md) for building, testing and releasing.

[MIT](LICENSE)
