import SwiftUI

struct GeneralTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Open at login")
                    Text("Start Tattle when you log in.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)
                if let error = model.launchAtLoginError {
                    Text(verbatim: error).font(.callout).foregroundStyle(.red)
                }
            } header: { Text("Startup") }

            Section {
                Toggle(isOn: $model.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("If hidden, open Tattle again to reach Settings.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)
                Toggle(isOn: $model.animateMenuBarIcon) {
                    Text("Animate the menu bar icon")
                    Text("The rays light up while something is noisy.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)
                .disabled(!model.showMenuBarIcon)
                Toggle(isOn: $model.showNowPlayingTitles) {
                    Text("Show what's playing")
                    Text("Show the video or song title next to the app.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)
            } header: { Text("Menu Bar") }

            Section {
                Toggle(isOn: $model.confirmBeforeQuittingApps) {
                    Text("Confirm before quitting apps")
                    Text("Quitting can lose unsaved work.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)
            } header: { Text("Quitting") }
        }
    }
}
