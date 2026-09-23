import SwiftUI

/// A message, opened.
///
/// The app fetches headers for the list and the text only when someone asks for it, which is the
/// difference between a pane that loads in two seconds and one that downloads everyone's mail.
/// Read-only, like the rest: BODY.PEEK, so opening a message here doesn't mark it read on the
/// server or on any other device.
struct MailMessageView: View {
    let message: MailMessage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var loaded: MailBody?
    @State private var problem: String?
    @State private var isReading = true
    @State private var markingUp: SketchOpening?
    @State private var replying: MailDraft?
    @State private var linkNote: String?
    @Environment(\.modelContext) private var context
    @State private var snapshotProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .readerSize()
        .background(TaskStripTheme.bayBackground)
        .task { await read() }
        .sheet(item: $replying) { draft in
            MailComposeView(draft: draft, accounts: IMAPReader.shared.accounts)
        }
        .canvasPresentation(item: $markingUp) { opening in
            NavigationStack {
                SketchCanvasView(
                    noteID: opening.id,
                    startingImage: opening.image,
                    startingName: opening.name
                )
            }
        }
        .alert(
            "Couldn't take a picture of this message",
            isPresented: Binding(get: { snapshotProblem != nil }, set: { if !$0 { snapshotProblem = nil } })
        ) {
            Button("OK", role: .cancel) { snapshotProblem = nil }
        } message: {
            Text(snapshotProblem ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.subject)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(message.sender)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(TaskStripTheme.amber.opacity(0.9))
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        if let account = message.account, !account.isEmpty {
                            Text("· \(account)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            // Buttons big enough to hit with a thumb: these are the things anyone actually does
            // with a message, and they were caption-sized text links.
            HStack(spacing: 10) {
                if message.senderAddress != nil {
                    Button {
                        replying = MailDraft.reply(
                            to: message,
                            from: sendingAccount?.email ?? "",
                            fromName: sendingAccount?.senderName ?? "",
                            body: loaded
                        )
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(sendingAccount == nil)
                    .help(sendingAccount == nil ? "Add a mail account to reply" : "Reply to this message")
                }
                if let text = loaded?.text, !text.isEmpty {
                    Button {
                        Platform.copy(text)
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                // A picture of the message, opened in the sketch canvas: highlight the line that
                // matters, ring the number that's wrong, and the marked-up page is a sketch note
                // like any other — which can go onto a strip.
                if loaded != nil {
                    Button {
                        markUp()
                    } label: {
                        Label("Mark Up", systemImage: "highlighter")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Take a picture of this message and draw on it")
                }
                // The message itself onto a strip, the way one dragged out of Mail lands there:
                // the strip keeps a link back to it, under its subject.
                if message.link != nil {
                    StripPickerMenu(title: "Link this email to a strip") { strip in
                        link(to: strip)
                    } label: {
                        Label("Link to Strip", systemImage: "link")
                            .font(.callout)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Keep a link to this message on a strip")
                }
                Spacer(minLength: 0)
                if let linkNote {
                    Text(linkNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if loaded?.fromHTML == true {
                    Label("from the HTML version", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
        }
        .padding(14)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    @ViewBuilder
    private var content: some View {
        if isReading {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text("Reading the message…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let problem {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(TaskStripTheme.high)
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Try again") { Task { await read(force: true) } }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(loaded?.text.isEmpty == false ? loaded!.text : "This message has no text — only attachments.")
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        // Mail is written in lines meant to be read, not to be stretched across
                        // a wide window; the text stops where reading gets uncomfortable.
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    if let loaded, !loaded.attachments.isEmpty || loaded.isTruncated {
                        MailAttachmentsView(
                            attachments: loaded.attachments,
                            isTruncated: loaded.isTruncated,
                            onFetchWholeMessage: { Task { await read(force: true, whole: true) } }
                        )
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }

    /// Files this message as a link on a strip, under its own subject — the same record the Mac
    /// writes when a message is dragged out of Mail onto a strip, so both routes leave the same
    /// thing behind.
    private func link(to strip: TaskItem) {
        guard let url = message.link else { return }
        guard !strip.links.contains(where: { $0.url == url }) else {
            linkNote = "Already on \(strip.title)."
            return
        }
        let label = message.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        strip.links.append(TaskLink(url: url, label: label))
        strip.actionLog.append(TaskActionLogEntry(text: "Linked an email", timestamp: .now))
        try? context.save()
        linkNote = "Linked to \(strip.title)."
    }

    /// The account a reply goes from: the one this message arrived on, so a reply to work mail
    /// comes from the work address rather than from whichever account happens to be first.
    private var sendingAccount: IMAPAccount? {
        let accounts = IMAPReader.shared.accounts
        if let id = message.accountID, let match = accounts.first(where: { $0.id == id }) { return match }
        return accounts.first
    }

    /// `whole` is the second, deliberate fetch: the reading is worth a couple of hundred
    /// kilobytes, and the files are worth the rest only when someone says so.
    /// Draws the message, then opens it in the sketch canvas as a new note named after it.
    @MainActor
    private func markUp() {
        guard let image = MailSnapshot.image(of: message, body: loaded) else {
            snapshotProblem = "The message couldn't be drawn as a picture."
            return
        }
        markingUp = SketchOpening(
            id: SketchStore.newNoteID(),
            image: image,
            name: message.subject.isEmpty ? "Email" : String(message.subject.prefix(60))
        )
    }

    private func read(force: Bool = false, whole: Bool = false) async {
        if !force, loaded != nil { return }
        isReading = true
        problem = nil
        let limit = whole ? MailBodyParser.wholeMessageLimit : MailBodyParser.byteLimit
        switch await IMAPReader.shared.body(for: message, limit: limit) {
        case .success(let read):
            loaded = read
        case .failure(let failure):
            problem = failure
        }
        isReading = false
    }
}


/// A sketch about to be opened: the note it will be written to, and the picture it starts with.
struct SketchOpening: Identifiable {
    let id: String
    let image: CGImage
    let name: String
}

extension View {
    /// How big the reader opens.
    ///
    /// On a Mac it's a sheet, and a sheet takes its width from the minimum rather than the ideal
    /// once its content stretches — so the minimum is the size worth opening at. On an iPhone and
    /// an iPad it's presented full screen and takes the screen, and a minimum width meant for a
    /// Mac window would push the text off the side of a phone.
    @ViewBuilder
    func readerSize() -> some View {
        #if os(macOS)
        frame(minWidth: 820, idealWidth: 960, minHeight: 520, idealHeight: 760)
        #else
        self
        #endif
    }
}
