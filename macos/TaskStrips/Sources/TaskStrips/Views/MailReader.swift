import Foundation

/// Asks Mail what's in the inbox.
///
/// Through Mail itself rather than through a mail server: no account to set up, no password to
/// keep, and whatever accounts Mail already has — iCloud, Gmail, Exchange — are simply there. The
/// price is a one-time permission to control Mail, which macOS asks for the first time this runs.
///
/// Read-only, deliberately: it asks for a list and opens a message in Mail. Nothing here marks,
/// moves, deletes or sends anything.
@MainActor
final class MailReader: ObservableObject {
    static let shared = MailReader()

    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var problem: String?
    @Published private(set) var isReading = false
    private var lastRead: Date?

    /// Mail is asked at most this often; the pane may ask whenever it likes.
    static let freshFor: TimeInterval = 5 * 60

    func refresh(now: Date = .now, force: Bool = false) {
        if !force, let lastRead, now.timeIntervalSince(lastRead) < Self.freshFor { return }
        guard !isReading else { return }
        isReading = true
        lastRead = now

        Task {
            // The quick, correct question first; if Mail is too busy to answer it, the cheap one
            // that asks for a handful by index — which a busy Mail can sometimes still manage.
            var outcome = await Self.ask(Self.script)
            if case .failure(let problem) = outcome, problem.contains("too busy") {
                outcome = await Self.ask(Self.fallbackScript)
            }
            await MainActor.run {
                isReading = false
                switch outcome {
                case .success(let text):
                    messages = MailInbox.newest(MailInbox.parse(text))
                    problem = messages.isEmpty ? "Nothing in the inbox." : nil
                case .failure(let message):
                    problem = message
                }
            }
        }
    }

    private enum Outcome {
        case success(String)
        case failure(String)
    }

    /// The whole conversation with Mail, in one script.
    ///
    /// The newest are at the *end* of the unified inbox, not the start: it lists each account's
    /// inbox one after another, so its first messages are the oldest of the first account — on a
    /// real inbox the first one it offered was from 2014. So the last stretch is taken, and the
    /// five properties are read from that slice in one request each rather than message by
    /// message, which is the difference between a second and a timeout.
    ///
    /// Everything is wrapped in a timeout: Mail downloading mail is Mail that doesn't answer, and
    /// a pane that spins forever is worse than one that says so.
    private static let script = """
    with timeout of \(Int(scriptTimeout)) seconds
        tell application "Mail"
            set box to inbox
            set total to count of messages of box
            if total is 0 then return ""
            set startAt to total - \(MailInbox.askFor - 1)
            if startAt < 1 then set startAt to 1
            -- The range is asked for five times rather than held in a variable: a variable holds
            -- a list of references, and Mail won't read a property off one of those ("Can't get
            -- message id of {message id 43742 of mailbox…}"). Asked as a range it answers with a
            -- list of values, which is the whole point of asking in bulk.
            set theIDs to message id of (messages startAt thru total of box)
            set theSubjects to subject of (messages startAt thru total of box)
            set theSenders to sender of (messages startAt thru total of box)
            set theDates to date received of (messages startAt thru total of box)
            set theReads to read status of (messages startAt thru total of box)
        end tell
    end timeout

    set epoch to date "Thursday, 1 January 1970 at 00:00:00"
    set output to ""
    repeat with i from 1 to (count of theIDs)
        set output to output & (item i of theIDs) & tab & (item i of theSubjects) & tab & ¬
            (item i of theSenders) & tab & (((item i of theDates) - epoch) as string) & tab & ¬
            (item i of theReads) & linefeed
    end repeat
    return output
    """

    /// What Mail is given to answer in, and a little longer before the process is pulled out from
    /// under it.
    private static let scriptTimeout: TimeInterval = 20
    private static let processTimeout: TimeInterval = 30

    /// What to ask when Mail can't manage the proper question: a few messages by index, no count
    /// of a mailbox with thousands in it. They may be the oldest Mail holds rather than the
    /// newest — the list sorts what it gets — but something beats a pane of apology.
    private static let fallbackScript = """
    with timeout of \(Int(scriptTimeout)) seconds
        tell application "Mail"
            set box to inbox
            set output to ""
            repeat with i from 1 to \(MailInbox.count)
                try
                    set m to message i of box
                    set output to output & (message id of m) & tab & (subject of m) & tab & ¬
                        (sender of m) & tab & (((date received of m) - (date "Thursday, 1 January 1970 at 00:00:00")) as string) & tab & ¬
                        (read status of m) & linefeed
                end try
            end repeat
            return output
        end tell
    end timeout
    """

    private static func ask(_ script: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]
                let output = Pipe()
                let errors = Pipe()
                task.standardOutput = output
                task.standardError = errors

                do {
                    try task.run()
                } catch {
                    continuation.resume(returning: .failure("Couldn't ask Mail: \(error.localizedDescription)"))
                    return
                }
                // Mail can be too busy to answer at all — downloading, reindexing — and a child
                // process waiting on it would hang this for as long as that lasts.
                let deadline = DispatchWorkItem { if task.isRunning { task.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + processTimeout, execute: deadline)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let problem = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                task.waitUntilExit()
                deadline.cancel()

                guard task.terminationStatus == 0 else {
                    // The one failure worth explaining: macOS asks once, and a no is remembered.
                    let refused = problem.contains("-1743") || problem.lowercased().contains("not authorized")
                    let busy = problem.contains("-1712") || problem.lowercased().contains("timed out")
                    let message: String
                    if refused {
                        message = "Task Strips isn't allowed to read Mail. System Settings › Privacy & Security › Automation can change that."
                    } else if busy {
                        message = "Mail is too busy to answer — it's often downloading. Try again in a moment."
                    } else {
                        // Whatever else went wrong, say what Mail actually said: an integration
                        // that fails with a shrug is one nobody can fix.
                        let reason = problem
                            .split(separator: "\n")
                            .last
                            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                        // Trimmed: AppleScript errors can carry a list of every message it
                        // stumbled over, and a pane is not a log.
                        let short = reason.count > 160 ? String(reason.prefix(160)) + "…" : reason
                        message = short.isEmpty ? "Mail didn't answer. Is it running?" : "Mail said: \(short)"
                    }
                    continuation.resume(returning: .failure(message))
                    return
                }
                continuation.resume(returning: .success(String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }
}
