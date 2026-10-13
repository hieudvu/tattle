import AppKit
import SwiftUI

struct AboutTab: View {
    static let repoURL = URL(string: "https://github.com/hieudvu/tattle")!

    @Bindable private var updates = UpdateController.shared

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "\(v) (\($0))" } ?? v
    }
    private var isDev: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // Identity header above the form, not boxed in a card (as in Continuo).
            VStack(spacing: 10) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                HStack(spacing: 6) {
                    Text(verbatim: "Tattle").font(.system(size: 20, weight: .semibold))
                    if isDev {
                        Text("Dev").font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(verbatim: "Version \(version)").font(.system(size: 12)).foregroundStyle(.tertiary)
                Text("See which app is making noise, then quiet it.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 8)

            SettingsForm {
                if updates.isAvailable {
                    Section {
                        Toggle(isOn: $updates.automaticallyChecks) {
                            Text("Automatically check for updates")
                            Text("Check in the background and ask before installing.").settingsSubtitleStyle()
                        }
                        .toggleStyle(.switch)
                        LabeledContent {
                            Button("Check for Updates…") { updates.checkForUpdates() }
                        } label: {
                            Text("Updates")
                        }
                    } header: { Text("Updates") }
                }

                Section {
                    LabeledContent {
                        Link("github.com/hieudvu/tattle", destination: Self.repoURL)
                    } label: {
                        Text("Source code")
                        Text("Released under the MIT License.").settingsSubtitleStyle()
                    }
                }
            }
        }
    }
}
