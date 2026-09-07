import Foundation
import Observation
import PomodoroCore

/// Observable task store with JSON persistence and a five-second grace window
/// after completion: the row stays visible (struck through, muted) and can be
/// un-marked before it disappears from the list.
@MainActor
@Observable
final class TaskListModel {

    private(set) var tasks: [TaskItem] = []

    /// Bumped when a grace window expires so views re-evaluate task visibility.
    private(set) var graceTick = 0

    private var graceTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        tasks = Self.load() ?? []
    }

    // MARK: - Derived

    /// Open tasks first (highest priority, oldest first), then tasks inside the
    /// completion grace window.
    var visibleTasks: [TaskItem] {
        _ = graceTick
        return TaskListLogic.visible(tasks, now: Date(), grace: TaskListLogic.completionGrace)
    }

    var openCount: Int {
        TaskListLogic.openCount(tasks)
    }

    /// Tasks completed within a window, including ones already removed from view.
    func completed(since start: Date, until end: Date = Date()) -> [TaskItem] {
        TaskListLogic.completed(tasks, since: start, until: end)
    }

    // MARK: - Mutations

    func add(title: String, priority: TaskItem.Priority) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TaskItem(title: trimmed, priority: priority))
        save()
    }

    func toggleDone(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[index].isDone {
            tasks[index].isDone = false
            tasks[index].doneAt = nil
            graceTasks[id]?.cancel()
            graceTasks[id] = nil
        } else {
            tasks[index].isDone = true
            tasks[index].doneAt = Date()
            scheduleGraceRemoval(for: id)
        }
        save()
    }

    func setPriority(_ id: UUID, _ priority: TaskItem.Priority) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].priority = priority
        save()
    }

    func remove(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        graceTasks[id]?.cancel()
        graceTasks[id] = nil
        save()
    }

    // MARK: - Grace window

    private func scheduleGraceRemoval(for id: UUID) {
        graceTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TaskListLogic.completionGrace))
            guard !Task.isCancelled else { return }
            self?.graceExpired(for: id)
        }
    }

    private func graceExpired(for id: UUID) {
        graceTasks[id] = nil
        graceTick += 1
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Pomodoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tasks.json")
    }

    private static func load() -> [TaskItem]? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([TaskItem].self, from: data)
    }

    private func save() {
        // Keep the file small: forget tasks completed more than 30 days ago.
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let pruned = tasks.filter { task in
            !(task.isDone && (task.doneAt ?? .distantPast) < cutoff)
        }
        if pruned.count != tasks.count {
            tasks = pruned
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(tasks) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }
}
