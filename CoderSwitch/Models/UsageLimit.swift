import Foundation

/// A single quota dimension for an account (e.g. monthly credit, daily request count).
/// Optional fields stay nil when a provider only reports a subset.
struct UsageLimit: Codable, Hashable, Identifiable, Sendable {
    var id: String { storageID }
    var name: String
    var storageID: String
    var used: Double?
    var limit: Double?
    var valuePrefix: String?
    var unit: String?
    var resetAt: Date?
    /// Marks quota values that have already been normalized into consumed usage.
    /// Nil means the value came from older app data before this distinction existed.
    var valueKind: String? = "used"
    /// When true, this is a pay-as-you-go metric with no upper limit (no progress bar shown).
    var isPayAsYouGo: Bool = false

    init(
        name: String,
        storageID: String? = nil,
        used: Double? = nil,
        limit: Double? = nil,
        valuePrefix: String? = nil,
        unit: String? = nil,
        resetAt: Date? = nil,
        valueKind: String? = "used",
        isPayAsYouGo: Bool = false
    ) {
        self.name = name
        self.storageID = storageID ?? name
        self.used = used
        self.limit = limit
        self.valuePrefix = valuePrefix
        self.unit = unit
        self.resetAt = resetAt
        self.valueKind = valueKind
        self.isPayAsYouGo = isPayAsYouGo
    }

    enum CodingKeys: String, CodingKey {
        case name
        case storageID
        case used
        case limit
        case valuePrefix
        case unit
        case resetAt
        case valueKind
        case isPayAsYouGo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        storageID = try container.decodeIfPresent(String.self, forKey: .storageID) ?? name
        used = try container.decodeIfPresent(Double.self, forKey: .used)
        limit = try container.decodeIfPresent(Double.self, forKey: .limit)
        valuePrefix = try container.decodeIfPresent(String.self, forKey: .valuePrefix)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        valueKind = try container.decodeIfPresent(String.self, forKey: .valueKind) ?? "used"
        isPayAsYouGo = try container.decodeIfPresent(Bool.self, forKey: .isPayAsYouGo) ?? false
    }

    var fraction: Double? {
        guard let used, let limit, limit > 0, !isPayAsYouGo else { return nil }
        if valueKind == "googleAntigravityRemainingPercent" {
            return min(1.0, max(0.0, 1.0 - (used / limit)))
        }
        return min(1.0, max(0.0, used / limit))
    }

    var remainingDescription: String? {
        if isPayAsYouGo {
            guard let used else { return nil }
            return formatValue(used)
        }
        if valueKind == "googleAntigravityRemainingPercent",
           let used,
           let limit {
            let remaining = min(limit, max(0, used))
            let consumed = max(0, limit - remaining)
            return "\(formatValue(consumed))% used"
        }
        guard let limit else { return nil }
        let used = used ?? 0
        let unit = unit ?? ""
        return "\(formatValue(used))\(unit) of \(formatValue(limit))\(unit)"
    }

    func displayValue(_ value: Double) -> String {
        formatValue(value) + (unit ?? "")
    }

    private func format(_ v: Double) -> String {
        if v >= 100 || v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v.rounded()))
        }
        return String(format: "%.2f", v)
    }

    private func formatValue(_ v: Double) -> String {
        (valuePrefix ?? "") + format(v)
    }
}

extension UsageLimit {
    var isGoogleAntigravityInternalModel: Bool {
        let identifiers = [name, storageID].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return identifiers.contains { value in
            value.hasPrefix("model_placeholder")
                || value.hasPrefix("chat_")
                || value.hasPrefix("tab_")
        }
    }
}
