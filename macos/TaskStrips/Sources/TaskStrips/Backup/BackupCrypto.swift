import CommonCrypto
import CryptoKit
import Foundation

/// The portable encryption a backup uses for credential passwords, matching BackupCrypto.kt
/// parameter for parameter — PBKDF2-HMAC-SHA256 at 120,000 iterations to a 256-bit key, then
/// AES-GCM with a 128-bit tag, each field base64 with no line breaks.
///
/// Portable is the whole point. A credential's password on the phone is encrypted under a
/// Keystore key that doesn't leave the device, and on this Mac it's in the login keychain, which
/// doesn't either. Neither survives the trip, so a backup re-encrypts under a passphrase the user
/// holds — and without one, carries no password at all rather than writing it in the clear.
enum BackupCrypto {
    static let iterations: UInt32 = 120_000
    static let keyLengthBytes = 32
    static let saltLengthBytes = 16
    /// AES-GCM's tag, which Java appends to the ciphertext and CryptoKit keeps beside it.
    static let tagLengthBytes = 16

    /// The three base64 fields a backup stores per password.
    struct Encrypted: Equatable {
        var salt: String
        var iv: String
        var cipher: String
    }

    static func encrypt(_ plainText: String, passphrase: String) -> Encrypted? {
        var saltBytes = [UInt8](repeating: 0, count: saltLengthBytes)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            return nil
        }
        let salt = Data(saltBytes)
        guard let key = deriveKey(passphrase: passphrase, salt: salt),
              let sealed = try? AES.GCM.seal(Data(plainText.utf8), using: key)
        else { return nil }

        return Encrypted(
            salt: salt.base64EncodedString(),
            iv: Data(sealed.nonce).base64EncodedString(),
            // Java hands back ciphertext with the tag appended; CryptoKit keeps them apart. Joined
            // here so the two write the same bytes.
            cipher: (sealed.ciphertext + sealed.tag).base64EncodedString()
        )
    }

    /// Nil on any failure — a wrong passphrase, a truncated field, bytes someone edited. GCM's
    /// tag makes a wrong key reliably detectable rather than silently producing garbage, so a
    /// caller can treat nil as "not this one" and carry on with the rest of the backup.
    static func decrypt(_ encrypted: Encrypted, passphrase: String) -> String? {
        guard let salt = Data(base64Encoded: encrypted.salt),
              let iv = Data(base64Encoded: encrypted.iv),
              let body = Data(base64Encoded: encrypted.cipher),
              body.count > tagLengthBytes,
              let key = deriveKey(passphrase: passphrase, salt: salt),
              let nonce = try? AES.GCM.Nonce(data: iv)
        else { return nil }

        let ciphertext = body.prefix(body.count - tagLengthBytes)
        let tag = body.suffix(tagLengthBytes)
        guard let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
              let plain = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// PBKDF2 through CommonCrypto, since CryptoKit has no key derivation of this kind.
    ///
    /// Internal rather than private so a test can check the derived bytes against a vector
    /// computed outside Swift entirely — the iteration count, hash and key length are exactly the
    /// parameters that would silently diverge from the phone's.
    static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey? {
        var derived = [UInt8](repeating: 0, count: keyLengthBytes)
        let passphraseBytes = Array(passphrase.utf8)
        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            guard let saltBase = saltBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return Int32(kCCParamError)
            }
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passphrase, passphraseBytes.count,
                saltBase, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                iterations,
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: Data(derived))
    }
}
