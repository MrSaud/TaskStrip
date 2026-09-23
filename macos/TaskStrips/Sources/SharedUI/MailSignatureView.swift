import SwiftUI

/// Writing the signature for one account, and seeing what it will look like.
///
/// The preview is the point: a colour and a size chosen off a list mean nothing until they're
/// shown as the recipient will see them.
struct MailSignatureView: View {
    let account: IMAPAccount
    /// Called with the edited signature, to be saved against the account.
    let onSave: (MailSignature) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var signature: MailSignature

    init(account: IMAPAccount, onSave: @escaping (MailSignature) -> Void) {
        self.account = account
        self.onSave = onSave
        _signature = State(initialValue: account.signature ?? MailSignature())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Signature") {
                    TextEditor(text: $signature.text)
                        .frame(minHeight: 110)
                        .font(.body)
                }

                Section("How it looks") {
                    Picker("Font", selection: $signature.family) {
                        ForEach(MailSignature.Family.allCases) { family in
                            Text(family.label).tag(family)
                        }
                    }
                    Picker("Size", selection: $signature.size) {
                        ForEach(MailSignature.sizes, id: \.self) { size in
                            Text("\(size) pt").tag(size)
                        }
                    }
                    Picker("Colour", selection: $signature.colorHex) {
                        ForEach(MailSignature.colours, id: \.hex) { colour in
                            HStack {
                                Circle()
                                    .fill(Color(hex: UInt32(colour.hex, radix: 16) ?? 0))
                                    .frame(width: 10, height: 10)
                                Text(colour.name)
                            }
                            .tag(colour.hex)
                        }
                    }
                    Toggle("Bold", isOn: $signature.isBold)
                    Toggle("Italic", isOn: $signature.isItalic)
                }

                Section {
                    if signature.isEmpty {
                        Text("Nothing yet — what you type above appears here as the person reading it will see it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(signature.text)
                            .font(previewFont)
                            .foregroundStyle(Color(hex: UInt32(signature.colorHex, radix: 16) ?? 0))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("A styled signature sends the message as plain text and as HTML, so it "
                         + "looks right in mail programs that show one or the other.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .readerSize()
        .background(TaskStripTheme.bayBackground)
    }

    private var previewFont: Font {
        var font = Font.system(size: CGFloat(signature.size), design: design)
        if signature.isBold { font = font.weight(.bold) }
        if signature.isItalic { font = font.italic() }
        return font
    }

    private var design: Font.Design {
        switch signature.family {
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SIGNATURE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                Text(account.email)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Button("Save") {
                onSave(signature)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .background(TaskStripTheme.baySurfaceFaded)
    }
}
