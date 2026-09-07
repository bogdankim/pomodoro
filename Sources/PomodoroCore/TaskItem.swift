import Foundation

/// A todo item with a three-level priority.
public struct TaskItem: Identifiable, Codable, Hashable, Sendable {

    public enum Priority: Int, Codable, Comparable, Sendable, CaseIterable {
        case low = 1
        case medium = 2
        case high = 3

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var displayName: String {
            switch self {
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            }
        }

        public var shortName: String {
            switch self {
            case .low: "Low"
            case .medium: "Med"
            case .high: "High"
            }
        }
    }

    public var id: UUID
    public var title: String
    public var priority: Priority
    public var isDone: Bool
    public var createdAt: Date
    public var doneAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        priority: Priority = .medium,
        isDone: Bool = false,
        createdAt: Date = Date(),
        doneAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.isDone = isDone
        self.createdAt = createdAt
        self.doneAt = doneAt
    }
}
