import Foundation
import SwiftData

/// A stray thought, jotted with no friction — no title, no priority, no due date.
///
/// Mirrors NoteEntity.kt, which is as small as it looks: text and when it was written. The point
/// is that capturing something costs nothing; it becomes a strip only once it's actually
/// actionable, which is what NotePromotion is for.
@Model
final class Note: Identifiable {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    init(text: String, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
