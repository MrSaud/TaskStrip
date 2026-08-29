import SwiftUI
import SwiftData

@main
struct TaskStripsApp: App {
    var body: some Scene {
        WindowGroup {
            TaskListView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: TaskItem.self)
    }
}
