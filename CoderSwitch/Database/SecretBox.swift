import Foundation
import CryptoKit

/// AES-GCM encryption for secrets stored in SQLite.
/// Master key lives at ~/Library/Application Support/CoderSwitch/.master.key (mode 0600).
/// Generated on first launch. No Keychain involved — user explicitly requested moving away from Keychain.
enum SecretBox {
    private static let key: SymmetricKey = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoderSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyURL = dir.appendingPathComponent(".master.key")

        if let existing = try? Data(contentsOf: keyURL), existing.count == 32 {
            return SymmetricKey(data: existing)
        }

        let new = SymmetricKey(size: .bits256)
        let raw = new.withUnsafeBytes { Data($0) }
        try? raw.write(to: keyURL, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: keyURL.path
        )
        return new
    }()

    static func seal(_ plaintext: String) throws -> Data {
        let data = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw SecretBoxError.encryptionFailed
        }
        return combined
    }

    static func open(_ ciphertext: Data) throws -> String {
        let sealed = try AES.GCM.SealedBox(combined: ciphertext)
        let data = try AES.GCM.open(sealed, using: key)
        guard let str = String(data: data, encoding: .utf8) else {
            throw SecretBoxError.decryptionFailed
        }
        return str
    }
}

enum SecretBoxError: Error {
    case encryptionFailed
    case decryptionFailed
}
