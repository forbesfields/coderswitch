import Foundation
import CryptoKit

struct PKCEChallenge {
    let verifier: String
    let challenge: String
    let method: String = "S256"

    init() {
        let size = 32
        var bytes = [UInt8](repeating: 0, count: size)
        _ = SecRandomCopyBytes(kSecRandomDefault, size, &bytes)
        verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let hash = Data(SHA256.hash(data: Data(verifier.utf8)))
        challenge = hash.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}