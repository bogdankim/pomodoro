import Foundation

/// A free-form note: text only, no priority, no done state. Notes are
/// persistent scratchpad entries — capture quickly, consult later, delete
/// when stale. Unlike tasks they never complete, so they stay out of the
/// session summary and completion logic entirely.
public struct NoteItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
