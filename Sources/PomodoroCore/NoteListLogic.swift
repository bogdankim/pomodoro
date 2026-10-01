import Foundation

/// Pure operations over a collection of notes, kept out of the UI layer for
/// testability — same pattern as `TaskListLogic`.
public enum NoteListLogic {

    /// Newest first; notes are a scratchpad, the latest thought matters most.
    /// Stampless (vault-adopted) notes sort below everything timestamped.
    public static func sorted(_ notes: [NoteItem]) -> [NoteItem] {
        notes.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case (let l?, let r?): return l > r
            case (.some, nil): return true
            default: return false
            }
        }
    }

    /// Notes shown in the list, capped to keep the popover glanceable.
    public static func visible(_ notes: [NoteItem], limit: Int = 50) -> [NoteItem] {
        Array(sorted(notes).prefix(limit))
    }
}
