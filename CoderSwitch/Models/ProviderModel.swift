import Foundation

struct ProviderModel: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String?
    var ownedBy: String?

    var displayName: String {
        name?.nonEmpty ?? id
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
