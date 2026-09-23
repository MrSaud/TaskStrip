import AppKit
import SwiftUI

/// The inbox, to glance at: who wrote, what about, and when. Clicking one opens it in Mail,
/// which is where it lives — this is a list beside the board, not a mail client.
struct InboxView: View {
    @ObservedObject private var reader = MailReader.shared
    @ObservedObject private var server = IMAPReader.shared

    @AppStorage(AppSettingsKey.inboxAccount) private var account = ""
    @AppStorage(AppSettingsKey.inboxUnreadOnly) private var unreadOnly = false

    /// Both sources as one list. A Mac can have mail twice over — an account in Mail and the same
    /// one set up here over IMAP — so the two are merged and the duplicates dropped rather than
    /// one being preferred and the other hidden.
    private var everything: [MailMessage] {
        MailInboxMerge.merged([reader.messages, server.messages])
    }

    private var messages: [MailMessage] {
        MailInboxMerge.filtered(everything, account: account, unreadOnly: unreadOnly)
    }

    /// Both readers' complaints, since either half can fail while the other still has a list.
    private var problem: String? {
        let problems = [reader.problem, server.problem].compactMap { $0 }
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

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
        .task {
            reader.refresh()
            server.refresh()
        }
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
            InboxFilterMenu(
                accounts: MailInboxMerge.accounts(in: everything),
                account: $account,
                unreadOnly: $unreadOnly
            )
            if reader.isReading || server.isReading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Ask Mail and the servers again")
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
                    open(message)
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

    private func refresh() {
        reader.refresh(force: true)
        server.refresh(force: true)
    }

    private func open(_ message: MailMessage) {
        guard let link = message.link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
