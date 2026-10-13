import Testing
@testable import TattleCore

final class FakePreferencesStore: PreferencesStore {
    var values: [String: Any] = [:]
    func get<V: PreferenceValue>(_ key: PreferenceKey<V>) -> V { (values[key.name] as? V) ?? key.defaultValue }
    func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) { values[key.name] = value }
    func removeAll() { values.removeAll() }
}

@Suite struct PreferencesTests {
    @Test func defaults() {
        let p = Preferences(from: FakePreferencesStore())
        #expect(p == Preferences())
        #expect(p.showMenuBarIcon && p.animateMenuBarIcon && p.confirmBeforeQuittingApps && p.useBrowserExtensions)
        #expect(!p.autoQuitHeadless && !p.launchAtLogin)
        #expect(p.autoQuitHeadlessAfterMinutes == 10)
    }

    @Test func roundTrip() {
        let store = FakePreferencesStore()
        var p = Preferences()
        p.showMenuBarIcon = false
        p.animateMenuBarIcon = false
        p.confirmBeforeQuittingApps = false
        p.autoQuitHeadless = true
        p.autoQuitHeadlessAfterMinutes = 30
        p.useBrowserExtensions = false
        p.launchAtLogin = true
        p.write(to: store)
        #expect(Preferences(from: store) == p)
    }

    @Test func minutesAreClamped() {
        var p = Preferences()
        p.autoQuitHeadlessAfterMinutes = 0
        #expect(p.autoQuitHeadlessAfterMinutes == 1)
        p.autoQuitHeadlessAfterMinutes = 9999
        #expect(p.autoQuitHeadlessAfterMinutes == 120)
        let store = FakePreferencesStore()
        store.set(-5, for: PreferenceKeys.autoQuitHeadlessAfterMinutes)
        #expect(Preferences(from: store).autoQuitHeadlessAfterMinutes == 1)
    }

    @Test func removeAllRestoresDefaults() {
        let store = FakePreferencesStore()
        store.set(false, for: PreferenceKeys.animateMenuBarIcon)
        store.removeAll()
        #expect(Preferences(from: store) == Preferences())
    }

    @Test func keyNamesAreUnique() {
        #expect(Set(PreferenceKeys.all).count == PreferenceKeys.all.count)
    }
}

@Suite struct AudioCaptureStatusTests {
    @Test(arguments: [(0, AudioCaptureStatus.granted), (1, .denied), (2, .notDetermined), (-1, .notDetermined)])
    func mapsTccPreflightResult(result: Int, expected: AudioCaptureStatus) {
        #expect(AudioCaptureStatus(tccPreflight: result) == expected)
    }
}
