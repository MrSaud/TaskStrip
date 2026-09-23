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
    @State private var cc: String
    /// Hidden until there's something in it or somebody asks for it: most messages go to one
    /// person, and an empty field is one more thing to read past.
    @State private var showsCc: Bool
    @State private var subject: String
    @State private var text: String
    @State private var accountID: UUID?
    @State private var isSending = false
    @State private var problem: String?
    @State private var confirming = false
    @State private var sentNote: String?
    /// Which field the suggestions belong to, so they appear under the one being typed in.
    @State private var typingIn: Field?

    private enum Field { case to, cc }

    init(draft: MailDraft, accounts: [IMAPAccount]) {
        self.draft = draft
        self.accounts = accounts
        _to = State(initialValue: draft.to)
        _cc = State(initialValue: draft.cc)
        _showsCc = State(initialValue: !draft.cc.isEmpty)
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
            cc: showsCc ? cc : "",
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
            Button(sendButtonTitle) {
                Task { await send() }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(confirmationDetail)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(draft.inReplyTo == nil ? "NEW MESSAGE" : "REPLY")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
            if isSending {
                ProgressView().controlSize(.small)
            } else {
                Button("Send") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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

            HStack {
                TextField("To", text: $to)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .onChange(of: to) { _, _ in typingIn = .to }
                if !showsCc {
                    Button("Cc") { showsCc = true }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }
            if typingIn == .to { suggestions(for: $to) }

            if showsCc {
                TextField("Cc", text: $cc)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .onChange(of: cc) { _, _ in typingIn = .cc }
                if typingIn == .cc { suggestions(for: $cc) }
            }
            if !readyDraft.isSendable, !to.isEmpty {
                Text("One of those isn't an email address yet. Separate several with commas.")
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

    /// The people worth offering for what's half-typed in this field: the ones already written
    /// to, colleagues in the same organisation first.
    @ViewBuilder
    private func suggestions(for field: Binding<String>) -> some View {
        let typed = MailDirectory.partial(in: field.wrappedValue)
        let already = readyDraft.recipients
        let found = IMAPReader.shared.suggestions(for: typed, from: account, excluding: already)
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(found) { contact in
                    Button {
                        field.wrappedValue = MailDirectory.completing(field.wrappedValue, with: contact.address)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(TaskStripTheme.amber.opacity(0.8))
                            Text(contact.display)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
        }
    }

    /// Says how many people this is about to reach, because "Send" under a Cc line of six is
    /// worth a second look.
    private var sendButtonTitle: String {
        let recipients = readyDraft.recipients
        guard recipients.count > 1 else {
            return "Send to \(recipients.first ?? to.trimmingCharacters(in: .whitespaces))"
        }
        return "Send to \(recipients.count) people"
    }

    private var confirmationDetail: String {
        let recipients = readyDraft.recipients
        let who = recipients.count > 3
            ? recipients.prefix(3).joined(separator: ", ") + " and \(recipients.count - 3) more"
            : recipients.joined(separator: ", ")
        return "To \(who), from \(account?.email ?? "—"). Once it's gone it can't be taken back."
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
