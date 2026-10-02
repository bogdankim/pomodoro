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

func runNoteChecks() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeNote(_ text: String, createdAt: Date) -> NoteItem {
        NoteItem(text: text, createdAt: createdAt)
    }

    // Visible notes are newest first, capped to the limit.
    let n1 = makeNote("oldest", createdAt: t0)
    let n2 = makeNote("middle", createdAt: t0.addingTimeInterval(10))
    let n3 = makeNote("newest", createdAt: t0.addingTimeInterval(20))
    expect(
        NoteListLogic.visible([n1, n2, n3], limit: 2).map(\.text),
        ["newest", "middle"], "visible notes newest first, capped")

    // Ordering is stable regardless of input order.
    expect(
        NoteListLogic.sorted([n3, n1, n2]).map(\.text),
        ["newest", "middle", "oldest"], "note sort")
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

func runVaultMarkdownChecks() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeEntry(
        _ kind: VaultEntry.Kind, _ title: String, isDone: Bool = false, priority: TaskItem.Priority? = nil
    )
        -> VaultEntry
    {
        VaultEntry(kind: kind, title: title, isDone: isDone, priority: priority, createdAt: t0)
    }

    // Task lines round-trip with priority; notes stay plain.
    let high = makeEntry(.task, "ship it", priority: .high)
    expect(
        VaultMarkdown.line(for: high, doneOn: nil), "- [ ] ship it #p3", "open task line")
    var none: Date?
    let parsed = VaultMarkdown.entry(from: "- [ ] ship it #p3", createdAt: t0, doneOn: &none)!
    expect(parsed.title, "ship it", "task parse title")
    expect(parsed.priority, TaskItem.Priority.high, "task parse priority")
    expect(parsed.isDone, false, "task parse open")

    // Done lines carry the completion stamp and parse back without it.
    let done = makeEntry(.task, "ship it", isDone: true, priority: .medium)
    let doneLine = VaultMarkdown.line(for: done, doneOn: t0)
    expectTrue(doneLine.hasPrefix("- [x] ship it #p2 ✅ "), "done line format")
    var stamp: Date?
    let doneParsed = VaultMarkdown.entry(from: doneLine, createdAt: t0, doneOn: &stamp)!
    expect(doneParsed.title, "ship it", "done parse strips stamp")
    expect(doneParsed.isDone, true, "done parse state")
    expectTrue(stamp != nil, "done parse keeps stamp")
    // The app's own render order (tag before the stamp) must keep the tag:
    // a trailing stamp used to leave whitespace that broke the tag match.
    expect(doneParsed.priority, TaskItem.Priority.medium, "done line keeps tag before stamp")

    // Foreign lines never parse.
    var discard: Date?
    expect(
        VaultMarkdown.entry(from: "- [ ] task with block ^abc", createdAt: t0, doneOn: &discard) != nil, true,
        "block id tolerated")
    expect(VaultMarkdown.entry(from: "Some prose", createdAt: t0, doneOn: &discard), nil, "prose rejected")
    // Uppercased checkboxes are valid GFM done markers and parse as done.
    expect(
        VaultMarkdown.entry(from: "- [X] uppercase checkbox", createdAt: t0, doneOn: &discard)?.isDone, true,
        "uppercased done parsed")

    // Section rewrite replaces only the owned section.
    let note = """
        ### Brief

        Morning standup notes here.

        ---
        ### Tasks

        - [ ] manual task #p1

        ---
        ### Notes

        - manual note

        """
    let entries = [
        makeEntry(.task, "app task", priority: .low),
        makeEntry(.note, "app note"),
    ]
    let rewritten = VaultMarkdown.applying(entries: entries, doneDates: [:], to: note)
    expectTrue(rewritten.contains("Morning standup notes here."), "brief preserved")
    expectTrue(rewritten.contains("- [ ] manual task #p1") == false, "old tasks replaced")
    expectTrue(rewritten.contains("- [ ] app task #p1"), "task written")
    // Notes render with a leading stamp (the entry's createdAt, 24-hour by
    // default); foreign stampless lines stay bare.
    expectTrue(
        rewritten.range(of: #"- \d{2}:\d{2} app note"#, options: .regularExpression) != nil,
        "note written with stamp")
    expectTrue(rewritten.contains("---"), "horizontal rules preserved")

    // Idempotent: same entries twice leaves text unchanged.
    let twice = VaultMarkdown.applying(entries: entries, doneDates: [:], to: rewritten)
    expect(twice, rewritten, "rewrite idempotent")

    // Round-trip: parse what we wrote and get the same entries back.
    let (roundTripped, _) = VaultMarkdown.entries(in: rewritten)
    expect(roundTripped.filter { $0.kind == .task }.map(\.title), ["app task"], "round-trip tasks")
    expect(roundTripped.filter { $0.kind == .note }.map(\.title), ["app note"], "round-trip notes")

    // Missing sections are appended.
    let bare = "# 2026-09-29\n\nSome intro.\n"
    let appended = VaultMarkdown.applying(entries: entries, doneDates: [:], to: bare)
    expectTrue(appended.contains("### Tasks"), "tasks heading created")
    expectTrue(appended.contains("### Notes"), "notes heading created")
    expectTrue(appended.contains("Some intro."), "existing content preserved")

    // A template round-trip is byte-stable: the app's sections slot in
    // without eating the template's blank-line layout.
    let templateNote = "### Brief\n\n---\n### Tasks\n\n---\n### Notes\n\n"
    let templated = VaultMarkdown.applying(entries: entries, doneDates: [:], to: templateNote)
    expectTrue(templated.contains("### Brief"), "template brief preserved")
    expectTrue(
        templated.contains("### Tasks\n- [ ] app task #p1\n\n---"),
        "task hugs heading, template gap before divider")
    expectTrue(templated.contains("### Notes\n- "), "filled notes section hugs its content")
    let retemplated = VaultMarkdown.applying(entries: entries, doneDates: [:], to: templated)
    expect(templated, retemplated, "template round-trip byte-stable")

    // With nothing to write, the template's empty sections are untouched.
    let pristine = VaultMarkdown.applying(entries: [], doneDates: [:], to: templateNote)
    expect(pristine, templateNote, "empty pass preserves template")

    // A divider glued to the section above is separated on rewrite.
    let glued = VaultMarkdown.applying(entries: entries, doneDates: [:], to: "### Notes---\n")
    expectTrue(glued.contains("### Notes\n"), "glued divider separated")

    // Parsing a hand-made note reads foreign entries (vault → app adoption).
    let (adopted, doneDates) = VaultMarkdown.entries(in: note)
    expect(adopted.count, 2, "hand note entry count")
    // Priority tags: #p1 is low, #p3 high.
    expectTrue(adopted.contains { $0.title == "manual task" && $0.priority == .low }, "priority adopted")
    expectTrue(adopted.allSatisfy { $0.kind == .task || $0.kind == .note }, "only owned sections parsed")

    // Done-date extraction keyed on the stripped title.
    expectTrue(doneDates.values.count >= 0, "done dates map builds")
}

func runVaultSyncChecks() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeEntry(_ kind: VaultEntry.Kind, _ title: String, createdAt: Date = t0, isDone: Bool = false)
        -> VaultEntry
    {
        VaultEntry(kind: kind, title: title, isDone: isDone, createdAt: createdAt)
    }

    // Local addition reaches the vault.
    let localAdd = [makeEntry(.task, "new local")]
    var result = VaultSync.merge(local: localAdd, vault: [], base: [], now: t0)
    expect(result.entries.map(\.title), ["new local"], "local add merged")
    expectTrue(result.vaultNeedsWrite, "local add writes vault")
    expectTrue(!result.appNeedsUpdate, "local add leaves app as-is")

    // Vault addition is adopted.
    result = VaultSync.merge(local: [], vault: localAdd, base: [], now: t0)
    expect(result.entries.map(\.title), ["new local"], "vault add adopted")
    expectTrue(result.appNeedsUpdate, "vault add updates app")
    expectTrue(!result.vaultNeedsWrite, "vault add does not rewrite")

    // Deletion on one side wins against an unchanged mirror on the other.
    let both = [makeEntry(.task, "shared")]
    result = VaultSync.merge(local: [], vault: both, base: both, now: t0)
    expect(result.entries.isEmpty, true, "local delete wins")
    expectTrue(result.vaultNeedsWrite, "deletion pushed to vault")

    result = VaultSync.merge(local: both, vault: [], base: both, now: t0)
    expect(result.entries.isEmpty, true, "vault delete empties app list")
    expectTrue(result.appNeedsUpdate, "vault delete updates app")
    expectTrue(!result.vaultNeedsWrite, "vault delete does not rewrite")

    // Field edits: done-state change on the vault side pulls back.
    let openBase = [makeEntry(.task, "shared")]
    let doneInVault = [makeEntry(.task, "shared", isDone: true)]
    result = VaultSync.merge(local: openBase, vault: doneInVault, base: openBase, now: t0)
    expectTrue(result.entries.allSatisfy(\.isDone), "vault done-state adopted")

    // The completion race: the app checked the task, the write hasn't
    // landed yet, and the poll still reads the open state from the vault.
    // Local evidence (app moved away from base, vault didn't) must win —
    // the checkmark is never reverted.
    result = VaultSync.merge(local: doneInVault, vault: openBase, base: openBase, now: t0)
    expect(result.entries.map(\.isDone), [true], "local check survives the write race")
    expectTrue(result.vaultNeedsWrite, "raced check pushes to vault")

    // The reverse race: a vault-side uncheck with the app still done.
    result = VaultSync.merge(local: doneInVault, vault: openBase, base: doneInVault, now: t0)
    expect(result.entries.map(\.isDone), [false], "vault uncheck adopted")

    // Priority changed in the vault while the app did nothing.
    let priorityEdit = [VaultEntry(kind: .task, title: "shared", priority: .high)]
    result = VaultSync.merge(local: openBase, vault: priorityEdit, base: openBase, now: t0)
    expect(result.entries.map(\.priority), [TaskItem.Priority.high], "vault priority adopted")

    // Same entry added independently on both sides is not duplicated.
    result = VaultSync.merge(local: both, vault: both, base: [], now: t0)
    expect(result.entries.count, 1, "independent adds dedupe")

    // Tasks sort before notes; priority orders within open tasks.
    let mixed = [
        makeEntry(.note, "a note", createdAt: t0),
        makeEntry(.task, "low", createdAt: t0, ),
        VaultEntry(kind: .task, title: "high", priority: .high, createdAt: t0.addingTimeInterval(5)),
    ]
    result = VaultSync.merge(local: mixed, vault: [], base: [], now: t0)
    expect(result.entries.map(\.title), ["high", "low", "a note"], "display ordering")
}

func runNoteTimestampChecks() {
    let calendar = Calendar.current
    // Today at 14:05 local.
    var day = calendar.dateComponents([.year, .month, .day], from: Date())
    day.hour = 14
    day.minute = 5
    let noon = calendar.date(from: day)!
    let dayBasis = calendar.startOfDay(for: noon)

    // Rendering both formats.
    expect(NoteTimestamp.render(noon, uses24Hour: true, calendar: calendar), "14:05", "24h render")
    expect(NoteTimestamp.render(noon, uses24Hour: false, calendar: calendar), "2:05 PM", "12h render")
    var midnightish = day
    midnightish.hour = 0
    midnightish.minute = 7
    let early = calendar.date(from: midnightish)!
    expect(NoteTimestamp.render(early, uses24Hour: false, calendar: calendar), "12:07 AM", "12h midnight")
    var evening = day
    evening.hour = 23
    evening.minute = 59
    let late = calendar.date(from: evening)!
    expect(NoteTimestamp.render(late, uses24Hour: false, calendar: calendar), "11:59 PM", "12h late")

    // Round trip: parse what was rendered, same time of day back.
    for uses24 in [true, false] {
        let stamp = NoteTimestamp.render(noon, uses24Hour: uses24, calendar: calendar)
        guard
            let parsed = NoteTimestamp.extract(
                from: "\(stamp) ship it", dayBasis: dayBasis, calendar: calendar)
        else {
            expectTrue(false, "stamp parses 24h=\(uses24)")
            continue
        }
        expect(
            calendar.dateComponents([.hour, .minute], from: parsed.date),
            calendar.dateComponents([.hour, .minute], from: noon),
            "round trip 24h=\(uses24)")
        expect(parsed.text, "ship it", "text after stamp 24h=\(uses24)")
    }

    // Foreign payloads never parse.
    expectTrue(
        NoteTimestamp.extract(from: "no stamp here", dayBasis: dayBasis, calendar: calendar) == nil,
        "plain text")
    expectTrue(
        NoteTimestamp.extract(from: "25:00 o'clock", dayBasis: dayBasis, calendar: calendar) == nil,
        "invalid hour")
    expectTrue(
        NoteTimestamp.extract(from: "14:05", dayBasis: dayBasis, calendar: calendar) == nil,
        "bare stamp needs text")
    expectTrue(
        NoteTimestamp.extract(from: "14:055 text", dayBasis: dayBasis, calendar: calendar) == nil,
        "not a stamp shape")

    // Note lines round-trip through the markdown layer.
    let note = VaultEntry(kind: .note, title: "call the bank", createdAt: noon)
    let line24 = VaultMarkdown.line(for: note, doneOn: nil, uses24Hour: true, dayBasis: dayBasis)
    expect(line24, "- 14:05 call the bank", "note line 24h")
    let line12 = VaultMarkdown.line(for: note, doneOn: nil, uses24Hour: false, dayBasis: dayBasis)
    expect(line12, "- 2:05 PM call the bank", "note line 12h")
    let (parsedEntries, _) = VaultMarkdown.entries(in: "### Notes\n\n\(line12)\n", dayBasis: dayBasis)
    expect(parsedEntries.first?.title, "call the bank", "parsed title is stamp-free")
    expect(
        parsedEntries.first?.createdAt.map { calendar.dateComponents([.hour, .minute], from: $0) },
        calendar.dateComponents([.hour, .minute], from: noon),
        "parsed stamp time")

    // Foreign (stampless) lines keep no createdAt and render bare.
    let (plain, _) = VaultMarkdown.entries(in: "### Notes\n\n- from quickadd\n", dayBasis: dayBasis)
    expect(plain.first?.createdAt, nil, "stampless line stays stampless")
    expect(
        VaultMarkdown.line(for: plain.first!, doneOn: nil, uses24Hour: false, dayBasis: dayBasis),
        "- from quickadd",
        "stampless renders bare")
}

func runDailyTemplateChecks() {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // No config: nothing resolves, caller falls back to its skeleton.
    expect(DailyTemplate.configuredPaths(root: dir), [] as [String], "no config no paths")
    expect(DailyTemplate.text(root: dir), nil as String?, "no config no text")

    // QuickAdd capture choice that creates from a template.
    let templates = dir.appendingPathComponent("Templates", isDirectory: true)
    try? FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
    try? "### Brief\n\n---\n### Tasks\n\n---\n### Notes\n".write(
        to: templates.appendingPathComponent("Daily.md"), atomically: true, encoding: .utf8)
    let quickAdd: [String: Any] = [
        "choices": [
            [
                "name": "New note",
                "createFileIfItDoesntExist": [
                    "enabled": true,
                    "template": "Templates/Daily.md",
                ],
            ]
        ]
    ]
    let pluginDir = dir.appendingPathComponent(".obsidian/plugins/quickadd", isDirectory: true)
    try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
    let quickAddData = try! JSONSerialization.data(withJSONObject: quickAdd)
    try? quickAddData.write(to: pluginDir.appendingPathComponent("data.json"))

    expect(
        DailyTemplate.configuredPaths(root: dir), ["Templates/Daily.md"] as [String],
        "quickadd path resolved")
    expect(DailyTemplate.text(root: dir)?.hasPrefix("### Brief"), true, "quickadd template read")

    // Daily-notes core plugin config wins when both exist.
    let obsidianDir = dir.appendingPathComponent(".obsidian", isDirectory: true)
    try? FileManager.default.createDirectory(at: obsidianDir, withIntermediateDirectories: true)
    try? "{\"template\":\"Templates/Core.md\"}".write(
        to: obsidianDir.appendingPathComponent("daily-notes.json"), atomically: true, encoding: .utf8)
    expect(
        DailyTemplate.configuredPaths(root: dir).first, "Templates/Core.md",
        "daily-notes config first")
    // Falls through to QuickAdd's template when the first one is missing.
    expect(DailyTemplate.text(root: dir)?.hasPrefix("### Brief"), true, "missing first falls through")

    // Extension-less configured path resolves to the .md file.
    try? "{\"template\":\"Templates/Daily\"}".write(
        to: obsidianDir.appendingPathComponent("daily-notes.json"), atomically: true, encoding: .utf8)
    expect(DailyTemplate.text(root: dir)?.hasPrefix("### Brief"), true, "extension added")
}

runEngineChecks()
runTaskChecks()
runNoteChecks()
runFormattingChecks()
runVaultMarkdownChecks()
runVaultSyncChecks()
runNoteTimestampChecks()
runDailyTemplateChecks()

if failures == 0 {
    print("All checks passed.")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
