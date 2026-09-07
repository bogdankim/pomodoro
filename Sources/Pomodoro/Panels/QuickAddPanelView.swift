import PomodoroCore
import SwiftUI

/// Spotlight-style capture panel for the global shortcut (⌘⇧P): type the task,
/// Tab cycles the priority, Return creates it, Escape dismisses.
struct QuickAddPanelView: View {
    let onCommit: (String, TaskItem.Priority) -> Void
    let onCancel: () -> Void

    @State private var draft = ""
    @State private var priority: TaskItem.Priority = .medium
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)

                TextField(
                    "Add a task",
                    text: $draft,
                    prompt: Text("Add a task…").foregroundStyle(.tertiary)
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .onSubmit(commit)
                .onKeyPress(.tab) {
                    priority = priority.next
                    return .handled
                }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }

                PriorityChip(priority: priority) {
                    priority = priority.next
                }
            }

            HStack {
                Text("Tab cycles priority")
                    .help("Press Tab to switch between Low, Medium and High")
                Spacer()
                Text("Return adds · Esc dismisses")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .onAppear {
            fieldFocused = true
        }
    }

    private func commit() {
        onCommit(draft, priority)
        draft = ""
        priority = .medium
    }
}
