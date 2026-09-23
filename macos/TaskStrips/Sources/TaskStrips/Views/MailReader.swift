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
    private let cache = MailInboxCache()

    private init() {
        // What it last saw, so the pane opens with something rather than a spinner.
        messages = cache.messages
    }

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
                    // Merged with itself, which is how the duplicate from a mailbox short enough
                    // to be both its own head and tail gets dropped.
                    let read = MailInboxMerge.merged([MailInbox.parse(text)])
                    if !read.isEmpty {
                        messages = read
                        cache.messages = read
                    }
                    problem = messages.isEmpty ? "Nothing in the inbox." : nil
                case .failure(let message):
                    // A list already on screen beats an apology: the failure is only shown when
                    // there's nothing to show instead.
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
    /// Account by account rather than through the unified inbox. The unified inbox lists each
    /// account's messages one after another, so any slice of it is one account's mail: asking for
    /// its last eight returned eight messages from the same address, and the newest mail in every
    /// other account was invisible. Asked per account, ten seconds buys a few from each — which is
    /// what "recent" has to mean on a Mac with eight accounts in it.
    ///
    /// Both ends of each mailbox are taken because Mail's message order is its own business: the
    /// unified inbox holds the newest last, an account's own INBOX holds them first, and a mailbox
    /// re-sorted by hand holds them wherever it likes. Dates decide afterwards, and the duplicate
    /// a short mailbox produces by being both ends at once is dropped by Message-ID.
    ///
    /// Everything is wrapped in a timeout: Mail downloading mail is Mail that doesn't answer, and
    /// a pane that spins forever is worse than one that says so.
    private static let script = """
    set epoch to date "Thursday, 1 January 1970 at 00:00:00"

    -- The five properties are read from a range in one request each rather than message by
    -- message, which is the difference between a second and a timeout. The range is asked for
    -- five times rather than held in a variable: a variable holds a list of references, and Mail
    -- won't read a property off one of those ("Can't get message id of {message id 43742 of
    -- mailbox…}").
    on slice(box, startAt, endAt, accountName, epoch)
        set output to ""
        tell application "Mail"
            set theIDs to message id of (messages startAt thru endAt of box)
            set theSubjects to subject of (messages startAt thru endAt of box)
            set theSenders to sender of (messages startAt thru endAt of box)
            set theDates to date received of (messages startAt thru endAt of box)
            set theReads to read status of (messages startAt thru endAt of box)
        end tell
        repeat with i from 1 to (count of theIDs)
            set output to output & (item i of theIDs) & tab & (item i of theSubjects) & tab & ¬
                (item i of theSenders) & tab & (((item i of theDates) - epoch) as string) & tab & ¬
                (item i of theReads) & tab & accountName & linefeed
        end repeat
        return output
    end slice

    with timeout of \(Int(scriptTimeout)) seconds
        set output to ""
        tell application "Mail" to set theAccounts to every account
        repeat with a in theAccounts
            -- One account's failure is not the list's: a server that's down shouldn't empty the
            -- pane of the seven accounts that are fine.
            try
                tell application "Mail"
                    set isOn to enabled of a
                    set accountName to name of a
                    -- "is" ignores case, which matters: Exchange calls it Inbox and everyone
                    -- else calls it INBOX.
                    set box to first mailbox of a whose name is "Inbox"
                    set total to count of messages of box
                end tell
                if isOn and total > 0 then
                    set headEnd to \(MailInbox.perAccount)
                    if total < headEnd then set headEnd to total
                    set output to output & my slice(box, 1, headEnd, accountName, epoch)
                    set tailStart to total - (\(MailInbox.perAccount) - 1)
                    if tailStart < 1 then set tailStart to 1
                    if tailStart > headEnd then
                        set output to output & my slice(box, tailStart, total, accountName, epoch)
                    end if
                end if
            end try
        end repeat
        return output
    end timeout
    """

    /// What Mail is given to answer in, and a little longer before the process is pulled out from
    /// under it.
    /// Generous, because Mail's mood decides this rather than the size of the question: the same
    /// request for a dozen messages answered in five seconds once and not at all in thirty the
    /// next time. Nobody waits on it — the pane is already showing the last list.
    private static let scriptTimeout: TimeInterval = 90
    private static let processTimeout: TimeInterval = 100

    /// What to ask when Mail can't manage the proper question: five messages by index of the
    /// unified inbox, no account walk and no count of a mailbox with thirty thousand in it. They
    /// may be one account's oldest rather than everyone's newest — the list sorts what it gets —
    /// but something beats a pane of apology.
    private static let fallbackScript = """
    with timeout of \(Int(scriptTimeout)) seconds
        tell application "Mail"
            set box to inbox
            set output to ""
            repeat with i from 1 to 5
                try
                    set m to message i of box
                    set output to output & (message id of m) & tab & (subject of m) & tab & ¬
                        (sender of m) & tab & (((date received of m) - (date "Thursday, 1 January 1970 at 00:00:00")) as string) & tab & ¬
                        (read status of m) & tab & (name of account of mailbox of m) & linefeed
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
