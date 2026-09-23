import SwiftUI
import UniformTypeIdentifiers

/// What the board's hours and money add up to, for a month or a year.
///
/// The strips never add up across each other — a strip's total is its own, and that was decided
/// deliberately. This asks a question of the board instead: a report is a way of looking, not a
/// thing that gets kept, and nothing on a strip changes because one was run.
struct ValueReportView: View {
    let tasks: [TaskItem]

    @Environment(\.dismiss) private var dismiss
    @State private var range: ValueRange = .thisMonth
    @State private var expanded: Set<String> = []
    @State private var exporting = false

    private var groups: [ValueReport.Group] { ValueReport.byTag(tasks, range: range) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("Period", selection: $range) {
                ForEach(ValueRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            if groups.isEmpty {
                nothing
            } else {
                list
            }
        }
        .readerSize()
        .background(TaskStripTheme.bayBackground)
        .fileExporter(
            isPresented: $exporting,
            document: MailAttachmentFile(bytes: Data(ValueReport.csv(tasks, range: range).utf8)),
            contentType: .commaSeparatedText,
            defaultFilename: ValueReport.fileName(for: range)
        ) { _ in }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOURS AND COSTS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                Text(range.label)
                    .font(.headline)
            }
            Spacer(minLength: 0)
            Button {
                exporting = true
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(groups.isEmpty)
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(14)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private var nothing: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sum")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing counted in this period.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Totals come from what each strip counts — hours, money, anything else. Time "
                 + "clocked before totals existed isn't included.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.amounts) { amount in
                        HStack {
                            Text(amount.unit.label)
                                .font(.callout)
                            Spacer(minLength: 0)
                            Text(StripTally.formatted(amount.amount, unit: amount.unit))
                                .font(.callout.monospacedDigit().weight(.medium))
                                .foregroundStyle(TaskStripTheme.amber)
                        }
                        .listRowBackground(Color.clear)
                    }

                    // The strips behind the number, because a total nobody can take apart is a
                    // number to be distrusted — the same rule the tallies themselves follow.
                    if expanded.contains(group.name) {
                        ForEach(ValueReport.byStrip(tasks, range: range, tag: group.name)) { strip in
                            HStack(alignment: .firstTextBaseline) {
                                Text(strip.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(
                                    strip.amounts
                                        .map { StripTally.formatted($0.amount, unit: $0.unit) }
                                        .joined(separator: " · ")
                                )
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                } header: {
                    Button {
                        toggle(group.name)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: expanded.contains(group.name) ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text(group.name.uppercased())
                                .font(.caption.weight(.semibold))
                            Text("\(group.strips.count) strip\(group.strips.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TaskStripTheme.amber)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func toggle(_ name: String) {
        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
    }
}
