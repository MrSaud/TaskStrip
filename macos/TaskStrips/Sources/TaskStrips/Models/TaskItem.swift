import Foundation
import SwiftData

// Phase 0 spike model: just enough to prove SwiftData persists across relaunches before the
// real schema (mirroring Android's TaskEntity) gets built in Phase 1.
@Model
final class TaskItem {
    var title: String
    var isDone: Bool
    var createdAt: Date

    init(title: String, isDone: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}
