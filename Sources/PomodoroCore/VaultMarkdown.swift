import Foundation

/// Pure markdown layer for daily-note capture: line format, section rewriting,
/// and rendering entries into full note text.
///
/// The formats mirror Obsidian's own conventions — GFM checkboxes with an
/// optional completion date, exactly like the Tasks plugin's done format — so
/// the notes look native in Obsidian and stay queryable by its plugins.
public enum VaultMarkdown {

    // MARK: - Line format

    public static let taskPrefix = "- [ ] "
    public static let donePrefix = "- [x] "

    /// Renders one entry as a markdown list line.
    public static func line(
        for entry: VaultEntry, doneOn: Date?, uses24Hour: Bool = true, dayBasis: Date = Date()
    ) -> String {
        let completion: String
        if entry.isDone, let doneOn {
            completion = " ✅ \(doneDateFormatter.string(from: doneOn))"
        } else {
            completion = ""
        }
        switch entry.kind {
        case .task:
            let checkbox = entry.isDone ? donePrefix : taskPrefix
            let tag = entry.priority.map { " \($0.vaultTag)" } ?? ""
            return "\(checkbox)\(entry.title)\(tag)\(completion)"
        case .note:
            // The timestamp is decoration, never part of the title: plain
            // foreign lines (no createdAt) render bare even after a format
            // switch, so the format toggle never manufactures identity.
            guard let created = entry.createdAt else {
                return "- \(entry.title)"
            }
            let stamp = NoteTimestamp.render(
                created, uses24Hour: uses24Hour, calendar: Self.noteCalendar)
            return "- \(stamp) \(entry.title)"
        }
    }

    /// Parses a list line back into an entry, keeping the completion stamp's
    /// date on the entry (`doneOn`) so callers can carry it through. Titles
    /// come back clean: stamps and priority tags are consumed into fields.
    /// Returns nil for anything that is not a checkbox task or a plain list
    /// note; foreign lines are left untouched by rewriting.
    public static func entry(
        from line: String, createdAt: Date?, doneOn: inout Date?
    ) -> VaultEntry? {
        for prefix in [donePrefix, uppercasedDonePrefix, taskPrefix] {
            guard line.hasPrefix(prefix) else { continue }
            let payload = String(line.dropFirst(prefix.count))
            let (title, priority) = Self.titleAndPriority(in: payload)
            let isDone = prefix != taskPrefix
            doneOn = isDone ? completionDate(in: payload) : nil
            return VaultEntry(
                kind: .task, title: title, isDone: isDone, priority: priority, createdAt: createdAt)
        }
        if line.hasPrefix(notePrefix) {
            let text = String(line.dropFirst(notePrefix.count)).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return VaultEntry(kind: .note, title: text, createdAt: createdAt)
        }
        return nil
    }

    /// The trailing `✅ yyyy-MM-dd` completion stamp's date, Tasks-plugin
    /// style. Absent on open tasks and notes.
    static func completionDate(in title: String) -> Date? {
        guard
            let match = title.range(of: completionStampPattern, options: .regularExpression),
            let date = doneDateFormatter.date(
                from: String(title[match]).dropFirst(2).trimmingCharacters(in: .whitespaces))
        else { return nil }
        return date
    }

    static func strippingCompletionDate(from title: String) -> String {
        guard let range = title.range(of: completionStampPattern, options: .regularExpression) else {
            return title
        }
        let before = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let after = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        switch (before.isEmpty, after.isEmpty) {
        case (true, true): return ""
        case (true, false): return String(after)
        case (false, true): return String(before)
        case (false, false): return before + " " + after
        }
    }

    private static let notePrefix = "- "
    private static let uppercasedDonePrefix = "- [X] "
    private static let completionStampPattern = "✅ \\d{4}-\\d{2}-\\d{2}\\s*$"

    /// The single calendar used everywhere timestamps are rendered and
    /// reconstructed, so a stamp round-trips to the same time of day.
    public static let noteCalendar = Calendar.current

    private static let doneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func titleAndPriority(in payload: String) -> (String, TaskItem.Priority?) {
        // The completion stamp may sit before or after the priority tag;
        // strip the stamp first so the tag is at the string's end.
        var title = strippingCompletionDate(from: payload)
        var priority: TaskItem.Priority?
        if let range = title.range(of: #"\s#p[1-3]\s*$"#, options: .regularExpression) {
            priority = TaskItem.Priority(vaultTag: String(title[title.index(after: range.lowerBound)...]))
            title = String(title[..<range.lowerBound])
        }
        return (title.trimmingCharacters(in: .whitespaces), priority)
    }

    // MARK: - Sections

    /// The headings the app owns inside a daily note. The QuickAdd capture in
    /// the user's vault already targets `### Notes`, so both spellings of the
    /// Tasks heading the vault might use are accepted on read.
    public static let tasksHeadings = ["Tasks", "## Tasks", "### Tasks"]
    public static let notesHeadings = ["Notes", "## Notes", "### Notes"]
    public static let taskSectionHeading = "### Tasks"
    public static let noteSectionHeading = "### Notes"

    /// Applies a set of entries to note text: the `### Tasks` and `### Notes`
    /// sections are replaced with the rendered lines; every other line —
    /// headings, prose, foreign list items — is preserved byte for byte.
    /// Missing sections are appended in canonical order (Tasks, then Notes).
    /// `dayBasis` anchors reconstructed note stamps to the note's day, and
    /// `uses24Hour` selects the stamp format. Idempotent: applying the same
    /// entries twice leaves the text unchanged.
    public static func applying(
        entries: [VaultEntry], doneDates: [String: Date], to text: String,
        uses24Hour: Bool = true, dayBasis: Date = Date()
    ) -> String {
        let tasks = entries.filter { $0.kind == .task }
        let notes = entries.filter { $0.kind == .note }
        var result = replacingSection(
            heading: taskSectionHeading,
            lines: tasks.map { entry in
                line(for: entry, doneOn: doneDates[entry.mergeKey])
            }, in: text)

        result = replacingSection(
            heading: noteSectionHeading,
            lines: notes.map { entry in
                line(for: entry, doneOn: nil, uses24Hour: uses24Hour, dayBasis: dayBasis)
            }, in: result)
        return result
    }

    /// Replaces the body of one `###` section, keeping everything outside it.
    /// A section runs from its heading to the next heading or horizontal
    /// rule; a missing section is created at the end of the note.
    static func replacingSection(heading: String, lines: [String], in text: String) -> String {
        var lines_out = textComponents(text)
        var headingIndex: Int?
        var sectionEnd: Int?

        for (index, existing) in lines_out.enumerated() {
            if existing == heading {
                headingIndex = index
            } else if headingIndex != nil, isStructural(existing) {
                sectionEnd = index
                break
            }
        }
        let end = sectionEnd ?? lines_out.count

        guard let headingIndex else {
            if !lines_out.isEmpty && lines_out.last != "" { lines_out.append("") }
            lines_out.append(heading)
            lines_out.append(contentsOf: lines)
            return joined(lines_out)
        }

        let trailingBlanks = lines_out[headingIndex + 1..<end].reversed().prefix { $0.isEmpty }.count
        let bodyEnd = end - trailingBlanks
        let body = lines_out[(headingIndex + 1)..<bodyEnd]

        // Trailing section blanks belong to the layout, not the body: keep
        // them so notes edited by hand keep their breathing room.
        var updated = Array(lines_out[...headingIndex])
        updated.append(contentsOf: lines)
        updated.append(contentsOf: body.isEmpty ? [] : [""])
        updated.append(contentsOf: lines_out[end...])
        return joined(updated)
    }

    /// Splits note text into lines the way editors do, tolerating CRLF.
    static func textComponents(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Lines that bound a section: headings and horizontal rules. List
    /// content, prose, and blanks belong to the section they follow.
    static func isStructural(_ line: String) -> Bool {
        line.hasPrefix("#")
            || (line.count >= 3 && line.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" })
    }

    private static func joined(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    // MARK: - Parsing a note

    /// The entries found under the Tasks and Notes sections of a note, in
    /// document order. `doneDates` carries each task's `✅` stamp, keyed by
    /// merge key, so completion dates survive the round trip. Note lines
    /// starting with a timestamp get that time back as `createdAt` (the day
    /// comes from `dayBasis`); their titles are stamp-free.
    public static func entries(
        in text: String, dayBasis: Date = Date()
    ) -> (entries: [VaultEntry], doneDates: [String: Date]) {
        var entries: [VaultEntry] = []
        var doneDates: [String: Date] = [:]
        var section: VaultEntry.Kind?

        for rawLine in textComponents(text) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("###") {
                let normalized = line.trimmingCharacters(
                    in: CharacterSet(charactersIn: "#").union(.whitespaces))
                section =
                    tasksHeadings.contains(normalized)
                    ? .task
                    : notesHeadings.contains(normalized) ? .note : nil
                continue
            }
            guard section != nil else { continue }
            var doneOn: Date?

            if section == .note {
                // A leading stamp becomes the note's createdAt, with the
                // title stored stamp-free so the merge key is stable across
                // 12h/24h formatting. Stampless lines stay timestamp-less.
                var stampedAt: Date?
                if let entry = VaultMarkdown.entry(from: line, createdAt: nil, doneOn: &stampedAt) {
                    var stamped = entry
                    if let stamp = NoteTimestamp.extract(from: stamped.title, dayBasis: dayBasis) {
                        stamped.createdAt = stamp.date
                        stamped.title = stamp.text
                    }
                    entries.append(stamped)
                }
                continue
            }

            guard let entry = entry(from: line, createdAt: .init(), doneOn: &doneOn) else { continue }
            entries.append(entry)
            if let doneOn {
                // Keyed on the parsed (already stripped) title — the same
                // merge key consumers use when they look the date back up.
                doneDates[TaskItem(entry: entry).vaultEntry.mergeKey] = doneOn
            }
        }
        return (entries, doneDates)
    }
}
