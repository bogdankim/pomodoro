import Foundation

/// A date-driven pomodoro state machine.
///
/// The engine never schedules anything of its own; callers drive it with `tick(now:)`
/// and pass wall-clock dates, which keeps it deterministic and testable.
public struct PomodoroEngine: Equatable, Sendable {

    public enum State: Equatable, Sendable {
        case idle
        case running(phase: PhaseKind, endAt: Date, total: TimeInterval)
        case paused(phase: PhaseKind, remaining: TimeInterval, total: TimeInterval)
    }

    /// Emitted when a phase reaches its end naturally (never on skip or reset).
    public struct Event: Equatable, Sendable {
        public let kind: PhaseKind
        /// When the phase that just ended began (the current run, not counting pauses).
        public let startedAt: Date
        public let total: TimeInterval
    }

    public private(set) var state: State = .idle
    /// Focus sessions completed within the current cycle; drives the long-break rule
    /// and the session dots. Resets when a long break starts.
    public private(set) var cycleCompleted: Int = 0
    public private(set) var lastPhase: PhaseKind?

    /// When the currently running phase began. Survives pause/resume.
    private var currentSessionStartedAt: Date?

    public init() {}

    // MARK: - Queries

    public var phase: PhaseKind? {
        switch state {
        case .idle: nil
        case .running(let phase, _, _), .paused(let phase, _, _): phase
        }
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isActive: Bool {
        state != .idle
    }

    public func remaining(now: Date) -> TimeInterval {
        switch state {
        case .idle: 0
        case .running(_, let endAt, _): max(0, endAt.timeIntervalSince(now))
        case .paused(_, let remaining, _): remaining
        }
    }

    /// Fraction of the phase elapsed, from 0 to 1.
    public func progress(now: Date) -> Double {
        let total: TimeInterval
        switch state {
        case .idle: return 0
        case .running(_, _, let t): total = t
        case .paused(_, _, let t): total = t
        }
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(now: now) / total))
    }

    /// The phase the user should get when starting from idle.
    public func suggestedNextPhase(longBreakEvery: Int) -> PhaseKind {
        if let lastPhase, lastPhase.isBreak { return .focus }
        if cycleCompleted > 0, cycleCompleted % max(1, longBreakEvery) == 0 { return .longBreak }
        return cycleCompleted == 0 && lastPhase == nil ? .focus : .shortBreak
    }

    // MARK: - Transitions

    public mutating func start(_ phase: PhaseKind, durations: PhaseDurations, now: Date) {
        guard case .idle = state else { return }
        let duration = durations.duration(for: phase)
        guard duration > 0 else { return }
        if phase == .longBreak { cycleCompleted = 0 }
        currentSessionStartedAt = now
        state = .running(phase: phase, endAt: now.addingTimeInterval(duration), total: duration)
    }

    public mutating func pause(now: Date) {
        guard case .running(let phase, let endAt, let total) = state else { return }
        state = .paused(phase: phase, remaining: max(0, endAt.timeIntervalSince(now)), total: total)
    }

    public mutating func resume(now: Date) {
        guard case .paused(let phase, let remaining, let total) = state, remaining > 0 else { return }
        state = .running(phase: phase, endAt: now.addingTimeInterval(remaining), total: total)
    }

    /// Advances time. Returns an event when the running phase finished naturally.
    @discardableResult
    public mutating func tick(now: Date) -> Event? {
        guard case .running(let phase, let endAt, let total) = state, now >= endAt else { return nil }
        if phase == .focus { cycleCompleted += 1 }
        lastPhase = phase
        let startedAt = currentSessionStartedAt ?? endAt.addingTimeInterval(-total)
        currentSessionStartedAt = nil
        state = .idle
        return Event(kind: phase, startedAt: startedAt, total: total)
    }

    /// Abandons the active phase and starts the next one immediately.
    /// A skipped focus does not count toward the long-break cycle.
    public mutating func skip(durations: PhaseDurations, longBreakEvery: Int, now: Date) {
        guard let current = phase else { return }
        let next: PhaseKind = current.isBreak ? .focus : .shortBreak
        let duration = durations.duration(for: next)
        guard duration > 0 else {
            state = .idle
            currentSessionStartedAt = nil
            return
        }
        currentSessionStartedAt = now
        state = .running(phase: next, endAt: now.addingTimeInterval(duration), total: duration)
    }

    /// Abandons everything and returns to a fresh loop: no active phase and no
    /// cycle progress.
    public mutating func reset() {
        state = .idle
        currentSessionStartedAt = nil
        cycleCompleted = 0
        lastPhase = nil
    }
}
