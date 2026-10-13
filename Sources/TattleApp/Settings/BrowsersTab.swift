import AppKit
import SwiftUI
import TattleCore

struct BrowsersTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $model.useBrowserExtensions) {
                    Text("Use browser extensions")
                    Text("Mute, pause or close single tabs, not whole browsers.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)
            }

            Section {
                if model.browserRows.isEmpty {
                    Text("No supported browsers found.").foregroundStyle(.secondary)
                }
                ForEach(model.browserRows) { row in
                    LabeledContent {
                        HStack(spacing: 12) {
                            if row.browser == .safari {
                                EmptyView()  // nothing to install: Tattle carries the extension
                            } else if row.status == .notInstalled {
                                Button("Set Up") { model.install(row.browser) }
                            } else {
                                Button("Remove") { model.remove(row.browser) }
                            }
                        }
                    } label: {
                        Text(row.browser.displayName)
                        StatusLabel(status: row.status)
                    }
                    .disabled(!model.useBrowserExtensions)
                    if row.status == .hostInstalled { SetupSteps(browser: row.browser, model: model) }
                }
                if let error = model.browserError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: error).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Privacy & Security") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
                        }
                        .controlSize(.small)
                    }
                }
            } header: { Text("Installed Browsers") }
        }
        // The status changes on its own (an extension connects or drops), not only on a click,
        // so poll while this pane is on screen.
        .task {
            while !Task.isCancelled {
                model.refreshBrowsers()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct StatusLabel: View {
    let status: IntegrationStatus
    var body: some View {
        switch status {
        case .notInstalled:
            Text("Not set up").settingsSubtitleStyle()
        case .hostInstalled:
            Text("Waiting for the extension").settingsSubtitleStyle()
        case .connected:
            Text("Connected").font(.footnote).foregroundStyle(.green)
        }
    }
}

extension Browser {
    var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        case .brave: "Brave"
        case .arc: "Arc"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .chromium: "Chromium"
        case .firefox: "Firefox"
        case .safari: "Safari"
        }
    }
}

/// Shown under a browser whose bridge is installed but whose extension hasn't connected:
/// the one manual step macOS/the browser won't let Tattle do for the user.
private struct SetupSteps: View {
    let browser: Browser
    @Bindable var model: SettingsModel

    private var steps: String {
        browser == .safari
            ? "1. Open Safari Settings ▸ Extensions. 2. Tick Tattle. 3. Allow it on websites. (A development build also needs Develop ▸ Allow Unsigned Extensions.)"
            : browser == .firefox
            ? "1. Show the extension folder. 2. Open the debugging page and choose Load Temporary Add-on. 3. Pick manifest.json."
            : "1. Show the extension folder. 2. Open the extensions page and turn on Developer mode. 3. Choose Load unpacked and pick the folder."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(steps).settingsSubtitleStyle()
            HStack(spacing: 8) {
                if browser == .safari {
                    Button("Open Safari") { NSWorkspace.shared.open(URL(filePath: "/Applications/Safari.app")) }
                } else {
                    Button("Show Extension Folder") { model.revealExtension(for: browser) }
                    Button("Open Extensions Page") { ExtensionFiles.openExtensionsPage(for: browser) }
                }
            }
            .controlSize(.small)
        }
        .disabled(!model.useBrowserExtensions)
    }
}
