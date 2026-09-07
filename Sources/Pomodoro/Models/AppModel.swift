import Foundation
import Observation
import PomodoroCore

/// A snapshot of what happened when a phase ended, shown in the summary panel.
struct SessionSummary: Equatable {
    let endedPhase: PhaseKind
    let startedAt: Date
    let total: TimeInterval
    let completedTasks: [TaskItem]
    /// Highest-priority open tasks at the moment the phase ended (capped for the HUD).
    let openTasks: [TaskItem]
    let openCount: Int
}

/// Drives the pomodoro engine off a wall-clock ticker and owns app-level state:
/// the current summary, the day's focus count, and reactions to phase ends.
@MainActor
@Observable
final class AppModel {

    private(set) var engine = PomodoroEngine()
    let settings: SettingsStore
    let tasks: TaskListModel

    private(set) var displaySeconds: Int = 0
    private(set) var summary: SessionSummary?
    private(set) var focusSessionsToday: Int = 0

    /// Called after a summary is produced so the UI layer can present the panel.
    var onSummaryAvailable: (() -> Void)?

    /// Called whenever timer state or the countdown changes so non-SwiftUI
    /// surfaces (the status item icon) can re-render.
    var onStateChange: (() -> Void)?

    private var ticker: Timer?
    private var dayKey = AppModel.todayKey()
    private var previousEngine: PomodoroEngine?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(settings: SettingsStore, tasks: TaskListModel) {
        self.settings = settings
        self.tasks = tasks
        focusSessionsToday = UserDefaults.standard.integer(forKey: "focusSessions.\(Self.todayKey())")
        refreshDisplaySeconds()
        startTicker()
    }

    // MARK: - Derived state

    var phase: PhaseKind? { engine.phase }
    var isRunning: Bool { engine.isRunning }
    var isActive: Bool { engine.isActive }
    var isPaused: Bool {
        if case .paused = engine.state { return true }
        return false
    }

    /// What the Start button begins when the engine is idle.
    var suggestedPhase: PhaseKind {
        engine.suggestedNextPhase(longBreakEvery: settings.longBreakEvery)
    }

    var cycleCompleted: Int { engine.cycleCompleted }

    /// Skip and Reset are available once a session is underway or the cycle has
    /// progress; a fresh loop shows only Start.
    var showPhaseControls: Bool {
        engine.isActive || engine.cycleCompleted > 0
    }

    var timeText: String {
        TimeFormatting.clock(Double(displaySeconds))
    }

    // MARK: - Actions

    func toggleRun() {
        let now = Date()
        switch engine.state {
        case .idle:
            engine.start(suggestedPhase, durations: settings.durations, now: now)
        case .running:
            engine.pause(now: now)
        case .paused:
            engine.resume(now: now)
        }
        refreshDisplaySeconds()
        onStateChange?()
    }

    func reset() {
        engine.reset()
        refreshDisplaySeconds()
        onStateChange?()
    }

    func skip() {
        engine.skip(durations: settings.durations, longBreakEvery: settings.longBreakEvery, now: Date())
        refreshDisplaySeconds()
        onStateChange?()
    }

    /// Starts the suggested phase from idle (summary panel, break end, etc.).
    func startSuggested() {
        guard case .idle = engine.state else { return }
        engine.start(suggestedPhase, durations: settings.durations, now: Date())
        summary = nil
        refreshDisplaySeconds()
        onStateChange?()
    }

    func dismissSummary() {
        summary = nil
    }

    // MARK: - Ticker

    private func startTicker() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = Date()
        rollDayIfNeeded(now: now)
        if let event = engine.tick(now: now) {
            handlePhaseEnd(event)
        }
        refreshDisplaySeconds()
        if engine != previousEngine {
            previousEngine = engine
            onStateChange?()
        }
    }

    private func refreshDisplaySeconds() {
        let seconds: Int
        if engine.state == .idle {
            // Idle shows a preview of the upcoming phase's full duration.
            seconds = Int(settings.durations.duration(for: suggestedPhase).rounded(.up))
        } else {
            seconds = Int(engine.remaining(now: Date()).rounded(.up))
        }
        if seconds != displaySeconds {
            displaySeconds = seconds
            onStateChange?()
        }
    }

    /// Re-renders the countdown preview after a settings change.
    func refreshCountdownDisplay() {
        refreshDisplaySeconds()
        onStateChange?()
    }

    private func handlePhaseEnd(_ event: PomodoroEngine.Event) {
        if event.kind == .focus {
            focusSessionsToday += 1
            UserDefaults.standard.set(focusSessionsToday, forKey: "focusSessions.\(dayKey)")
        }

        let completed = tasks.completed(since: event.startedAt)
        let open = TaskListLogic.sortedOpen(tasks.tasks)
        summary = SessionSummary(
            endedPhase: event.kind,
            startedAt: event.startedAt,
            total: event.total,
            completedTasks: completed,
            openTasks: Array(open.prefix(3)),
            openCount: open.count
        )
        onSummaryAvailable?()

        if settings.soundEnabled {
            SoundPlayer.play(event.kind == .focus ? "Glass" : "Pop")
        }

        if event.kind == .focus && settings.autoStartBreaks {
            engine.start(suggestedPhase, durations: settings.durations, now: Date())
        } else if event.kind.isBreak && settings.autoStartFocus {
            engine.start(.focus, durations: settings.durations, now: Date())
        }
    }

    private func rollDayIfNeeded(now: Date) {
        let key = Self.todayKey()
        if key != dayKey {
            dayKey = key
            focusSessionsToday = UserDefaults.standard.integer(forKey: "focusSessions.\(key)")
        }
    }

    private static func todayKey() -> String {
        dayFormatter.string(from: Date())
    }
}
