import PomodoroCore
import SwiftUI

/// Spotlight-style capture panel for the global shortcut (⌘⇧P): the leading
/// icon switches task/note (Shift-Tab does from the keyboard), Tab cycles
/// priority, Return creates, Escape dismisses.
struct QuickAddPanelView: View {
    let onCommit: (String, TaskItem.Priority, CaptureMode) -> Void
    let onCancel: () -> Void

    @State private var draft = ""
    @State private var priority: TaskItem.Priority = .medium
    @State private var mode: CaptureMode = .task
    @State private var keyMonitor: CaptureModeKeyMonitor?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                modeButton

                TextField(
                    "Add",
                    text: $draft,
                    prompt: Text(mode == .note ? "Add a note…" : "Add a task…").foregroundStyle(.tertiary)
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .onSubmit(commit)
                .onKeyPress(.tab) {
                    guard mode == .task else { return .ignored }
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
                // Kept in the layout in both modes and faded out for notes,
                // so the row's height (and width) never changes on toggle.
                .opacity(mode == .task ? 1 : 0)
                .allowsHitTesting(mode == .task)
                .accessibilityHidden(mode != .task)
            }

            HStack {
                Text(mode == .task ? "Tab cycles priority · ⇧Tab for note" : "⇧Tab for task")
                    .help(
                        mode == .task
                            ? "Press Tab to switch between Low, Medium and High; Shift-Tab captures a note instead"
                            : "Shift-Tab captures a task instead"
                    )
                Spacer()
                Text("Return adds · Esc dismisses")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .animation(.snappy(duration: 0.25), value: mode)
        .onAppear {
            fieldFocused = true
            installMonitor()
        }
        .onDisappear { keyMonitor?.remove() }
    }

    /// The mode switch: plus for tasks, note glyph for notes. Lives where
    /// the eye already starts, adds no width, and always shows the state.
    private var modeButton: some View {
        Button {
            mode = mode.toggled
        } label: {
            Image(systemName: mode == .note ? "note.text" : "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode == .task ? "Capture a note instead (⇧Tab)" : "Capture a task instead (⇧Tab)")
        .accessibilityLabel(mode == .task ? "Switch to note capture" : "Switch to task capture")
    }

    /// Shift-Tab is swallowed by AppKit's key view loop before SwiftUI's
    /// key handlers see it, so mode toggling needs an event monitor that
    /// runs while the panel is key. The focus state is read live through
    /// its property wrapper — a capture list would freeze it at creation.
    private func installMonitor() {
        let monitor = CaptureModeKeyMonitor(
            shouldIntercept: { fieldFocused },
            onIntercept: { mode = mode.toggled }
        )
        monitor.install()
        keyMonitor = monitor
    }

    private func commit() {
        onCommit(draft, priority, mode)
        draft = ""
        priority = .medium
    }
}
