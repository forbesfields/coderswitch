import Foundation
import CoderSwitchCore

extension UsageWindow {
    var title: String {
        switch self {
        case .session: "Session"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .credits: "Credits"
        }
    }
}

/// Session and weekly usage for one account, as shown by the menu bar meter.
struct MeterReading: Equatable, Sendable {
    var session: Double?
    var weekly: Double?

    static let empty = MeterReading()

    /// The higher of the two fractions; this is the number the menu bar can print.
    var worst: Double? {
        [session, weekly].compactMap { $0 }.max()
    }
}

/// How an account's limits split between the two headline bars and the rest.
struct AccountUsageSummary {
    struct Headline: Identifiable {
        let title: String
        let limit: UsageLimit
        var id: String { limit.id }
    }

    var headlines: [Headline]
    var others: [UsageLimit]
}

extension Account {
    /// Limits worth showing. Hides Google's internal placeholder models.
    private var visibleLimits: [UsageLimit] {
        usageLimits.filter { !$0.isGoogleAntigravityInternalModel }
    }

    /// The session bar, falling back to a daily window when a provider has no session window.
    var sessionLimit: UsageLimit? {
        let withFraction = visibleLimits.filter { $0.fraction != nil }
        return withFraction.first { $0.window == .session } ?? withFraction.first { $0.window == .daily }
    }

    var weeklyLimit: UsageLimit? {
        visibleLimits.first { $0.window == .weekly && $0.fraction != nil }
    }

    /// Stale numbers from a failed poll are not trusted for the menu bar.
    var meterReading: MeterReading {
        guard lastCheckError == nil else { return .empty }
        return MeterReading(session: sessionLimit?.fraction, weekly: weeklyLimit?.fraction)
    }

    var usageSummary: AccountUsageSummary {
        var headlines: [AccountUsageSummary.Headline] = []
        if let sessionLimit {
            headlines.append(.init(title: sessionLimit.window?.title ?? "Session", limit: sessionLimit))
        }
        if let weeklyLimit {
            headlines.append(.init(title: "Weekly", limit: weeklyLimit))
        }
        // Providers without session or weekly windows (Google models, custom sites) lead with their own limits.
        if headlines.isEmpty {
            let lead = (provider == .googleAntigravity ? menuBarUsageLimits : visibleLimits).prefix(3)
            headlines = lead.map { .init(title: $0.name, limit: $0) }
        }
        let shown = Set(headlines.map(\.id))
        return AccountUsageSummary(headlines: headlines, others: visibleLimits.filter { !shown.contains($0.id) })
    }
}

/// Which account the menu bar meter follows, and what it should draw.
struct MenuBarMeterState: Equatable {
    var reading: MeterReading
    var showsPercentage: Bool
    var tooltip: String

    var percentText: String? {
        guard showsPercentage, let worst = reading.worst else { return nil }
        return UsageFormat.percent(worst)
    }

    static func make(accounts: [Account], selection: String, showsPercentage: Bool) -> MenuBarMeterState {
        guard let account = followedAccount(in: accounts, selection: selection) else {
            return MenuBarMeterState(reading: .empty, showsPercentage: showsPercentage, tooltip: "CoderSwitch")
        }
        let reading = account.meterReading
        return MenuBarMeterState(
            reading: reading,
            showsPercentage: showsPercentage,
            tooltip: tooltip(for: account, reading: reading, among: accounts)
        )
    }

    /// A chosen account wins if it still exists; otherwise the enabled account with the highest usage.
    static func followedAccount(in accounts: [Account], selection: String) -> Account? {
        if selection != UsagePreferences.automaticFollow,
           let chosen = accounts.first(where: { $0.id.uuidString == selection }) {
            return chosen
        }
        let enabled = accounts.filter(\.isEnabled)
        return enabled
            .filter { $0.meterReading.worst != nil }
            .max { ($0.meterReading.worst ?? 0) < ($1.meterReading.worst ?? 0) }
            ?? enabled.first
    }

    private static func tooltip(for account: Account, reading: MeterReading, among accounts: [Account]) -> String {
        var name = account.provider.displayName
        if accounts.filter({ $0.provider == account.provider }).count > 1 {
            name += " (\(account.label))"
        }
        var parts = [name]
        if let session = reading.session { parts.append("Session \(UsageFormat.percent(session))") }
        if let weekly = reading.weekly { parts.append("Weekly \(UsageFormat.percent(weekly))") }
        if parts.count == 1 {
            parts.append(account.lastCheckError == nil ? "No usage data yet" : "Usage unavailable")
        }
        return parts.joined(separator: " · ")
    }
}
