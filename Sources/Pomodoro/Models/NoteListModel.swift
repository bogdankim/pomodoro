import Foundation
import Observation
import PomodoroCore
import SwiftUI

/// Observable note store with JSON persistence. Notes never complete, so
/// unlike `TaskListModel` there is no grace window — deletion is immediate.
@MainActor
@Observable
final class NoteListModel {

    private(set) var notes: [NoteItem] = []

    init() {
        notes = Self.load() ?? []
    }

    // MARK: - Derived

    /// Newest first, capped so the popover stays a glance surface.
    var visibleNotes: [NoteItem] {
        NoteListLogic.visible(notes)
    }

    /// Called after any list mutation (vault sync included) so the vault
    /// layer can push the change.
    var onListChange: (() -> Void)?

    // MARK: - Mutations

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Collapse internal line breaks: a note is a one-liner in the popover.
        let singleLine = trimmed.replacingOccurrences(
            of: "\\s*\\n\\s*", with: " ", options: .regularExpression)
        withAnimation(.listChange) {
            notes.append(NoteItem(text: singleLine))
        }
        save()
    }

    func remove(_ id: UUID) {
        withAnimation(.listChange) {
            notes.removeAll { $0.id == id }
        }
        save()
    }

    // MARK: - Vault sync

    /// Replaces the whole list from a vault merge. Entries keep the ids they
    /// arrived with, so unchanged rows never animate.
    func replaceFromVault(_ items: [NoteItem]) {
        withAnimation(.listChange) {
            notes = items
        }
        save()
    }

    /// Empties the list for a new day. History stays in the vault's previous
    /// daily note; the app shows only the current day.
    func clear() {
        withAnimation(.listChange) {
            notes = []
        }
        save()
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Pomodoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notes.json")
    }

    private static func load() -> [NoteItem]? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([NoteItem].self, from: data)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
        onListChange?()
    }
}
