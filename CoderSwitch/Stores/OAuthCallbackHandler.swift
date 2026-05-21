import Foundation
import AppKit

@MainActor
@Observable
final class OAuthCallbackHandler {
    var isProcessing = false
    var lastError: String?

    func handle(url: URL) -> Bool {
        // No longer needed - we use localhost callback server instead
        return false
    }
}