import AppKit
import SwiftUI

/// The inbox, to glance at: who wrote, what about, and when. Clicking one opens it in Mail,
/// which is where it lives — this is a list beside the board, not a mail client.
struct InboxView: View {
    @ObservedObject private var reader = MailReader.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            if let problem = reader.problem, reader.messages.isEmpty {
                empty(problem)
            } else {
                list
            }
        }
        .background(TaskStripTheme.bayBackground)
        .task { reader.refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("INBOX", systemImage: "tray")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            Spacer(minLength: 0)
            if reader.isReading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    reader.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Ask Mail again")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private var list: some View {
        List {
            ForEach(reader.messages) { message in
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
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func empty(_ problem: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(problem)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Try again") { reader.refresh(force: true) }
                .buttonStyle(.link)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func open(_ message: MailMessage) {
        guard let link = message.link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
