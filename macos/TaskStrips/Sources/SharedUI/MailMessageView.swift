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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 380, minHeight: 420)
        .background(TaskStripTheme.bayBackground)
        .task { await read() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.subject)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(message.sender)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(TaskStripTheme.amber.opacity(0.9))
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        if let account = message.account, !account.isEmpty {
                            Text("· \(account)")
                        }
                    }
                    .font(.caption2)
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(loaded?.text.isEmpty == false ? loaded!.text : "This message has no text — only attachments.")
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if loaded?.isTruncated == true {
                        Text("Only the first part of a long message is fetched.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
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

    private func read(force: Bool = false) async {
        if !force, loaded != nil { return }
        isReading = true
        problem = nil
        switch await IMAPReader.shared.body(for: message) {
        case .success(let read):
            loaded = read
        case .failure(let failure):
            problem = failure
        }
        isReading = false
    }
}
