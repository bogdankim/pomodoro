import Foundation

/// Pure operations over a collection of tasks, kept out of the UI layer for testability.
public enum TaskListLogic {

    /// How long a completed task stays visible (struck through) before disappearing.
    public static let completionGrace: TimeInterval = 5

    /// Open tasks sorted by priority (highest first), oldest first within a priority.
    public static func sortedOpen(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { !$0.isDone }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt < rhs.createdAt
            }
    }

    /// The tasks shown in the list: open tasks (highest priority first, oldest first
    /// within a priority) followed by tasks completed within the grace window.
    public static func visible(_ tasks: [TaskItem], now: Date, grace: TimeInterval = completionGrace)
        -> [TaskItem]
    {
        let open = sortedOpen(tasks)
        let finishing =
            tasks
            .filter { task in
                guard task.isDone, let doneAt = task.doneAt else { return false }
                return now.timeIntervalSince(doneAt) < grace && now >= doneAt
            }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        return open + finishing
    }

    /// Tasks completed during a window (e.g. the focus session that just ended),
    /// oldest completion first. Includes tasks whose grace window already passed.
    public static func completed(_ tasks: [TaskItem], since start: Date, until end: Date = .init())
        -> [TaskItem]
    {
        tasks
            .filter { task in
                guard task.isDone, let doneAt = task.doneAt else { return false }
                return doneAt >= start && doneAt <= end
            }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
    }

    /// Number of open (not done) tasks.
    public static func openCount(_ tasks: [TaskItem]) -> Int {
        tasks.lazy.filter { !$0.isDone }.count
    }
}
