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
    @State private var senderName = ""
    @State private var problem: String?
    @State private var isTesting = false
    @State private var editingSignature: IMAPAccount?
    /// What DNS said about the address being typed, once it has said it.
    @State private var provider: MailHost.Provider?
    @State private var lookingUp = false

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
                                // Where a message sent from this account goes out through.
                                Text("sends via \(account.outgoingHost):\(account.outgoingPort)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                if let signature = account.signature, !signature.isEmpty {
                                    Text("signature: \(signature.text.split(separator: "\n").first.map(String.init) ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                editingSignature = account
                            } label: {
                                Image(systemName: account.signature?.isEmpty == false
                                      ? "signature" : "square.and.pencil")
                            }
                            .buttonStyle(.plain)
                            .help("The signature on mail sent from this account")
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
                        guard host.isEmpty || host.hasPrefix("imap.") || host.hasSuffix("awsapps.com")
                            || host.hasSuffix("office365.com"),
                            let guess = IMAPHost.guess(for: address)
                        else { return }
                        // The guess by name goes in straight away so the field is never empty,
                        // and DNS replaces it a second later if it knows better.
                        host = guess.host
                        port = String(guess.port)
                        provider = nil
                        lookUp(address)
                    }
                SecureField("Password", text: $password)
                TextField("Your name (optional)", text: $senderName)
                TextField("Server", text: $host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Port", text: $port)

                if lookingUp {
                    Text("Looking up the server…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // What DNS found outranks what the address looks like: kfas.org.kw reads like a
                // company running its own mail and is in fact Microsoft's.
                if let note = provider?.note {
                    Label(note, systemImage: provider == .microsoft ? "exclamationmark.triangle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(provider == .microsoft ? TaskStripTheme.urgent : .secondary)
                } else if IMAPHost.refusesPasswords(email) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(TaskStripTheme.urgent)
                        if let advice = IMAPRefusal.advice(for: problem) {
                            Text(advice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(isTesting ? "Checking…" : "Add account") { add() }
                    .disabled(isTesting || email.isEmpty || password.isEmpty || host.isEmpty)
            } header: {
                Text("Add an account")
            } footer: {
                Text("The account and its password are kept in your iCloud keychain, like the other "
                     + "credentials — never in the app's own store or its backups — so adding it "
                     + "here adds it on your Mac, iPhone and iPad. Mail is read over TLS, headers "
                     + "only, and left unread. The same sign-in sends, through this provider's "
                     + "outgoing server, and a copy of anything sent goes to your Sent folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { accounts = store.accounts }
        .sheet(item: $editingSignature) { account in
            MailSignatureView(account: account) { signature in
                var edited = account
                edited.signature = signature.isEmpty ? nil : signature
                // Saved through the store so it reaches the phone and the iPad with the account.
                if let password = store.password(for: edited) {
                    store.save(edited, password: password)
                    accounts = store.accounts
                }
            }
        }
    }

    /// Asks DNS who runs this domain's mail. Slow answers are nobody's problem: the field is
    /// already filled with the guess, and a lookup for an address that's since been edited is
    /// dropped rather than overwriting what's there.
    private func lookUp(_ address: String) {
        lookingUp = true
        Task {
            let found = await MailHost.best(for: address)
            await MainActor.run {
                lookingUp = false
                guard email == address else { return }
                provider = found.provider
                if !found.host.isEmpty {
                    host = found.host
                    port = String(found.port)
                }
            }
        }
    }

    /// Signs in before saving: a wrong password is worth catching while the person is still
    /// looking at the field they typed it into.
    private func add() {
        let trimmedName = senderName.trimmingCharacters(in: .whitespaces)
        let account = IMAPAccount(
            email: email.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 993,
            senderName: trimmedName.isEmpty ? nil : trimmedName
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
                senderName = ""
                provider = nil
                IMAPReader.shared.refresh(force: true)
            }
        }
    }
}
