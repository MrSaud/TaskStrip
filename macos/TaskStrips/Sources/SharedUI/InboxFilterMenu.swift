import SwiftUI

/// Which of the merged inbox to show: one account or all of them, everything or only what hasn't
/// been read.
///
/// The same menu on both platforms, because the list underneath is the same list — a Mac merges
/// Mail's accounts with the app's own, a phone has only the app's, and neither wants a different
/// way of narrowing it.
struct InboxFilterMenu: View {
    /// The accounts present in the list, from `MailInboxMerge.accounts(in:)`.
    let accounts: [String]
    /// Empty means all of them.
    @Binding var account: String
    @Binding var unreadOnly: Bool

    var body: some View {
        Menu {
            Toggle(isOn: $unreadOnly) {
                Label("Unread only", systemImage: "circle.fill")
            }

            if accounts.count > 1 {
                Section("Account") {
                    Picker("Account", selection: $account) {
                        Text("All accounts").tag("")
                        ForEach(accounts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }

            if isNarrowed {
                Section {
                    Button {
                        account = ""
                        unreadOnly = false
                    } label: {
                        Label("Show everything", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Image(systemName: isNarrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(isNarrowed ? "Showing part of the inbox" : "Filter the inbox")
        .accessibilityLabel("Filter the inbox")
        .accessibilityValue(isNarrowed ? (account.isEmpty ? "unread only" : account) : "everything")
    }

    private var isNarrowed: Bool { !account.isEmpty || unreadOnly }
}
