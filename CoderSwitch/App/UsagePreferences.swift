import Foundation

/// UserDefaults keys behind the General settings tab. Views read them with `@AppStorage`.
enum UsagePreferences {
    static let followedAccountKey = "menuBar.followedAccount"
    static let showsPercentageKey = "menuBar.showsPercentage"
    static let refreshMinutesKey = "usage.refreshMinutes"

    static let automaticFollow = "automatic"
    static let refreshMinuteOptions = [1, 2, 5, 15]
    static let defaultRefreshMinutes = 1

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            followedAccountKey: automaticFollow,
            showsPercentageKey: false,
            refreshMinutesKey: defaultRefreshMinutes,
        ])
    }

    static func refreshInterval(_ defaults: UserDefaults = .standard) -> Duration {
        let minutes = defaults.integer(forKey: refreshMinutesKey)
        return .seconds(60 * (refreshMinuteOptions.contains(minutes) ? minutes : defaultRefreshMinutes))
    }
}
