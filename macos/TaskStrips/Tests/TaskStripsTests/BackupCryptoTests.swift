import CryptoKit
import XCTest
@testable import TaskStrips

/// This is the one place the Mac has to agree with the phone byte for byte: a password encrypted
/// on Android has to open here, and one written here has to open there. Nothing in the app would
/// notice a mismatch — a wrong key produces a failed decrypt, which looks exactly like a wrong
/// passphrase.
final class BackupCryptoTests: XCTestCase {
    private let passphrase = "correct horse battery staple"

    // MARK: - The parameters that have to match

    /// The vector was computed outside Swift entirely (Python's hashlib.pbkdf2_hmac), so this
    /// pins the four things that could silently diverge from BackupCrypto.kt — the hash, the
    /// iteration count, the key length, and that the passphrase is hashed as UTF-8.
    func testTheDerivedKeyMatchesAVectorComputedElsewhere() throws {
        let salt = try XCTUnwrap(Data(base64Encoded: "dGFza3N0cmlwLXRlc3QwMQ=="))
        let key = try XCTUnwrap(BackupCrypto.deriveKey(passphrase: passphrase, salt: salt))

        let bytes = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(
            bytes.map { String(format: "%02x", $0) }.joined(),
            "e2a88ea7b43c0cb5ab814fb6f7df4081343d6509fdb8bedee82077e46de66f45"
        )
    }

    func testTheParametersAreTheOnesAndroidUses() {
        XCTAssertEqual(BackupCrypto.iterations, 120_000)
        XCTAssertEqual(BackupCrypto.keyLengthBytes, 32)
        XCTAssertEqual(BackupCrypto.saltLengthBytes, 16)
        XCTAssertEqual(BackupCrypto.tagLengthBytes, 16)
    }

    /// Java hands back ciphertext with the GCM tag appended and the IV separately; CryptoKit
    /// keeps all three apart. If this framing were wrong, everything would still round-trip here
    /// and nothing would open on the phone.
    func testTheCipherFieldCarriesTheTagAppendedToTheCiphertext() throws {
        let encrypted = try XCTUnwrap(BackupCrypto.encrypt("hunter2", passphrase: passphrase))
        let body = try XCTUnwrap(Data(base64Encoded: encrypted.cipher))
        let iv = try XCTUnwrap(Data(base64Encoded: encrypted.iv))

        XCTAssertEqual(body.count, Data("hunter2".utf8).count + BackupCrypto.tagLengthBytes)
        // 12 bytes is what both AES.GCM and the JCE generate for GCM by default.
        XCTAssertEqual(iv.count, 12)
        XCTAssertEqual(try XCTUnwrap(Data(base64Encoded: encrypted.salt)).count, 16)
    }

    /// Base64 with no line breaks, matching Base64.NO_WRAP — a wrapped field would come back as
    /// something the phone's decoder rejects.
    func testEveryFieldIsUnwrappedBase64() throws {
        let encrypted = try XCTUnwrap(
            BackupCrypto.encrypt(String(repeating: "long password ", count: 20), passphrase: passphrase)
        )
        for field in [encrypted.salt, encrypted.iv, encrypted.cipher] {
            XCTAssertFalse(field.contains("\n"))
            XCTAssertNotNil(Data(base64Encoded: field))
        }
    }

    // MARK: - Round trips

    func testWhatIsEncryptedComesBackOut() throws {
        let encrypted = try XCTUnwrap(BackupCrypto.encrypt("hunter2", passphrase: passphrase))
        XCTAssertEqual(BackupCrypto.decrypt(encrypted, passphrase: passphrase), "hunter2")
    }

    func testANonAsciiPasswordSurvives() throws {
        let secret = "كلمة السر 🔐"
        let encrypted = try XCTUnwrap(BackupCrypto.encrypt(secret, passphrase: "جواز"))
        XCTAssertEqual(BackupCrypto.decrypt(encrypted, passphrase: "جواز"), secret)
    }

    func testEachEncryptionUsesAFreshSaltAndNonce() throws {
        let first = try XCTUnwrap(BackupCrypto.encrypt("hunter2", passphrase: passphrase))
        let second = try XCTUnwrap(BackupCrypto.encrypt("hunter2", passphrase: passphrase))

        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.iv, second.iv)
        XCTAssertNotEqual(first.cipher, second.cipher, "the same password twice must not look the same")
    }

    // MARK: - Failing safely

    func testTheWrongPassphraseReturnsNothingRatherThanGarbage() throws {
        let encrypted = try XCTUnwrap(BackupCrypto.encrypt("hunter2", passphrase: passphrase))
        XCTAssertNil(BackupCrypto.decrypt(encrypted, passphrase: "not it"))
    }

    /// GCM authenticates the ciphertext, so an edited backup fails to open rather than yielding a
    /// password that was never written.
    func testTamperedBytesDoNotOpen() throws {
        let encrypted = try XCTUnwrap(BackupCrypto.encrypt("hunter2", passphrase: passphrase))
        var body = try XCTUnwrap(Data(base64Encoded: encrypted.cipher))
        body[0] ^= 0xFF

        let tampered = BackupCrypto.Encrypted(
            salt: encrypted.salt,
            iv: encrypted.iv,
            cipher: body.base64EncodedString()
        )
        XCTAssertNil(BackupCrypto.decrypt(tampered, passphrase: passphrase))
    }

    func testNonsenseFieldsDoNotOpenAndDoNotCrash() {
        let cases = [
            BackupCrypto.Encrypted(salt: "!!!", iv: "!!!", cipher: "!!!"),
            BackupCrypto.Encrypted(salt: "", iv: "", cipher: ""),
            // Shorter than the tag, so there is no ciphertext at all.
            BackupCrypto.Encrypted(salt: "dGFza3N0cmlwLXRlc3QwMQ==", iv: "AAAAAAAAAAAAAAAA", cipher: "AAAA"),
        ]
        for encrypted in cases {
            XCTAssertNil(BackupCrypto.decrypt(encrypted, passphrase: passphrase))
        }
    }
}
