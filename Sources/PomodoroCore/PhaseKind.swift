import Foundation

/// The kind of pomodoro phase.
public enum PhaseKind: String, Codable, Sendable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    public var displayName: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    public var isBreak: Bool {
        self != .focus
    }
}

/// Durations for each phase, in seconds.
public struct PhaseDurations: Equatable, Sendable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval

    public init(focus: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
    }

    public func duration(for phase: PhaseKind) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}
