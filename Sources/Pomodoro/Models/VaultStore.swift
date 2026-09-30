import Foundation
import Observation
import PomodoroCore

/// Keeps the app's tasks and notes in two-way sync with the vault's daily
/// notes: the app renders captures into `Daily/YYYY-MM-DD.md` under
/// `### Tasks` / `### Notes`, and edits made in Obsidian merge back in.
///
/// Sync is poll-based (2s) because iCloud-mounted vaults make file watchers
/// unreliable. Every cycle compares three states through `VaultSync` — the
/// app's list, the note's parsed entries, and the merged state as of the
/// last completed sync — and pushes or pulls only the differences. Writes
/// the app made are remembered and skipped as echoes.
@MainActor
@Observable
final class VaultStore {

    enum Status: Equatable {
        case idle
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncDate: Date?

    var onVaultChangeApplied: (() -> Void)?

    private let settings: SettingsStore
    private let tasks: TaskListModel
    private let notes: NoteListModel

    private var pollTimer: Timer?
    private var pushDebounce: Timer?
    /// Merged state as of the last completed sync, per day.
    private var base: [String: [VaultEntry]] = [:]
    /// The exact text the app last wrote for a day, so polls skip echoes.
    private var lastWritten: [String: String] = [:]
    /// The day the persisted store belongs to. A launch on any later day
    /// means the store holds yesterday's data: cleared before first sync.
    private var currentDay: String
    /// True while the store is rebuilding the models from merged state, so
    /// the resulting model callbacks don't schedule a redundant push.
    private var isApplyingToModels = false

    init(settings: SettingsStore, tasks: TaskListModel, notes: NoteListModel) {
        self.settings = settings
        self.tasks = tasks
        self.notes = notes
        let stored = UserDefaults.standard.string(forKey: "vaultSyncDay")
        currentDay = stored ?? VaultStore.todayKey()
        if settings.vaultSyncEnabled, currentDay < VaultStore.todayKey() {
            // Yesterday's store: the new day starts blank. The old list is
            // already in its daily note, and sync opens today's empty one.
            tasks.clear()
            notes.clear()
            currentDay = VaultStore.todayKey()
            UserDefaults.standard.set(currentDay, forKey: "vaultSyncDay")
        }
    }

    /// The first sync persists the day key; afterwards every rollover
    /// updates it so the next launch knows how old the store is.
    func start() {
        guard pollTimer == nil else { return }
        UserDefaults.standard.set(currentDay, forKey: "vaultSyncDay")
        syncNow()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pushDebounce?.invalidate()
        pushDebounce = nil
    }

    /// Called after any local data change; coalesces bursts into one sync.
    func pushSoon() {
        guard settings.vaultSyncEnabled, !isApplyingToModels else { return }
        pushDebounce?.invalidate()
        let item = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        RunLoop.main.add(item, forMode: .common)
        pushDebounce = item
    }

    /// Full sync cycle: day rollover, read, merge, pull, push.
    func syncNow() {
        guard settings.vaultSyncEnabled else { return }
        let root = URL(fileURLWithPath: settings.vaultPath, isDirectory: true)
        guard !settings.vaultPath.isEmpty, FileManager.default.fileExists(atPath: root.path) else {
            status = .error("Vault folder not found")
            return
        }

        rollDayIfNeeded()
        let noteURL = dailyNoteURL(root: root)
        let text = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""

        if text == lastWritten[currentDay] {
            base[currentDay] = localEntries()
            status = .idle
            return
        }
        let (vaultEntries, doneDates) = VaultMarkdown.entries(in: text)
        let result = VaultSync.merge(
            local: localEntries(), vault: vaultEntries, base: base[currentDay] ?? [], now: Date())

        if result.appNeedsUpdate {
            applyToModels(result.entries, doneDates: doneDates)
            onVaultChangeApplied?()
        }

        let noteExists = FileManager.default.fileExists(atPath: noteURL.path)
        if result.vaultNeedsWrite || (!result.entries.isEmpty && !noteExists) {
            do {
                let written = try write(result.entries, doneDates: doneDates, to: noteURL, existing: text)
                lastWritten[currentDay] = written
            } catch {
                status = .error("Write failed: \(error.localizedDescription)")
                return
            }
        }

        base[currentDay] = result.entries
        lastSyncDate = Date()
        status = .idle
    }

    // MARK: - Pieces

    private func localEntries() -> [VaultEntry] {
        tasks.tasks.map(\.vaultEntry) + notes.notes.map(\.vaultEntry)
    }

    private func dailyNoteURL(root: URL) -> URL {
        root.appendingPathComponent("Daily", isDirectory: true)
            .appendingPathComponent("\(currentDay).md")
    }

    private func rollDayIfNeeded() {
        let today = VaultStore.todayKey()
        guard today != currentDay else { return }
        currentDay = today
        pruneOldDays(keeping: today)
        // The vault's daily note is the database: a new day starts blank in
        // the app, and yesterday's list lives on in yesterday's note.
        tasks.clear()
        notes.clear()
        base[currentDay] = []
        lastWritten[currentDay] = nil
    }

    private func pruneOldDays(keeping day: String) {
        base = base.filter { $0.key >= day }
        lastWritten = lastWritten.filter { $0.key >= day }
    }

    /// Rebuilds the observable models from merged entries. Tasks completed in
    /// the vault take the daily note's `✅` stamp as their completion date, so
    /// they age out of the store on the same 30-day horizon as locally
    /// completed ones and stay out of every session summary.
    private func applyToModels(_ entries: [VaultEntry], doneDates: [String: Date]) {
        isApplyingToModels = true
        defer { isApplyingToModels = false }

        let taskEntries = entries.filter { $0.kind == .task }
        let noteEntries = entries.filter { $0.kind == .note }
        tasks.replaceFromVault(
            taskEntries.map { entry in
                var item = TaskItem(entry: entry)
                if item.isDone {
                    item.doneAt =
                        tasks.tasks.first(where: { $0.id == item.id })?.doneAt
                        ?? doneDates[entry.mergeKey]
                }
                return item
            })
        notes.replaceFromVault(noteEntries.map(NoteItem.init(entry:)))
    }

    /// Renders the merged entries into the note and writes it, creating the
    /// Daily folder and note (with the app's minimal section skeleton) when
    /// missing. Returns the text written.
    private func write(_ entries: [VaultEntry], doneDates: [String: Date], to url: URL, existing: String)
        throws -> String
    {
        var doneMap = doneDates
        for task in tasks.tasks where task.isDone {
            doneMap[task.vaultEntry.mergeKey] = task.doneAt ?? Date()
        }

        var text = existing
        if text.isEmpty {
            text = "\(VaultMarkdown.taskSectionHeading)\n\n\(VaultMarkdown.noteSectionHeading)\n"
        }
        let updated = VaultMarkdown.applying(entries: entries, doneDates: doneMap, to: text)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return updated
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
