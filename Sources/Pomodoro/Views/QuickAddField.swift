import Combine
import PomodoroCore
import SwiftUI

/// Capsule showing the current priority; clicking cycles it just like Tab does
/// in the adjacent field. Changing priorities rolls the old label up and out.
struct PriorityChip: View {
    let priority: TaskItem.Priority
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(priority.tint)
                        .frame(width: 7, height: 7)
                    Text(priority.shortName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 46)
                .id(priority)
                .transition(reduceMotion ? .opacity : priorityRoll)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: priority)
        .help("Priority (Tab to cycle)")
        .accessibilityLabel("\(priority.displayName) priority")
    }

    /// Removal slides up and out while the new value slides in from below,
    /// giving the cycle a rolling feel; clipped to the capsule.
    private var priorityRoll: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .offset(y: -12).combined(with: .opacity)
        )
    }
}

/// The inline quick-add row at the top of the task list. Type a task, press
/// Tab to cycle the priority, press Return to add it.
struct QuickAddField: View {
    let tasks: TaskListModel

    @State private var draft = ""
    @State private var priority: TaskItem.Priority = .medium
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField(
                "Add a task",
                text: $draft,
                prompt: Text("Add a task…").foregroundStyle(.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.body)
            .focused($fieldFocused)
            .onSubmit(add)
            .onKeyPress(.tab) {
                priority = priority.next
                return .handled
            }
            .onKeyPress(.escape) {
                fieldFocused = false
                return .handled
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusQuickAddField)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    fieldFocused = true
                }
            }

            PriorityChip(priority: priority) {
                priority = priority.next
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func add() {
        tasks.add(title: draft, priority: priority)
        draft = ""
    }
}
