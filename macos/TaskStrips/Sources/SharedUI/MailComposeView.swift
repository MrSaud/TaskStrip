import SwiftUI

/// Writing a message, and sending it.
///
/// The first screen in this app that acts outward: everything else reads and changes nothing.
/// So nothing leaves on a single tap — Send asks first, and says exactly who it's about to go to,
/// because the cost of a mistake here is a message in somebody else's inbox.
struct MailComposeView: View {
    /// Prefilled for a reply; empty for a new message.
    var draft: MailDraft
    /// Which account it goes from. The first one unless someone picks another.
    var accounts: [IMAPAccount]

    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    @State private var subject: String
    @State private var text: String
    @State private var accountID: UUID?
    @State private var isSending = false
    @State private var problem: String?
    @State private var confirming = false
    @State private var sentNote: String?

    init(draft: MailDraft, accounts: [IMAPAccount]) {
        self.draft = draft
        self.accounts = accounts
        _to = State(initialValue: draft.to)
        _subject = State(initialValue: draft.subject)
        _text = State(initialValue: draft.body)
        _accountID = State(initialValue: accounts.first { $0.email == draft.from }?.id ?? accounts.first?.id)
    }

    private var account: IMAPAccount? {
        accounts.first { $0.id == accountID } ?? accounts.first
    }

    private var readyDraft: MailDraft {
        MailDraft(
            from: account?.email ?? "",
            fromName: account?.senderName ?? "",
            to: to,
            subject: subject,
            body: text,
            inReplyTo: draft.inReplyTo
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fields
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(TaskStripTheme.bayBackground)
        .confirmationDialog(
            "Send this message?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Send to \(to.trimmingCharacters(in: .whitespaces))") {
                Task { await send() }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("From \(account?.email ?? "—"). Once it's gone it can't be taken back.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(draft.inReplyTo == nil ? "NEW MESSAGE" : "REPLY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
            if isSending {
                ProgressView().controlSize(.small)
            } else {
                Button("Send") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!readyDraft.isSendable || account == nil)
            }
        }
        .padding(14)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private var fields: some View {
        Form {
            if accounts.count > 1 {
                Picker("From", selection: Binding(get: { accountID }, set: { accountID = $0 })) {
                    ForEach(accounts) { account in
                        Text(account.email).tag(Optional(account.id))
                    }
                }
            } else if let account {
                LabeledContent("From", value: account.email)
            }

            TextField("To", text: $to)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
            if !to.isEmpty, !MailDraft.looksLikeAnAddress(to) {
                Text("That doesn't look like an email address yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Subject", text: $subject)

            Section("Message") {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .font(.body)
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(TaskStripTheme.urgent)
            }
            if let sentNote {
                Text(sentNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func send() async {
        guard let account else { return }
        isSending = true
        problem = nil
        sentNote = nil
        switch await IMAPReader.shared.send(readyDraft, from: account) {
        case .sent(let mailbox):
            // Said plainly, because a copy in Sent is what makes the message exist on the Mac
            // and the iPad too — and some accounts have nowhere to put it.
            sentNote = mailbox.map { "Sent, and filed in \($0)." } ?? "Sent. This account has no Sent folder to file a copy in."
            isSending = false
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        case .filingFailed(let detail):
            isSending = false
            problem = "Sent — but the copy for your Sent folder didn't go in: \(detail)"
        case .failed(let detail):
            isSending = false
            problem = detail
        }
    }
}
