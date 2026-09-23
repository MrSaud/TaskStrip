import Foundation
import SwiftData

/// What the board does to a strip — mark it done, reopen it, archive it, delete it — shared by the
/// Mac's board window and the iPhone/iPad board so the two can't drift in the rules: a blocked
/// strip can't be finished, finishing a repeating one files the next, deleting one frees whatever
/// it was blocking and takes its files along.
enum StripActions {
    enum ToggleOutcome: Equatable {
        case completed
        case reopened
        /// Not changed: this strip waits on another that isn't done yet.
        case blocked(by: TaskItem)
    }

    static func blocker(for task: TaskItem, in all: [TaskItem]) -> TaskItem? {
        guard let id = task.blockedByID else { return nil }
        return all.first { $0.id == id }
    }

    /// The bottom of the board.
    static func nextOrderIndex(in all: [TaskItem]) -> Int {
        (all.map(\.orderIndex).max() ?? -1) + 1
    }

    /// Starts the clock on a strip, stopping whatever else was running.
    ///
    /// One strip at a time, deliberately: two clocks running is two people's worth of work, and
    /// the usual cause is forgetting to stop the first one.
    @discardableResult
    static func startTimer(on task: TaskItem, in all: [TaskItem], now: Date = .now) -> TaskItem? {
        let stopped = all.first { $0.id != task.id && StripTime.isRunning($0.sessions) }
        if let stopped { stopTimer(on: stopped, now: now) }
        task.sessions = StripTime.start(task.sessions, now: now)
        return stopped
    }

    static func stopTimer(on task: TaskItem, now: Date = .now) {
        guard let running = StripTime.running(in: task.sessions) else { return }
        let spent = now.timeIntervalSince(running.startedAt)
        task.sessions = StripTime.stop(task.sessions, now: now)
        // The log is where a strip's history lives, and an hour spent is history.
        if let entry = StripTime.logEntry(for: spent) {
            task.actionLog.append(TaskActionLogEntry(text: entry, timestamp: now))
        }
    }

    static func toggleTimer(on task: TaskItem, in all: [TaskItem], now: Date = .now) {
        if StripTime.isRunning(task.sessions) {
            stopTimer(on: task, now: now)
        } else {
            startTimer(on: task, in: all, now: now)
        }
    }

    @discardableResult
    static func toggleDone(
        _ task: TaskItem,
        in all: [TaskItem],
        context: ModelContext,
        scheduler: ReminderScheduler = .shared
    ) -> ToggleOutcome {
        if !task.isDone, let blocking = blocker(for: task, in: all), !blocking.isDone {
            return .blocked(by: blocking)
        }
        task.isDone.toggle()
        task.completedAt = task.isDone ? .now : nil
        // Finishing something is the end of working on it; leaving the clock running would log
        // the rest of the afternoon against it.
        if task.isDone { stopTimer(on: task) }

        // Completing a repeating strip spawns the next one rather than rolling this one forward,
        // so the finished occurrence stays as history — Android's choice, and the reason "what did
        // I finish last week" keeps working.
        if task.isDone, let next = ReminderPlan.nextOccurrence(completing: task, orderIndex: nextOrderIndex(in: all)) {
            context.insert(next)
            scheduler.schedule(for: next)
        }
        // Covers both directions: completing clears the pending reminder, reopening restores it.
        scheduler.schedule(for: task)
        return task.isDone ? .completed : .reopened
    }

    static func archive(_ task: TaskItem, scheduler: ReminderScheduler = .shared) {
        task.isArchived = true
        scheduler.schedule(for: task)
    }

    /// Back onto the board at the bottom. Renumbering only ever walks the strips on the board, so
    /// the orderIndex it held before being archived could put it anywhere mid-board.
    static func unarchive(_ task: TaskItem, in all: [TaskItem]) {
        task.orderIndex = nextOrderIndex(in: all)
        task.isArchived = false
    }

    static func delete(
        _ task: TaskItem,
        in all: [TaskItem],
        context: ModelContext,
        store: AttachmentStore = .shared,
        scheduler: ReminderScheduler = .shared
    ) {
        let id = task.id
        // The strip's files go with it — nothing else points at them, and leaving them behind
        // would grow the media folder forever.
        for attachment in task.attachments { store.remove(attachment) }
        scheduler.cancel(taskID: id)
        context.delete(task)
        releaseBlocked(by: id, in: all)
    }

    /// A strip that pointed at a deleted one as its blocker would otherwise stay blocked forever.
    static func releaseBlocked(by deletedID: UUID, in all: [TaskItem]) {
        for task in all where task.blockedByID == deletedID {
            task.blockedByID = nil
        }
    }
}
