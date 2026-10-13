import SwiftUI
import TattleCore

struct BehaviorTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $model.autoQuitHeadless) {
                    Text("Quit noisy headless browsers")
                    Text("Quit --headless browsers left running by automation tools.").settingsSubtitleStyle()
                }
                .toggleStyle(.switch)

                LabeledContent {
                    HStack(spacing: 8) {
                        Text("\(model.autoQuitHeadlessAfterMinutes) min").monospacedDigit()
                        Stepper("After", value: $model.autoQuitHeadlessAfterMinutes, in: Preferences.autoQuitMinutesRange)
                            .labelsHidden()
                    }
                } label: {
                    Text("After")
                    Text("How long they can stay noisy first.").settingsSubtitleStyle()
                }
                .disabled(!model.autoQuitHeadless)
            } header: { Text("Headless Browsers") }
        }
    }
}
