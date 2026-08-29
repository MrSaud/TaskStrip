import SwiftUI

// Mirrors ui/components/DateRangeFilter.kt's dialog at the concept level: an optional
// from/to bound on a task's due date.
struct DateRangeFilterView: View {
    @Binding var from: Date?
    @Binding var to: Date?

    @State private var fromEnabled: Bool
    @State private var toEnabled: Bool
    @State private var fromValue: Date
    @State private var toValue: Date

    init(from: Binding<Date?>, to: Binding<Date?>) {
        _from = from
        _to = to
        _fromEnabled = State(initialValue: from.wrappedValue != nil)
        _toEnabled = State(initialValue: to.wrappedValue != nil)
        _fromValue = State(initialValue: from.wrappedValue ?? .now)
        _toValue = State(initialValue: to.wrappedValue ?? .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILTER BY DUE DATE").font(.headline)

            Toggle("From", isOn: $fromEnabled)
            if fromEnabled {
                DatePicker("", selection: $fromValue, displayedComponents: .date)
                    .labelsHidden()
            }

            Toggle("To", isOn: $toEnabled)
            if toEnabled {
                DatePicker("", selection: $toValue, displayedComponents: .date)
                    .labelsHidden()
            }

            HStack {
                Button("Clear") {
                    fromEnabled = false
                    toEnabled = false
                    apply()
                }
                Spacer()
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private func apply() {
        from = fromEnabled ? fromValue : nil
        to = toEnabled ? toValue : nil
    }
}
