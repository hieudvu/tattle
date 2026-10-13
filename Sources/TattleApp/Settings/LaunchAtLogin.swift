import ServiceManagement

/// Swappable seam over `SMAppService.mainApp` so the UI never needs the host.
protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SMAppServiceLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Inert stand-in for previews and rendering.
final class FakeLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
