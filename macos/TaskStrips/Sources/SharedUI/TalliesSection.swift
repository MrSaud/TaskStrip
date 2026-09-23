import SwiftUI

/// The running totals on a strip: hours spent, money spent, whatever else adds up.
///
/// The editor for them is deliberately two things — a total you can read at a glance, and a way
/// to add to it in two taps. Everything else (where the number came from, when, a note) is behind
/// the total, because the total is what anybody opens this for.
struct TalliesSection: View {
    @Binding var tallies: [TaskTally]

    /// Whatever the device counts money in, unless a tally says otherwise.
    private var currency: String { Locale.current.currency?.identifier ?? "USD" }

    @State private var adding = false
    @State private var newName = ""
    @State private var newUnit = "hours"
    @State private var newCustomUnit = ""
    @State private var newTarget = ""
    @State private var expanded: Set<UUID> = []
    @State private var amounts: [UUID: String] = [:]
    /// What each addition was for, and when it happened — kept per tally while it's being typed.
    @State private var notes: [UUID: String] = [:]
    @State private var dates: [UUID: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tallies.isEmpty && !adding {
                Text("Nothing counted on this strip yet — hours, money, anything that adds up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach($tallies) { $tally in
                tallyView($tally)
            }

            if adding {
                newTallyForm
            } else {
                Button {
                    adding = true
                } label: {
                    Label("Add a total", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - One tally

    private func tallyView(_ tally: Binding<TaskTally>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tally.wrappedValue.name.isEmpty ? "Untitled" : tally.wrappedValue.name)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text(StripTally.formatted(tally.wrappedValue.total, unit: tally.wrappedValue.unit))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tally.wrappedValue.isOverTarget ? TaskStripTheme.urgent : TaskStripTheme.amber)
                Button {
                    toggle(tally.wrappedValue.id)
                } label: {
                    Image(systemName: expanded.contains(tally.wrappedValue.id) ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if let target = tally.wrappedValue.target, target > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: min(tally.wrappedValue.progress ?? 0, 1))
                        .tint(tally.wrappedValue.isOverTarget ? TaskStripTheme.urgent : TaskStripTheme.amber)
                    Text(targetLine(for: tally.wrappedValue))
                        .font(.caption)
                        .foregroundStyle(tally.wrappedValue.isOverTarget ? TaskStripTheme.urgent : .secondary)
                }
            }

            // The number, what it was for, and when it happened. The date is today unless it
            // isn't: hours are written up the morning after as often as on the day.
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Add \(tally.wrappedValue.unit.label.lowercased())", text: amountBinding(tally.wrappedValue.id))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(maxWidth: 110)
                        .onSubmit { add(to: tally) }
                    TextField("What for (optional)", text: noteBinding(tally.wrappedValue.id))
                        .onSubmit { add(to: tally) }
                }
                HStack(spacing: 8) {
                    DatePicker(
                        "On",
                        selection: dateBinding(tally.wrappedValue.id),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .font(.caption)
                    Spacer(minLength: 0)
                    Button("Add") { add(to: tally) }
                        .buttonStyle(.bordered)
                        .disabled(Double(amounts[tally.wrappedValue.id] ?? "") == nil)
                }
            }

            if expanded.contains(tally.wrappedValue.id) {
                entries(of: tally)
            }
        }
        .padding(10)
        .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 4))
    }

    private func targetLine(for tally: TaskTally) -> String {
        let target = StripTally.formatted(tally.target ?? 0, unit: tally.unit)
        guard let remaining = tally.remaining else { return "of \(target)" }
        if tally.isOverTarget {
            return "of \(target) — over by \(StripTally.formatted(-remaining, unit: tally.unit))"
        }
        return "of \(target) — \(StripTally.formatted(remaining, unit: tally.unit)) left"
    }

    /// Where the total came from. A total nobody can take apart is a number to be distrusted.
    private func entries(of tally: Binding<TaskTally>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if tally.wrappedValue.entries.isEmpty {
                Text("Nothing added yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(tally.wrappedValue.entries) { entry in
                HStack(spacing: 8) {
                    Text(StripTally.formatted(entry.amount, unit: tally.wrappedValue.unit))
                        .font(.caption.monospacedDigit())
                    Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if entry.fromTimer {
                        Image(systemName: "stopwatch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        tally.wrappedValue.entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this entry")
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    tallies.removeAll { $0.id == tally.wrappedValue.id }
                } label: {
                    Label("Remove this total", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Making one

    private var newTallyForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What's being counted — \"Training hours\", \"Cost\"", text: $newName)
            HStack {
                Picker("Unit", selection: $newUnit) {
                    Text("Hours").tag("hours")
                    Text("Minutes").tag("minutes")
                    Text(currency).tag("money")
                    Text("Count").tag("count")
                    Text("Other…").tag("custom")
                }
                .labelsHidden()
                if newUnit == "custom" {
                    TextField("Unit — km, pages, boxes", text: $newCustomUnit)
                }
            }
            TextField("Target (optional) — a budget, or a goal", text: $newTarget)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

            HStack {
                Button("Add") { make() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { cancel() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 4))
    }

    private func make() {
        let unit: TallyUnit
        switch newUnit {
        case "minutes": unit = .minutes
        case "money": unit = .money(currency: currency)
        case "count": unit = .count
        case "custom": unit = .custom(newCustomUnit.trimmingCharacters(in: .whitespaces))
        default: unit = .hours
        }
        var tally = TaskTally(name: newName.trimmingCharacters(in: .whitespaces), unit: unit)
        tally.target = Double(newTarget.trimmingCharacters(in: .whitespaces))
        tallies.append(tally)
        expanded.insert(tally.id)
        cancel()
    }

    private func cancel() {
        adding = false
        newName = ""
        newUnit = "hours"
        newCustomUnit = ""
        newTarget = ""
    }

    private func add(to tally: Binding<TaskTally>) {
        let id = tally.wrappedValue.id
        guard let amount = Double(amounts[id] ?? ""), amount != 0 else { return }
        tally.wrappedValue = StripTally.adding(
            amount,
            to: tally.wrappedValue,
            note: (notes[id] ?? "").trimmingCharacters(in: .whitespaces),
            at: dates[id] ?? .now
        )
        amounts[id] = ""
        notes[id] = ""
        // The date stays where it was put: several entries from the same day usually arrive
        // together.
    }

    private func amountBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { amounts[id] ?? "" }, set: { amounts[id] = $0 })
    }

    private func noteBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { notes[id] ?? "" }, set: { notes[id] = $0 })
    }

    private func dateBinding(_ id: UUID) -> Binding<Date> {
        Binding(get: { dates[id] ?? .now }, set: { dates[id] = $0 })
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}
