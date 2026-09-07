import PomodoroCore
import SwiftUI

/// The task list inside the popover, with an empty state. Short lists are a
/// plain stack so nothing scroll-related flashes when rows animate; only
/// genuinely long lists become a ScrollView.
struct TaskListSection: View {
    let tasks: TaskListModel

    /// Rows that fit comfortably without scrolling.
    private let maxVisibleRows = 7

    var body: some View {
        Group {
            if tasks.visibleTasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 19))
                        .foregroundStyle(.tertiary)
                    Text("No tasks yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if tasks.visibleTasks.count <= maxVisibleRows {
                VStack(spacing: 2) {
                    ForEach(tasks.visibleTasks) { task in
                        TaskRow(task: task, tasks: tasks)
                    }
                }
                .padding(.vertical, 2)
                .animation(.snappy(duration: 0.35), value: tasks.visibleTasks.map(\.id))
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tasks.visibleTasks) { task in
                            TaskRow(task: task, tasks: tasks)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 236)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .animation(.snappy(duration: 0.35), value: tasks.visibleTasks.map(\.id))
            }
        }
    }
}

/// A single task row. Completing it mutes and strikes the title; the row
/// lingers for a few seconds and can be un-marked before it disappears.
struct TaskRow: View {
    let task: TaskItem
    let tasks: TaskListModel

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Button {
                tasks.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(task.isDone ? "Mark \(task.title) as not done" : "Mark \(task.title) as done")

            Text(task.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .animation(.snappy(duration: 0.2), value: task.isDone)

            Spacer(minLength: 8)

            if hovering && !task.isDone {
                Button {
                    tasks.remove(task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete task")
                .transition(.opacity)
            }

            Circle()
                .fill(task.priority.tint)
                .frame(width: 8, height: 8)
                .help("\(task.priority.displayName) priority")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeIn(duration: 0.1), value: hovering)
        .transition(reduceMotion ? .opacity : .blurOut)
        .contextMenu {
            Button(task.isDone ? "Mark as Not Done" : "Mark as Done") {
                tasks.toggleDone(task.id)
            }
            Menu("Priority") {
                ForEach(TaskItem.Priority.allCases, id: \.self) { priority in
                    Button(priority.displayName) {
                        tasks.setPriority(task.id, priority)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                tasks.remove(task.id)
            }
        }
    }
}
