import Foundation

/// A strip's steps, and what they say about how far along it is.
///
/// A strip has always had a progress bar you drag by hand. With steps on it, dragging would be
/// two answers to one question — so the steps win: tick three of five and the bar reads 60%.
/// A strip with no steps keeps the bar it always had.
enum StripChecklist {
    /// The progress the ticks add up to, or nil when there's nothing to count.
    static func progress(of items: [TaskChecklistItem]) -> Int? {
        guard !items.isEmpty else { return nil }
        let done = items.filter(\.isDone).count
        return Int((Double(done) / Double(items.count) * 100).rounded())
    }

    static func summary(of items: [TaskChecklistItem]) -> String? {
        guard !items.isEmpty else { return nil }
        return "\(items.filter(\.isDone).count)/\(items.count)"
    }

    /// Ticks or unticks one, stamping when it was done — the action log reads better for it, and
    /// a step ticked weeks ago shouldn't look like today's work.
    static func toggling(_ id: UUID, in items: [TaskChecklistItem], now: Date = .now) -> [TaskChecklistItem] {
        items.map { item in
            guard item.id == id else { return item }
            var toggled = item
            toggled.isDone.toggle()
            toggled.doneAt = toggled.isDone ? now : nil
            return toggled
        }
    }

    /// Text typed into the box, as steps: one per line, so a list pasted from anywhere arrives
    /// whole rather than as one long step.
    static func items(fromTyped text: String) -> [TaskChecklistItem] {
        text.split(separator: "\n")
            .map { line in
                // A pasted list usually brings its bullets and tick boxes with it.
                String(line.trimmingCharacters(in: .whitespaces).drop { "-•*[]()x✓ ".contains($0) })
            }
            .filter { !$0.isEmpty }
            .map { TaskChecklistItem(text: $0) }
    }
}
