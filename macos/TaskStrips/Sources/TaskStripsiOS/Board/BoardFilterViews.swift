import SwiftUI

/// The board's tags, as a row of chips over the strips — Android's home screen has the same row,
/// and tapping the chip that's already on turns it off.
struct TagChips: View {
    let tags: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    let isOn = selected?.caseInsensitiveCompare(tag) == .orderedSame
                    Button {
                        selected = isOn ? nil : tag
                    } label: {
                        Text(tag.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(isOn ? TaskStripTheme.ink : TaskStripTheme.paper.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isOn ? TaskStripTheme.amber : TaskStripTheme.baySurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(TaskStripTheme.bayBackground)
    }
}

/// Everything else that narrows or reorders the board, in one menu: today and overdue, the
/// priorities to show, the order, and a way out of all of it. The button fills in and carries a
/// count while anything is hiding strips, so a board that looks short is never a mystery.
struct BoardFilterMenu: View {
    @Binding var filter: BoardFilter

    var body: some View {
        Menu {
            Toggle(isOn: $filter.todayOnly) {
                Label("Today & overdue", systemImage: "alarm")
            }

            Section("Priority") {
                ForEach(Priority.allCases) { priority in
                    Toggle(isOn: binding(for: priority)) {
                        Text(priority.label)
                    }
                }
            }

            Section("Order") {
                Picker("Order", selection: $filter.sort) {
                    ForEach(BoardFilter.Sort.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            }

            if filter.isNarrowing {
                Section {
                    Button(role: .destructive) {
                        filter.clear()
                    } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Label(
                "Filter strips",
                systemImage: filter.isNarrowing ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityValue(filter.isNarrowing ? "\(filter.narrowingCount) filters on" : "no filters")
    }

    private func binding(for priority: Priority) -> Binding<Bool> {
        Binding(
            get: { filter.priorities.contains(priority) },
            set: { isOn in
                if isOn { filter.priorities.insert(priority) } else { filter.priorities.remove(priority) }
            }
        )
    }
}
