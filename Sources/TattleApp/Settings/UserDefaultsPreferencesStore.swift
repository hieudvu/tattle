import Foundation
import TattleCore

/// The real store. Missing keys read as the key's default (no registerDefaults
/// needed: `PreferenceKey` carries it), so "Restore Defaults" is just removal.
final class UserDefaultsPreferencesStore: PreferencesStore, @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func get<V: PreferenceValue>(_ key: PreferenceKey<V>) -> V {
        (defaults.object(forKey: key.name) as? V) ?? key.defaultValue
    }
    func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) {
        defaults.set(value, forKey: key.name)
    }
    func removeAll() {
        for name in PreferenceKeys.all { defaults.removeObject(forKey: name) }
    }
}
