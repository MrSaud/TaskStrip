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
    @State private var signingInWithMicrosoft = false
    @State private var signingInWithGoogle = false
    @AppStorage(GoogleAuth.clientIDKey) private var googleClientID = ""
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
                                Text(account.signsInWithMicrosoft
                                     ? "Microsoft 365 · signed in"
                                     : account.signsInWithGoogle
                                         ? "\(account.host):\(account.port) · signed in with Google"
                                         : "\(account.host):\(account.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !account.signsInWithMicrosoft {
                                    // Where a message sent from this account goes out through.
                                    Text("sends via \(account.outgoingHost):\(account.outgoingPort)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
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
                Button {
                    Task { await signInWithMicrosoft() }
                } label: {
                    Label(
                        signingInWithMicrosoft ? "Signing in…" : "Sign in with Microsoft",
                        systemImage: "person.badge.key"
                    )
                }
                .disabled(signingInWithMicrosoft)
            } header: {
                Text("Exchange and Outlook")
            } footer: {
                Text("Microsoft no longer accepts a password over IMAP, so a work account signs in "
                     + "on Microsoft's own page and the app keeps only the token it hands back. "
                     + "If your organisation asks an administrator to approve the app, that "
                     + "happens once for everyone there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    Label(
                        signingInWithGoogle ? "Signing in…" : "Sign in with Google",
                        systemImage: "person.badge.key"
                    )
                }
                .disabled(signingInWithGoogle || googleClientID.isEmpty)
                TextField("Google client ID", text: $googleClientID)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Gmail")
            } footer: {
                Text("Signing in with Google means no app password to make or to keep — the "
                     + "password is typed on Google's own page and the app keeps only the token. "
                     + "Google gives each app its own client ID: make one for an iOS app in the "
                     + "Google Cloud console and paste it above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// Microsoft's own sign-in, in a sheet this app can't see inside. What comes back is a
    /// token, which goes to the keychain — there is no password here to keep or to lose.
    @MainActor
    private func signInWithMicrosoft() async {
        signingInWithMicrosoft = true
        problem = nil
        defer { signingInWithMicrosoft = false }
        do {
            let (tokens, address) = try await MicrosoftSignIn.shared.signIn()
            // Signing in again as somebody already here refreshes them rather than listing them
            // twice.
            let existing = accounts.first { $0.email.caseInsensitiveCompare(address) == .orderedSame }
            var account = existing ?? IMAPAccount.microsoft(email: address)
            account.provider = .microsoft
            await MicrosoftTokens.shared.save(tokens, for: account.id)
            store.save(account, password: "")
            accounts = store.accounts
            IMAPReader.shared.refresh(force: true)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Google's own sign-in. What comes back is a token that stands where a password stood, so
    /// nothing else about reading or sending this account changes.
    @MainActor
    private func signInWithGoogle() async {
        signingInWithGoogle = true
        problem = nil
        defer { signingInWithGoogle = false }
        do {
            let (tokens, address) = try await GoogleSignIn.shared.signIn()
            // Signing in as somebody already here refreshes them rather than listing them twice.
            let existing = accounts.first { $0.email.caseInsensitiveCompare(address) == .orderedSame }
            var account = existing ?? IMAPAccount.google(email: address)
            account.provider = .google
            await GoogleTokens.shared.save(tokens, for: account.id)
            store.save(account, password: "")
            accounts = store.accounts
            IMAPReader.shared.refresh(force: true)
        } catch {
            problem = error.localizedDescription
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
