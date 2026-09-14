import Foundation

/// Pure operations over a collection of notes, kept out of the UI layer for
/// testability — same pattern as `TaskListLogic`.
public enum NoteListLogic {

    /// Newest first; notes are a scratchpad, the latest thought matters most.
    public static func sorted(_ notes: [NoteItem]) -> [NoteItem] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    /// Notes shown in the list, capped to keep the popover glanceable.
    public static func visible(_ notes: [NoteItem], limit: Int = 50) -> [NoteItem] {
        Array(sorted(notes).prefix(limit))
    }
}
