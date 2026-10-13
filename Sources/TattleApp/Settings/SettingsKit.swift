import SwiftUI

/// The grouped System-Settings body, as in Continuo's `SettingsForm`: a grouped
/// `Form` with a transparent scroll background so the window material shows
/// through the gaps between cards.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

extension View {
    /// Secondary caption under a row title. Grouped-form implicit styling for
    /// multi-`Text` labels is unreliable, so style it explicitly (as Continuo does).
    func settingsSubtitleStyle() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
