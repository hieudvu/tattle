import AppKit
import SwiftUI
import TattleCore

/// The menu-bar popover: native SwiftUI, system fonts/materials/symbols, no
/// custom chrome. Rows = one noisy app; trailing icon buttons = mute / quit.
struct NoisePanel: View {
    let model: NoiseModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let error = model.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 400)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Tattle").font(.headline)
            if isDevBuild {
                Text("DEV")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.22), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            if model.previewUpdateAvailable || UpdateController.shared.updateAvailable {
                Button("Update now") { UpdateController.shared.checkForUpdates() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            IconButton(symbol: "gearshape", tint: .secondary, label: "Settings… (⌘,)", size: 14) {
                SettingsWindowPresenter.shared.show()
            }
            .keyboardShortcut(",")
            IconButton(symbol: "power", tint: .secondary, label: "Quit Tattle (⌘Q)", size: 14) {
                model.shutDown()  // release taps, or muted apps would stay silent
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    private var content: some View { NoiseList(model: model) }
}

/// The noisy-app list shared by the menu-bar popover and Settings ▸ Sound.
struct NoiseList: View {
    let model: NoiseModel

    @ViewBuilder var body: some View {
        if model.noisemakers.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "speaker.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Nothing is making noise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            VStack(spacing: 2) {
                ForEach(model.noisemakers) { noisemaker in
                    let browserTabs = model.tabs(for: noisemaker)
                    // One tab = one thing making noise: fold it into the app row instead of
                    // repeating it underneath.
                    let onlyTab = browserTabs.count == 1 ? browserTabs.first : nil
                    NoiseRow(
                        noisemaker: noisemaker,
                        isMuted: model.isMuted(noisemaker),
                        // Two or more tabs: the app row is only the app (name, mute-all, quit);
                        // titles and transport belong to the tab rows below.
                        nowPlaying: browserTabs.count > 1 ? nil : model.nowPlaying(for: noisemaker),
                        tabCount: browserTabs.count,
                        onlyTab: onlyTab,
                        onShowTab: { if let onlyTab { model.send(.focus, to: onlyTab) } },
                        onMedia: { model.sendMedia($0, for: noisemaker) },
                        onToggleMute: { model.toggleMute(noisemaker) },
                        onCloseTab: onlyTab.map { tab in { model.send(.close, to: tab) } },
                        onQuit: { model.requestQuit(noisemaker, tabCount: browserTabs.count) }
                    )
                    if onlyTab == nil {
                        ForEach(browserTabs) { tab in
                            TabRow(tab: tab) { model.send($0, to: tab) }
                        }
                    }
                }
            }
            .padding(6)
        }
    }
}

private struct NoiseRow: View {
    let noisemaker: Noisemaker
    let isMuted: Bool
    var nowPlaying: NowPlayingInfo? = nil
    var tabCount = 0
    var onlyTab: TabInfo? = nil
    var onShowTab: () -> Void = {}
    var onMedia: (NowPlayingCommand) -> Void = { _ in }
    let onToggleMute: () -> Void
    /// Set on a row that stands for one tab: its X closes that tab, not the whole browser.
    var onCloseTab: (() -> Void)? = nil
    let onQuit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(bundlePath: noisemaker.bundlePath)
                .frame(width: 32, height: 32)
                .opacity(isMuted ? 0.55 : 1)

            if onlyTab != nil {
                // Clicking the text jumps to that tab (a Button, so one click is enough).
                Button(action: onShowTab) { titleBlock.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help("Show this tab")
            } else {
                titleBlock.help(helpText)
            }

            Spacer(minLength: 8)

            if let nowPlaying {
                IconButton(symbol: "backward.fill", tint: .secondary, label: "Previous", size: 12) { onMedia(.previous) }
                IconButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", tint: .secondary,
                           label: nowPlaying.isPlaying ? "Pause" : "Play", size: 14) { onMedia(.toggle) }
                IconButton(symbol: "forward.fill", tint: .secondary, label: "Next", size: 12) { onMedia(.next) }
            }
            IconButton(
                symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isMuted ? .orange : .secondary,
                label: isMuted ? "Unmute \(noisemaker.name)" : "Mute \(noisemaker.name)",
                action: onToggleMute
            )
            if let onCloseTab {
                IconButton(symbol: "xmark", tint: .secondary, label: "Close tab", size: 12, action: onCloseTab)
            } else {
                IconButton(
                    symbol: "xmark.circle.fill",
                    tint: .secondary,
                    label: "Quit \(noisemaker.name)",
                    action: onQuit
                )
            }
        }
        .contextMenu {
            if onCloseTab != nil { Button("Quit \(noisemaker.name)", action: onQuit) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rowTitle).lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var rowTitle: String {
        if let nowPlaying { return nowPlaying.title }
        if let t = onlyTab?.title, !t.isEmpty { return t }
        return noisemaker.name
    }

    /// With a known title the app name moves down here; otherwise this says what is happening.
    private var subtitle: String {
        var parts: [String] = []
        if isMuted { parts.append("Muted") }
        if let nowPlaying {
            if let artist = nowPlaying.artist { parts.append(artist) }
            parts.append(noisemaker.name)
        } else if let onlyTab, !onlyTab.title.isEmpty {
            parts.append(noisemaker.name)
        } else if tabCount > 1 {
            parts.append("\(tabCount) tabs playing audio")
        } else if !isMuted {
            parts.append("Playing audio")
        }
        if noisemaker.isHeadless { parts.append("headless") }
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        var lines = ["pid \(noisemaker.ownerPID)"]
        if !noisemaker.commandLine.isEmpty { lines.append(noisemaker.commandLine) }
        return lines.joined(separator: "\n")
    }
}

/// One browser tab under its browser's row: title + host, then mute / pause / close.
private struct TabRow: View {
    let tab: TabInfo
    let onCommand: (TabCommand) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            // A Button, not onTapGesture: in a popover of an inactive app a tap gesture swallows
            // the first click (it only makes the window key), which made this need a double click.
            Button { onCommand(.focus) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title.isEmpty ? host : tab.title)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(tab.isMuted ? .secondary : .primary)
                    Text(host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show this tab")

            IconButton(
                symbol: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: tab.isMuted ? .orange : .secondary,
                label: tab.isMuted ? "Unmute tab" : "Mute tab",
                action: { onCommand(tab.isMuted ? .unmute : .mute) }
            )
            IconButton(symbol: "pause.fill", tint: .secondary, label: "Pause tab", action: { onCommand(.pause) })
            IconButton(symbol: "xmark", tint: .secondary, label: "Close tab", action: { onCommand(.close) })
        }
        .padding(.leading, 50)  // align under the app name, past its icon
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }

    private var host: String { URL(string: tab.url)?.host ?? tab.url }
}

private struct IconButton: View {
    let symbol: String
    let tint: Color
    let label: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The owning app's real icon, or a speaker glyph for a bare process.
private struct AppIcon: View {
    let bundlePath: String?

    var body: some View {
        if let bundlePath {
            Image(nsImage: IconCache.icon(forBundleAt: bundlePath)).resizable().interpolation(.high)
        } else {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor private enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleAt path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
