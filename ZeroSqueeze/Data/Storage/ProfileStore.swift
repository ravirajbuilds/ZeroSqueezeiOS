import Foundation

/// Persists `UserProfile` to UserDefaults as JSON.
final class ProfileStore {
    @MainActor static let shared = ProfileStore()

    private let key = "zerosqueeze.user_profile.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    func save(_ profile: UserProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            defaults.set(data, forKey: key)
        } catch {
            ZSLogger.error(.data, "ProfileStore encode failed", error: error)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
