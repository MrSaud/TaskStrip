import SwiftUI
import SwiftData

// Phase 0 spike screen: the thinnest possible add/list/delete loop over SwiftData, just to
// confirm the toolchain (Xcode project, SwiftData persistence, code signing for local runs)
// works before Phase 1 builds the real task model and "flight strip" UI on top of it.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("New task title…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button("Add", action: addTask)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            List {
                ForEach(tasks) { task in
                    HStack {
                        Button {
                            task.isDone.toggle()
                        } label: {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        Text(task.title)
                            .strikethrough(task.isDone)
                    }
                }
                .onDelete(perform: deleteTasks)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .navigationTitle("Task Strips")
    }

    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(TaskItem(title: trimmed))
        newTitle = ""
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
    }
}
