import Foundation
import PomodoroCore

// Assertion harness runnable without full Xcode: `swift run PomodoroChecks`.
// Exits non-zero when any check fails.

nonisolated(unsafe) var failures = 0

func expect<T: Equatable>(
    _ actual: T, _ expected: T, _ label: String, file: StaticString = #filePath, line: UInt = #line
) {
    if actual != expected {
        failures += 1
        print("FAIL [\(label)] at \(file):\(line): got \(actual), expected \(expected)")
    }
}

func expectTrue(_ condition: Bool, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    if !condition {
        failures += 1
        print("FAIL [\(label)] at \(file):\(line)")
    }
}

func runEngineChecks() {
    let durations = PhaseDurations(focus: 1500, shortBreak: 300, longBreak: 900)
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    // Fresh engine runs focus.
    var engine = PomodoroEngine()
    engine.start(.focus, durations: durations, now: t0)
    expect(engine.phase, .focus, "fresh engine phase")
    expectTrue(engine.isRunning, "fresh engine running")
    expect(engine.progress(now: t0), 0, "progress at start")

    // Tick completes the phase and emits an event.
    expect(engine.tick(now: t0.addingTimeInterval(1499)) == nil, true, "no event before end")
    let event = engine.tick(now: t0.addingTimeInterval(1500))
    expect(event?.kind, .focus, "event kind")
    expect(event?.startedAt, t0, "event start")
    expect(event?.total, 1500, "event total")
    expect(engine.state, .idle, "idle after completion")
    expect(engine.cycleCompleted, 1, "cycle counted")
    expect(engine.remaining(now: t0.addingTimeInterval(2000)), 0, "remaining clamped to zero")

    // Long break after every fourth focus.
    engine = PomodoroEngine()
    for _ in 1...3 {
        engine.start(.focus, durations: durations, now: t0)
        _ = engine.tick(now: t0.addingTimeInterval(1500))
        expect(engine.suggestedNextPhase(longBreakEvery: 4), .shortBreak, "short break suggested")
    }
    engine.start(.focus, durations: durations, now: t0)
    _ = engine.tick(now: t0.addingTimeInterval(1500))
    expect(engine.cycleCompleted, 4, "four completed")
    expect(engine.suggestedNextPhase(longBreakEvery: 4), .longBreak, "long break suggested")
    engine.start(.longBreak, durations: durations, now: t0)
    expect(engine.cycleCompleted, 0, "cycle cleared on long break start")

    // Pause and resume preserve remaining time.
    engine = PomodoroEngine()
    engine.start(.focus, durations: durations, now: t0)
    engine.pause(now: t0.addingTimeInterval(10))
    expect(engine.state, .paused(phase: .focus, remaining: 1490, total: 1500), "paused state")
    let resumeAt = t0.addingTimeInterval(100)
    engine.resume(now: resumeAt)
    expect(engine.remaining(now: resumeAt), 1490, "remaining preserved across pause")
    expect(engine.tick(now: resumeAt.addingTimeInterval(1489.5)) == nil, true, "still running near end")
    expectTrue(engine.tick(now: resumeAt.addingTimeInterval(1490)) != nil, "completes at end")

    // Session start survives pauses.
    engine = PomodoroEngine()
    engine.start(.focus, durations: durations, now: t0)
    engine.pause(now: t0.addingTimeInterval(5))
    engine.resume(now: t0.addingTimeInterval(60))
    let pausedEvent = engine.tick(now: t0.addingTimeInterval(60 + 1495))
    expect(pausedEvent?.startedAt, t0, "startedAt stable across pause")

    // Skip focus: starts short break, no cycle credit.
    engine = PomodoroEngine()
    engine.start(.focus, durations: durations, now: t0)
    engine.skip(durations: durations, longBreakEvery: 4, now: t0.addingTimeInterval(60))
    expect(engine.phase, .shortBreak, "skip focus goes to break")
    expect(engine.cycleCompleted, 0, "skipped focus not counted")
    expect(engine.remaining(now: t0.addingTimeInterval(60)), 300, "break duration after skip")

    // Skip break: back to focus.
    engine = PomodoroEngine()
    engine.start(.shortBreak, durations: durations, now: t0)
    engine.skip(durations: durations, longBreakEvery: 4, now: t0.addingTimeInterval(30))
    expect(engine.phase, .focus, "skip break goes to focus")
    expect(engine.remaining(now: t0.addingTimeInterval(30)), 1500, "focus duration after skip")

    // Reset: full restart — idle, cycle cleared, suggestion back to focus.
    engine = PomodoroEngine()
    engine.start(.focus, durations: durations, now: t0)
    _ = engine.tick(now: t0.addingTimeInterval(1500))
    engine.start(.shortBreak, durations: durations, now: t0)
    engine.reset()
    expect(engine.state, .idle, "reset to idle")
    expect(engine.cycleCompleted, 0, "cycle cleared after reset")
    expect(engine.suggestedNextPhase(longBreakEvery: 4), .focus, "suggestion after reset")

    // Progress is monotonic.
    engine = PomodoroEngine()
    engine.start(.focus, durations: durations, now: t0)
    var last = 0.0
    var monotonic = true
    var offset = 0.0
    while offset <= 1500 {
        let p = engine.progress(now: t0.addingTimeInterval(offset))
        if p < last || p > 1 { monotonic = false }
        last = p
        offset += 75
    }
    expectTrue(monotonic, "progress monotonic")
    expect(engine.progress(now: t0.addingTimeInterval(1500)), 1, "progress reaches 1")
}

func runTaskChecks() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeTask(
        _ title: String, priority: TaskItem.Priority, createdAt: Date, isDone: Bool = false,
        doneAt: Date? = nil
    ) -> TaskItem {
        TaskItem(title: title, priority: priority, isDone: isDone, createdAt: createdAt, doneAt: doneAt)
    }

    // Open tasks sort by priority, then age.
    let a = makeTask("old low", priority: .low, createdAt: t0)
    let b = makeTask("new high", priority: .high, createdAt: t0.addingTimeInterval(5))
    let c = makeTask("old high", priority: .high, createdAt: t0)
    let d = makeTask("medium", priority: .medium, createdAt: t0.addingTimeInterval(2))
    expect(
        TaskListLogic.visible([a, b, c, d], now: t0.addingTimeInterval(10)).map(\.title),
        ["old high", "new high", "medium", "old low"], "open task ordering")

    // Completed task stays visible during the grace window, then disappears.
    let done = makeTask(
        "done", priority: .high, createdAt: t0, isDone: true, doneAt: t0.addingTimeInterval(100))
    expect(
        TaskListLogic.visible([done], now: t0.addingTimeInterval(103)).map(\.title),
        ["done"], "done visible during grace")
    expect(
        TaskListLogic.visible([done], now: t0.addingTimeInterval(106)).isEmpty, true,
        "done hidden after grace")

    // Session completion query includes tasks whose grace has passed.
    let early = makeTask(
        "before session", priority: .low, createdAt: t0, isDone: true, doneAt: t0.addingTimeInterval(10))
    let within = makeTask(
        "during session", priority: .low, createdAt: t0, isDone: true, doneAt: t0.addingTimeInterval(50))
    let open = makeTask("still open", priority: .high, createdAt: t0)
    expect(
        TaskListLogic.completed(
            [early, within, open], since: t0.addingTimeInterval(30), until: t0.addingTimeInterval(200)
        ).map(\.title),
        ["during session"], "completed since")

    expect(TaskListLogic.openCount([a, early]), 1, "open count")

    // Priority ordering follows raw values.
    expect(TaskItem.Priority.high > .medium, true, "high above medium")
    expect(TaskItem.Priority.medium > .low, true, "medium above low")
}

func runFormattingChecks() {
    expect(TimeFormatting.clock(0), "00:00", "zero")
    expect(TimeFormatting.clock(1500), "25:00", "25 minutes")
    expect(TimeFormatting.clock(59), "00:59", "59 seconds")
    expect(TimeFormatting.clock(1499.2), "25:00", "rounds up")
    expect(TimeFormatting.clock(0.4), "00:01", "rounds up small")
    expect(TimeFormatting.clock(3600), "1:00:00", "one hour")
    expect(TimeFormatting.clock(7325), "2:02:05", "hours and minutes")
}

runEngineChecks()
runTaskChecks()
runFormattingChecks()

if failures == 0 {
    print("All checks passed.")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
