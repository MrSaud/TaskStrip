import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Back up and restore on iPhone and iPad, through the Files app — the same backup file the Mac
/// and Android write, with the same passphrase for passwords, and the same sheets. Only where the
/// file goes differs: the Mac asks with a save panel; here the Files picker does.
struct BoardBackup: ViewModifier {
    @Binding var isBackingUp: Bool
    @Binding var isRestoring: Bool

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { !$0.isTombstoned }) private var tasks: [TaskItem]
    @Query private var notes: [Note]
    @Query(filter: #Predicate<StorageItem> { !$0.isTombstoned }) private var storageItems: [StorageItem]
    @Query(filter: #Predicate<Reminder> { !$0.isTombstoned }) private var reminders: [Reminder]
    @Query(filter: #Predicate<Credential> { !$0.isTombstoned }) private var credentials: [Credential]

    @State private var progress: BackupProgress?
    @State private var written: WrittenBackup?
    @State private var isSaving = false
    @State private var summary: BackupImportSummary?
    @State private var message: ImportMessage?

    // iOS drops a sheet asked for while another is still closing, without a word — which is
    // how the first version of this lost its Files picker. So each step waits for the sheet
    // before it to be gone (its onDismiss) and only then starts, holding what it needs here.
    @State private var pendingPassphrase: String?
    @State private var pendingRestore: (summary: BackupImportSummary, mode: ImportMode, passphrase: String)?
    @State private var afterProgress: AfterProgress?
    /// Whether the progress sheet actually came up. A step fast enough to finish before it did
    /// gets no onDismiss, so the next step is started directly instead.
    @State private var progressShown = false

    private enum AfterProgress {
        case save(WrittenBackup)
        case report(ImportMessage)
    }

    /// A finished archive waiting for the Files picker to say where it goes.
    private struct WrittenBackup {
        let document: BackupDocument
        let result: BackupExport.Result
        let strips: Int
    }

    private var contents: BackupExport.Contents {
        BackupExport.Contents(
            tasks: tasks, notes: notes, storageItems: storageItems, reminders: reminders, credentials: credentials
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isBackingUp, onDismiss: {
                if let passphrase = pendingPassphrase {
                    pendingPassphrase = nil
                    write(passphrase: passphrase)
                }
            }) {
                ExportBackupSheet(
                    contents: contents,
                    onExport: { passphrase in
                        pendingPassphrase = passphrase
                        isBackingUp = false
                    },
                    onCancel: { isBackingUp = false }
                )
            }
            // Presented by its own flag, not by `written` being set: the picker clears its flag as
            // it closes, before this completion runs, and the backup's counts must outlive that.
            .fileExporter(
                isPresented: $isSaving,
                document: written?.document,
                contentType: .zip,
                defaultFilename: BackupExport.suggestedFileName()
            ) { outcome in
                guard let written else { return }
                switch outcome {
                case .success(let url):
                    message = BackupFlow.exportMessage(written.result, fileName: url.lastPathComponent, strips: written.strips)
                case .failure(let error):
                    message = ImportMessage(title: "Couldn't save the backup", body: error.localizedDescription)
                }
                self.written = nil
            }
            .fileImporter(isPresented: $isRestoring, allowedContentTypes: [.zip, .json]) { outcome in
                switch outcome {
                case .success(let url): read(url)
                case .failure(let error):
                    message = ImportMessage(title: "Couldn't read that backup", body: error.localizedDescription)
                }
            }
            .sheet(item: $summary, onDismiss: {
                if let pending = pendingRestore {
                    pendingRestore = nil
                    restore(pending.summary, mode: pending.mode, passphrase: pending.passphrase)
                }
            }) { summary in
                ImportBackupSheet(
                    summary: summary,
                    existingCount: tasks.count,
                    onImport: { mode, passphrase in
                        pendingRestore = (summary, mode, passphrase)
                        self.summary = nil
                    },
                    onCancel: { self.summary = nil }
                )
            }
            .sheet(
                isPresented: Binding(get: { progress != nil }, set: { if !$0 { progress = nil } }),
                onDismiss: {
                    progressShown = false
                    runAfterProgress()
                }
            ) {
                if let progress {
                    BackupProgressView(progress: progress)
                        .interactiveDismissDisabled()
                        .presentationDetents([.medium])
                        .onAppear { progressShown = true }
                }
            }
            .alert(item: $message) { message in
                Alert(title: Text(message.title), message: Text(message.body), dismissButton: .default(Text("OK")))
            }
    }

    private func write(passphrase: String) {
        do {
            let prepared = try BackupFlow.prepareExport(contents, passphrase: passphrase)
            progress = BackupProgress(
                title: "Writing the backup",
                step: prepared.mediaPaths.isEmpty ? "Packing" : "Packing files",
                completed: 0,
                total: prepared.mediaPaths.count
            )
            Task {
                let result = await BackupFlow.pack(prepared) { done, total in
                    progress?.completed = done
                    progress?.total = total
                }
                finishProgress(then: .save(WrittenBackup(
                    document: BackupDocument(data: result.archive), result: result, strips: prepared.strips
                )))
            }
        } catch {
            message = ImportMessage(title: "Couldn't write the backup", body: error.localizedDescription)
        }
    }

    /// The picked file is only readable inside a security scope that ends with this call, but the
    /// files inside it are unpacked later, after the summary sheet — so it is copied somewhere the
    /// app owns first.
    private func read(_ url: URL) {
        do {
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "TaskStrips-restore-\(UUID().uuidString)-\(url.lastPathComponent)")
            try Platform.withAccess(to: url) { try FileManager.default.copyItem(at: $0, to: copy) }
            summary = try BackupFlow.readSummary(at: copy)
        } catch {
            message = ImportMessage(title: "Couldn't read that backup", body: error.localizedDescription)
        }
    }

    private func restore(_ summary: BackupImportSummary, mode: ImportMode, passphrase: String) {
        progress = BackupProgress(
            title: "Reading the backup",
            step: "Restoring files",
            completed: 0,
            total: summary.referencedMediaPaths.count
        )
        Task {
            let outcome = await BackupFlow.restoreMedia(for: summary) { done, total in
                progress?.completed = done
                progress?.total = total
            }
            let result = BackupFlow.apply(
                summary,
                mode: mode,
                passphrase: passphrase,
                restored: outcome.restored,
                mediaProblem: outcome.problem,
                existing: contents,
                context: modelContext
            )
            ReminderScheduler.shared.sync(tasks)
            ReminderScheduler.shared.sync(reminders)
            if let source = summary.sourceURL { try? FileManager.default.removeItem(at: source) }
            finishProgress(then: .report(result))
        }
    }

    private func finishProgress(then next: AfterProgress) {
        afterProgress = next
        let wasShown = progressShown
        progress = nil
        if !wasShown { runAfterProgress() }
    }

    private func runAfterProgress() {
        guard let next = afterProgress else { return }
        afterProgress = nil
        switch next {
        case .save(let backup):
            written = backup
            isSaving = true
        case .report(let result): message = result
        }
    }
}

/// A finished backup, as the Files picker wants it.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.zip]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
