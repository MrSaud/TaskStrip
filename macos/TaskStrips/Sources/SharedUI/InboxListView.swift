import SwiftUI

/// The inbox as the phone and iPad see it: read from the mail server itself, since iOS gives an
/// app no way to ask Mail anything.
///
/// The same list the Mac's pane shows, from a different source — which is why the row is shared
/// and only the reading differs.
struct InboxListView: View {
    var showsHeader = true
    @ObservedObject private var reader = IMAPReader.shared
    @Environment(\.openURL) private var openURL

    @AppStorage(AppSettingsKey.inboxAccount) private var account = ""
    @AppStorage(AppSettingsKey.inboxUnreadOnly) private var unreadOnly = false
    @State private var reading: MailMessage?
    @State private var composing: MailDraft?

    /// The same narrowing the Mac's pane does, over the same list — the phone simply has one
    /// source feeding it rather than two.
    private var messages: [MailMessage] {
        MailInboxMerge.filtered(reader.messages, account: account, unreadOnly: unreadOnly)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            if messages.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(TaskStripTheme.bayBackground)
        .task { reader.refresh() }
        // Full screen rather than a sheet: on an iPad a sheet is a card in the middle of the
        // screen, which is a poor way to read a message and a worse one to mark one up. The
        // reader has its own Done button, so nothing is lost by taking the whole screen.
        .sheet(item: $composing) { draft in
            MailComposeView(draft: draft, accounts: reader.accounts)
        }
        .canvasPresentation(item: $reading) { message in
            MailMessageView(message: message)
        }
        #if DEBUG
        // `-OpenNewestMessage`, for checking how big the reader opens on a device or a simulator.
        // With no account set up it opens on a made-up message, which still sizes the sheet.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-OpenNewestMessage") else { return }
            for _ in 0..<15 {
                if let first = reader.messages.first { reading = first; return }
                try? await Task.sleep(for: .seconds(1))
            }
            reading = MailMessage(
                id: "sample", subject: "A message, for measuring the window",
                sender: "Someone <someone@example.com>", receivedAt: .now, isRead: false
            )
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("INBOX", systemImage: "tray")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            if !account.isEmpty {
                Text(account)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if reader.problem != nil, !reader.messages.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(TaskStripTheme.high)
            }
            if let sender = reader.accounts.first {
                Button {
                    composing = MailDraft(
                        from: sender.email, fromName: sender.senderName ?? "", to: "", subject: "", body: ""
                    )
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write a message")
            }
            InboxFilterMenu(
                accounts: MailInboxMerge.accounts(in: reader.messages),
                account: $account,
                unreadOnly: $unreadOnly
            )
            if reader.isReading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    reader.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private var list: some View {
        List {
            ForEach(messages) { message in
                Button {
                    reading = message
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if !message.isRead {
                                Circle()
                                    .fill(TaskStripTheme.amber)
                                    .frame(width: 6, height: 6)
                            }
                            Text(message.senderName)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(TaskStripTheme.amber.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text(message.subject)
                            .lineLimit(2)
                            .fontWeight(message.isRead ? .regular : .semibold)
                        if account.isEmpty, let name = message.account, !name.isEmpty {
                            Text(name)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button("Read") { reading = message }
                    Button("Copy Subject") { Platform.copy(message.subject) }
                    if let link = message.link {
                        Button("Copy Link") { Platform.copy(link) }
                    }
                    if let name = message.account, !name.isEmpty, name != account {
                        Divider()
                        Button("Show Only \(name)") { account = name }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if !reader.messages.isEmpty {
                Text(account.isEmpty ? "Nothing unread." : "Nothing from \(account).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Show everything") {
                    account = ""
                    unreadOnly = false
                }
                .buttonStyle(.borderless)
            } else if !reader.hasAccounts {
                Text("No mail account yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Settings › Add an account reads your inbox here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else if let problem = reader.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Button("Try again") { reader.refresh(force: true) }
                    .buttonStyle(.borderless)
            } else if reader.isReading {
                Text("Reading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}
