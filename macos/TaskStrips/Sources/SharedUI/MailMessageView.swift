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
    @State private var snapshotProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        // Big enough to read in: a message is paragraphs, not a form. A sheet on a Mac takes its
        // width from the minimum rather than the ideal when its content stretches, which is why
        // the minimum is the size worth opening at. On an iPad it asks for the page-sized sheet
        // rather than the postcard a sheet gets by default.
        .frame(minWidth: 820, idealWidth: 960, minHeight: 520, idealHeight: 760)
        .background(TaskStripTheme.bayBackground)
        .pageSizedSheet()
        .task { await read() }
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
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                // Replying is Mail's job — this app doesn't send anything. The reply opens there
                // with the address and subject already filled in.
                if let reply = replyURL {
                    Button {
                        openURL(reply)
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.borderless)
                }
                if let text = loaded?.text, !text.isEmpty {
                    Button {
                        Platform.copy(text)
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
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
                    .buttonStyle(.borderless)
                    .help("Take a picture of this message and draw on it")
                }
                Spacer(minLength: 0)
                if loaded?.fromHTML == true {
                    Label("from the HTML version", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
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

    /// A reply Mail can open: the sender, and the subject with one Re: rather than two.
    private var replyURL: URL? {
        guard let address = message.senderAddress else { return nil }
        let subject = message.subject.lowercased().hasPrefix("re:") ? message.subject : "Re: \(message.subject)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url
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
    /// The largest sheet each platform offers. An iPad's default sheet is a form sheet about the
    /// size of a postcard, which is no way to read a message; iOS 18 can ask for a page-sized one
    /// and earlier versions get the full height instead.
    @ViewBuilder
    func pageSizedSheet() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            presentationDetents([.large])
        }
        #else
        self
        #endif
    }
}
