import Foundation
import SwiftData

/// A saved login, mirroring CredentialEntity.kt — with one deliberate difference: the password
/// isn't here.
///
/// Android keeps an `encryptedPassword` column, encrypted under a Keystore key. The Mac's
/// equivalent of that key store is the Keychain, which holds the secret itself rather than a key
/// to decrypt a column with, so the password lives there under this credential's id and never
/// touches the SwiftData store. See CredentialStore.
@Model
final class Credential: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var username: String
    var url: String
    var notes: String
    var createdAt: Date

    init(
        title: String,
        username: String = "",
        url: String = "",
        notes: String = "",
        id: UUID = UUID(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.username = username
        self.url = url
        self.notes = notes
        self.createdAt = createdAt
    }
}
