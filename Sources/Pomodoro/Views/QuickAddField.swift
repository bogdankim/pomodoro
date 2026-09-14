import Combine
import PomodoroCore
import SwiftUI

/// What the capture fields create on Return.
enum CaptureMode: Hashable {
    case task
    case note

    var toggled: CaptureMode {
        self == .task ? .note : .task
    }
}

/// Capsule showing the current priority; clicking cycles it just like Tab
/// does while the adjacent field is focused. Changing priorities rolls the
/// old label up and out.
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

/// The inline quick-add row at the top of the task list. The leading icon
/// switches what Return creates — task or note — and doubles as the mode
/// indicator; Shift-Tab toggles it from the keyboard. Tab cycles priority.
struct QuickAddField: View {
    let tasks: TaskListModel
    let notes: NoteListModel

    @State private var draft = ""
    @State private var priority: TaskItem.Priority = .medium
    @State private var mode: CaptureMode = .task
    @State private var keyMonitor: CaptureModeKeyMonitor?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            modeButton

            TextField(
                "Add",
                text: $draft,
                prompt: Text(mode == .note ? "Add a note…" : "Add a task…").foregroundStyle(.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.body)
            .focused($fieldFocused)
            .onSubmit(add)
            .onKeyPress(.tab) {
                guard mode == .task else { return .ignored }
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
            // Kept in the layout in both modes and faded out for notes, so
            // the row's height (and width) never changes when modes flip.
            .opacity(mode == .task ? 1 : 0)
            .allowsHitTesting(mode == .task)
            .accessibilityHidden(mode != .task)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.25), value: mode)
        .onAppear(perform: installMonitor)
        .onDisappear { keyMonitor?.remove() }
    }

    /// The mode switch: plus for tasks, note glyph for notes. Lives where
    /// the eye already starts, adds no width, and always shows the state.
    private var modeButton: some View {
        Button {
            mode = mode.toggled
        } label: {
            Image(systemName: mode == .note ? "note.text" : "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode == .task ? "Capture a note instead (⇧Tab)" : "Capture a task instead (⇧Tab)")
        .accessibilityLabel(mode == .task ? "Switch to note capture" : "Switch to task capture")
    }

    /// Shift-Tab is swallowed by AppKit's key view loop before SwiftUI's
    /// key handlers see it, so mode toggling needs an event monitor that
    /// runs while the field is focused. The focus state is read live through
    /// its property wrapper — a capture list would freeze it at creation.
    private func installMonitor() {
        let monitor = CaptureModeKeyMonitor(
            shouldIntercept: { fieldFocused },
            onIntercept: { mode = mode.toggled }
        )
        monitor.install()
        keyMonitor = monitor
    }

    private func add() {
        switch mode {
        case .task:
            tasks.add(title: draft, priority: priority)
        case .note:
            notes.add(text: draft)
        }
        draft = ""
    }
}
