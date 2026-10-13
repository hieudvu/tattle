import AppKit
import Observation
import SwiftUI
import TattleCore
import TattleSystem

/// Live state of the permissions Tattle can use. The grant changes in System Settings, not
/// in this window, so the pane re-reads it while it is on screen.
@MainActor @Observable
final class PermissionsModel {
    private(set) var audioCapture = AudioCaptureAccess.status()

    func refresh() {
        let current = AudioCaptureAccess.status()
        if current != audioCapture { audioCapture = current }
    }

    func requestAudioCapture() {
        AudioCaptureAccess.request { Task { @MainActor in self.refresh() } }
    }
}

struct PermissionsTab: View {
    static let audioCaptureURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    @State private var model = PermissionsModel()

    var body: some View {
        SettingsForm {
            Section {
                PermissionRow(
                    symbol: "speaker.slash",
                    title: "System Audio Recording",
                    detail: detail,
                    status: model.audioCapture,
                    onGrant: model.requestAudioCapture,
                    onOpenSettings: { NSWorkspace.shared.open(Self.audioCaptureURL) }
                )
            } header: { Text("Required to mute") }
        }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var detail: String {
        switch model.audioCapture {
        case .granted: "Tattle can mute apps. It never records or stores audio."
        case .denied: "Turn Tattle on in System Settings to mute apps."
        case .notDetermined: "Lets Tattle mute an app. It never records or stores audio."
        }
    }
}

struct PermissionRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: String
    let status: AudioCaptureStatus
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary)
                .frame(width: 30, height: 30)
                .overlay { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.secondary) }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(verbatim: detail).settingsSubtitleStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing.fixedSize()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .denied:
            HStack(spacing: 10) {
                Label("Not granted", systemImage: "xmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                Button("Open System Settings", action: onOpenSettings)
            }
        case .notDetermined:
            HStack(spacing: 8) {
                Button("Grant", action: onGrant).buttonStyle(.borderedProminent)
                Button("Open System Settings", action: onOpenSettings)
            }
        }
    }
}
