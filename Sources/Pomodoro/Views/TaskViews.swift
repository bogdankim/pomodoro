import PomodoroCore
import SwiftUI

/// The task and note lists inside the popover, with a shared empty state.
/// Short lists are a plain stack so nothing scroll-related flashes when rows
/// animate; only genuinely long lists become a ScrollView.
struct TaskListSection: View {
    let tasks: TaskListModel
    let notes: NoteListModel

    /// Rows that fit comfortably without scrolling.
    private let maxVisibleRows = 7

    var body: some View {
        Group {
            if tasks.visibleTasks.isEmpty && notes.visibleNotes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 19))
                        .foregroundStyle(.tertiary)
                    Text("No tasks or notes yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                listContent
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        // Rows animate when the models mutate: TaskListModel and NoteListModel
        // wrap every change in withAnimation(.listChange).
        let combined = tasks.visibleTasks.map(AnyListItem.task) + notes.visibleNotes.map(AnyListItem.note)
        if combined.count <= maxVisibleRows {
            VStack(spacing: 2) {
                ForEach(combined) { item in
                    row(for: item)
                }
            }
            .padding(.vertical, 2)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(combined) { item in
                        row(for: item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 236)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func row(for item: AnyListItem) -> some View {
        switch item {
        case .task(let task): TaskRow(task: task, tasks: tasks)
        case .note(let note): NoteRow(note: note, notes: notes)
        }
    }
}

/// Type-erased row identity so tasks and notes can share one ForEach while
/// keeping their distinct row views.
enum AnyListItem: Identifiable {
    case task(TaskItem)
    case note(NoteItem)

    var id: UUID {
        switch self {
        case .task(let task): task.id
        case .note(let note): note.id
        }
    }
}

/// A single note row: text only — no checkbox, no priority dot. Notes never
/// complete; the row's hover affordance is delete, nothing else.
struct NoteRow: View {
    let note: NoteItem
    let notes: NoteListModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Text(note.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if hovering {
                Button {
                    notes.remove(note.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete note")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeIn(duration: 0.1), value: hovering)
        .transition(reduceMotion ? .opacity : .blurOut)
        .contextMenu {
            Button("Delete", role: .destructive) {
                notes.remove(note.id)
            }
        }
        .accessibilityLabel("Note: \(note.text)")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
