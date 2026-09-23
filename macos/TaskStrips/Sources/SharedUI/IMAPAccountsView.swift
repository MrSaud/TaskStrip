import SwiftUI

/// Setting up an account the app reads mail from.
///
/// The password is typed once and goes straight to the iCloud keychain — never into the app's
/// store, a backup, or iCloud's own database — so it's set up once for every device.
struct IMAPAccountsView: View {
    @State private var accounts: [IMAPAccount] = []
    @State private var email = ""
    @State private var password = ""
    @State private var host = ""
    @State private var port = "993"
    @State private var problem: String?
    @State private var isTesting = false

    private let store = IMAPAccountStore()

    var body: some View {
        Group {
            if !accounts.isEmpty {
                Section("Mail accounts") {
                    ForEach(accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.email)
                                Text("\(account.host):\(account.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                store.remove(account)
                                accounts = store.accounts
                                IMAPReader.shared.refresh(force: true)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: email) { _, address in
                        guard host.isEmpty || host.hasPrefix("imap."), let guess = IMAPHost.guess(for: address) else {
                            return
                        }
                        host = guess.host
                        port = String(guess.port)
                    }
                SecureField("Password", text: $password)
                TextField("Server", text: $host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Port", text: $port)

                if IMAPHost.refusesPasswords(email) {
                    Label(
                        "Microsoft doesn't allow a password here — Outlook and Hotmail need OAuth, "
                            + "which this app doesn't do yet.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(TaskStripTheme.urgent)
                } else if IMAPHost.wantsAppPassword(email) {
                    Text("This provider wants an app-specific password rather than your own — "
                         + "make one in your account's security settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(TaskStripTheme.urgent)
                }

                Button(isTesting ? "Checking…" : "Add account") { add() }
                    .disabled(isTesting || email.isEmpty || password.isEmpty || host.isEmpty)
            } header: {
                Text("Add an account")
            } footer: {
                Text("The password is kept in your iCloud keychain, like the other credentials — "
                     + "never in the app's own store or its backups. Mail is read over TLS, headers "
                     + "only, and left unread.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { accounts = store.accounts }
    }

    /// Signs in before saving: a wrong password is worth catching while the person is still
    /// looking at the field they typed it into.
    private func add() {
        let account = IMAPAccount(
            email: email.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 993
        )
        isTesting = true
        problem = nil
        Task {
            let failure = await IMAPReader.test(account, password: password)
            await MainActor.run {
                isTesting = false
                if let failure {
                    problem = failure
                    return
                }
                guard store.save(account, password: password) else {
                    problem = "Couldn't save the password to the keychain."
                    return
                }
                accounts = store.accounts
                email = ""
                password = ""
                host = ""
                port = "993"
                IMAPReader.shared.refresh(force: true)
            }
        }
    }
}
