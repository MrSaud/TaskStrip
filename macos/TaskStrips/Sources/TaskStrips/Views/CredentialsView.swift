import AppKit
import SwiftData
import SwiftUI

/// Saved logins, mirroring ui/screens/CredentialsScreen.kt.
///
/// Passwords are never in the list — each is fetched from the keychain only when asked for, and
/// revealing or copying one takes a fresh Touch ID confirmation each time.
struct CredentialsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Credential.title) private var credentials: [Credential]

    @State private var search = ""
    @State private var editing: Credential?
    @State private var isCreating = false
    @State private var pendingDeletion: Credential?
    @State private var revealed: [UUID: String] = [:]
    @State private var problem: String?

    private var store: CredentialStore { .shared }

    private var visible: [Credential] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return credentials }
        return credentials.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.username.localizedCaseInsensitiveContains(trimmed)
                || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if credentials.isEmpty {
                empty
            } else {
                list
            }
        }
        .frame(minWidth: 540, minHeight: 500)
        .background(TaskStripTheme.bayBackground)
        .searchable(text: $search, placement: .toolbar, prompt: "Search credentials")
        .toolbar { toolbarContent }
        .sheet(isPresented: $isCreating) {
            CredentialEditView(credential: nil, password: "", onSave: insert, onCancel: { isCreating = false })
        }
        .sheet(item: $editing) { credential in
            CredentialEditView(
                credential: credential,
                password: store.password(for: credential.id) ?? "",
                onSave: { update(credential, with: $0) },
                onCancel: { editing = nil }
            )
        }
        .confirmationDialog(
            "Delete \"\(pendingDeletion?.title ?? "")\"?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let credential = pendingDeletion { delete(credential) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The saved password goes from the keychain too. This can't be undone.")
        }
        .alert("Keychain trouble", isPresented: Binding(
            get: { problem != nil },
            set: { if !$0 { problem = nil } }
        )) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
        // Nothing stays revealed behind a closed window.
        .onDisappear { revealed.removeAll() }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("NO CREDENTIALS YET")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Passwords are kept in your login keychain, never in the app's own store.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("New Credential") { isCreating = true }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            VStack {
                Spacer()
                Text("NOTHING MATCHES")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(visible) { credential in
                    row(for: credential)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for credential: Credential) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(credential.title)
                    .font(.headline)
                Spacer()
                Button { editing = credential } label: {
                    Label("Edit \(credential.title)", systemImage: "square.and.pencil")
                }
                Button(role: .destructive) { pendingDeletion = credential } label: {
                    Label("Delete \(credential.title)", systemImage: "trash")
                }
            }

            if !credential.username.isEmpty {
                HStack(spacing: 6) {
                    Text(credential.username)
                        .textSelection(.enabled)
                    Button { copy(credential.username) } label: {
                        Label("Copy username", systemImage: "doc.on.doc")
                    }
                    .help("Copy username")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(revealed[credential.id] ?? "••••••••")
                    .font(.body.monospaced())
                    .foregroundStyle(revealed[credential.id] != nil ? TaskStripTheme.amber : .secondary)
                if store.hasPassword(for: credential.id) {
                    Button { toggleReveal(credential) } label: {
                        Label(
                            revealed[credential.id] == nil ? "Reveal password" : "Hide password",
                            systemImage: revealed[credential.id] == nil ? "eye" : "eye.slash"
                        )
                    }
                    .help(revealed[credential.id] == nil ? "Reveal" : "Hide")
                    Button { copyPassword(credential) } label: {
                        Label("Copy password", systemImage: "doc.on.doc")
                    }
                    .help("Copy password")
                } else {
                    Text("no password saved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if !credential.url.isEmpty {
                Text(credential.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !credential.notes.isEmpty {
                Text(credential.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Edit…") { editing = credential }
            Divider()
            Button("Delete…", role: .destructive) { pendingDeletion = credential }
        }
    }

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem {
                Button { isCreating = true } label: {
                    Label("New credential", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    /// Hiding needs no permission; showing does. Asked every time rather than remembered, which
    /// is the point of asking.
    private func toggleReveal(_ credential: Credential) {
        if revealed[credential.id] != nil {
            revealed[credential.id] = nil
            return
        }
        Task {
            guard await LocalAuth.confirm(reason: "reveal the password for \(credential.title)") else { return }
            let password = store.password(for: credential.id)
            await MainActor.run { revealed[credential.id] = password }
        }
    }

    /// Copying is its own confirmation even when the password is already on screen — the
    /// clipboard is readable by everything else running, which looking at the screen is not.
    private func copyPassword(_ credential: Credential) {
        Task {
            guard await LocalAuth.confirm(reason: "copy the password for \(credential.title)") else { return }
            guard let password = store.password(for: credential.id) else { return }
            await MainActor.run { copy(password) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func insert(_ draft: CredentialDraft) {
        let credential = Credential(
            title: draft.title,
            username: draft.username,
            url: draft.url,
            notes: draft.notes
        )
        modelContext.insert(credential)
        savePassword(draft.password, for: credential)
        isCreating = false
    }

    private func update(_ credential: Credential, with draft: CredentialDraft) {
        credential.title = draft.title
        credential.username = draft.username
        credential.url = draft.url
        credential.notes = draft.notes
        savePassword(draft.password, for: credential)
        revealed[credential.id] = nil
        editing = nil
    }

    /// A password that silently failed to save would look identical to one that saved fine, right
    /// up until the day it's needed.
    private func savePassword(_ password: String, for credential: Credential) {
        if !store.setPassword(password, for: credential.id) {
            problem = "\"\(credential.title)\" was saved, but its password couldn't be written to "
                + "the keychain. Everything else about it is stored."
        }
    }

    private func delete(_ credential: Credential) {
        store.removePassword(for: credential.id)
        revealed[credential.id] = nil
        modelContext.delete(credential)
    }
}
