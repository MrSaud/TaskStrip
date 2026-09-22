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
    /// Last edit, and optional purely so the store can migrate.
    ///
    /// SwiftData can give a new non-optional attribute a default only when the Swift initialiser
    /// is a literal it can encode into the model. `Date.now` is not one, so declaring this
    /// non-optional produced a mandatory attribute with no default and Core Data refused to
    /// migrate an existing store at all — "missing attribute values on mandatory destination
    /// attribute", which is a launch that fails rather than a field that misbehaves.
    ///
    /// Nil means "never edited since it was filed", which is what [lastEditedAt] reads it as.
    var updatedAt: Date?
    /// Tombstoned: deleted here, and kept only so the delete can reach the other device.
    ///
    /// Deliberately not called `isDeleted`. SwiftData's own PersistentModel already has one of
    /// those, meaning "removed from the context", and a stored property of that name shadows it —
    /// a #Predicate binds to ours while plain Swift `model.isDeleted` silently reads theirs. That
    /// split is invisible at the call site and was caught only by a test that fetched a tombstoned
    /// row and asked it whether it was gone. The name is the fix.
    var isTombstoned: Bool = false

    /// When this was last edited, falling back to when it was filed — a row
    /// nobody has touched is exactly as old as its filing.
    var lastEditedAt: Date { updatedAt ?? createdAt }
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
