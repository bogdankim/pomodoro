import Foundation

/// One syncable entry in the vault: a checkbox task or a plain-list note as
/// it appears under a daily note's Tasks or Notes heading. The vault sees
/// markdown, so an entry's identity there is its text — `mergeKey` — while
/// `id` is session-local row identity backing SwiftUI animations. Equality
/// deliberately ignores `id` and `createdAt`: neither is representable in a
/// daily note, so a rename on either side reads as deleting one entry and
/// adding another.
public struct VaultEntry: Equatable, Sendable {

    public enum Kind: String, Sendable {
        case task
        case note
    }

    public var id: UUID
    public var kind: Kind
    public var title: String
    public var isDone: Bool
    public var priority: TaskItem.Priority?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        isDone: Bool = false,
        priority: TaskItem.Priority? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.isDone = isDone
        self.priority = priority
        self.createdAt = createdAt
    }

    /// Entries with the same key are the same entry as far as the vault is
    /// concerned.
    public var mergeKey: String { "\(kind.rawValue)|\(title)" }
}

extension TaskItem {

    public var vaultEntry: VaultEntry {
        VaultEntry(
            id: id, kind: .task, title: title, isDone: isDone, priority: priority, createdAt: createdAt)
    }

    public init(entry: VaultEntry) {
        self.init(
            id: entry.id,
            title: entry.title,
            priority: entry.priority ?? .medium,
            isDone: entry.isDone,
            createdAt: entry.createdAt,
            doneAt: nil
        )
    }
}

extension NoteItem {

    public var vaultEntry: VaultEntry {
        VaultEntry(id: id, kind: .note, title: text, createdAt: createdAt)
    }

    public init(entry: VaultEntry) {
        self.init(id: entry.id, text: entry.title, createdAt: entry.createdAt)
    }
}

extension TaskItem.Priority {

    /// The markdown tag that carries priority through the vault, e.g. `#p3`.
    /// Plain tags like `#p2` render natively in Obsidian and are picked up by
    /// the Tasks and Dataview plugins.
    public var vaultTag: String { "#p\(rawValue)" }

    public init?(vaultTag: String) {
        let trimmed = vaultTag.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 3, let value = Int(trimmed.dropFirst(2)), 1...3 ~= value else {
            return nil
        }
        self = TaskItem.Priority(rawValue: value)!
    }
}
