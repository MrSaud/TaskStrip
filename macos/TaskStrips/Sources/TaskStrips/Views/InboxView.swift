import AppKit
import SwiftUI

/// The inbox, to glance at: who wrote, what about, and when. Clicking one opens it in Mail,
/// which is where it lives — this is a list beside the board, not a mail client.
///
/// Read from the servers, the same way the phone and iPad read it, so the three show the same
/// list. Mail's own accounts were easier — no password, and Exchange came free — but only the Mac
/// could ask, and an inbox that differs by device isn't much of an inbox.
struct InboxView: View {
    @ObservedObject private var server = IMAPReader.shared

    @AppStorage(AppSettingsKey.inboxAccount) private var account = ""
    @AppStorage(AppSettingsKey.inboxUnreadOnly) private var unreadOnly = false
    @State private var reading: MailMessage?
    @State private var composing: MailDraft?

    private var everything: [MailMessage] { server.messages }

    private var messages: [MailMessage] {
        MailInboxMerge.filtered(everything, account: account, unreadOnly: unreadOnly)
    }

    /// One line per account that wouldn't answer — the other seven still have a list.
    private var problem: String? { server.problem }

    var body: some View {
        VStack(spacing: 0) {
            header
            if messages.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(TaskStripTheme.bayBackground)
        .task { server.refresh() }
        .sheet(item: $composing) { draft in
            MailComposeView(draft: draft, accounts: server.accounts)
        }
        .sheet(item: $reading) { message in
            MailMessageView(message: message)
        }
        #if DEBUG
        // `-OpenNewestMessage`, for checking how big the reader actually opens without a hand on
        // the trackpad.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-OpenNewestMessage") else { return }
            for _ in 0..<20 {
                if let first = everything.first { reading = first; return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("INBOX", systemImage: "tray")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            // Whose inbox, when it isn't everyone's — otherwise a short list looks like lost mail.
            if !account.isEmpty {
                Text(account)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            // A refresh that failed while a list is up is worth a mark, not a page of apology.
            if let problem, !everything.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(TaskStripTheme.high)
                    .help(problem)
            }
            if let sender = server.accounts.first {
                Button {
                    composing = MailDraft(
                        from: sender.email, fromName: sender.senderName ?? "", to: "", subject: "", body: ""
                    )
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
                .help("Write a message")
            }
            InboxFilterMenu(
                accounts: MailInboxMerge.accounts(in: everything),
                account: $account,
                unreadOnly: $unreadOnly
            )
            if server.isReading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
                .help("Ask the servers again")
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
                        // Which account it landed in, while the list is showing all of them.
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
                    // Only where Mail has the account too — the link is a Mail link.
                    Button("Open in Mail") { open(message) }
                    Button("Copy Link") {
                        if let link = message.link { Platform.copy(link) }
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

    /// Nothing to show — which is a different sentence depending on whether there's no mail or
    /// just none that gets past the filter.
    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if !everything.isEmpty {
                Text(account.isEmpty ? "Nothing unread." : "Nothing from \(account).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Show everything") {
                    account = ""
                    unreadOnly = false
                }
                .buttonStyle(.link)
            } else if !server.hasAccounts {
                Text("No mail account yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Settings › Add an account reads your inbox here, and on your iPhone and iPad.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Text(problem ?? "Nothing in the inbox.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Button("Try again") { refresh() }
                    .buttonStyle(.link)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func refresh() { server.refresh(force: true) }

    private func open(_ message: MailMessage) {
        guard let link = message.link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
