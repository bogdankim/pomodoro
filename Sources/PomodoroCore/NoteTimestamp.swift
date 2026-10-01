import Foundation

/// The leading time stamp on note lines, in either the 24-hour (`14:05`) or
/// 12-hour (`2:05 PM`) form. Rendering and parsing are hand-rolled so both
/// formats are exact and free of locale drift; parsing validates ranges and
/// returns nil for anything that only looks like a time.
public enum NoteTimestamp {

    /// Renders the time-of-day of `date` in the given format.
    public static func render(_ date: Date, uses24Hour: Bool, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        if uses24Hour {
            return String(format: "%02d:%02d", hour, minute)
        }
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let meridiem = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, minute, meridiem)
    }

    /// A leading stamp found in a note line's payload: the reconstructed
    /// full date (day of `dayBasis` + parsed time) and the text after it.
    /// Nil when the payload does not start with a valid stamp.
    public static func extract(from payload: String, dayBasis: Date, calendar: Calendar = .current)
        -> (date: Date, text: String)?
    {
        guard let match = payload.range(of: stampPattern, options: [.anchored, .regularExpression]) else {
            return nil
        }
        let token = String(payload[match])
        guard let date = parse(token, dayBasis: dayBasis, calendar: calendar) else { return nil }
        let text = String(payload[match.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (date, text)
    }

    /// Parses a rendered stamp against the note's day. Validation is strict:
    /// `25:00` and `12:75` are text, not times.
    static func parse(_ token: String, dayBasis: Date, calendar: Calendar = .current) -> Date? {
        let parts = token.split(separator: " ")
        let timeParts = parts[0].split(separator: ":")
        guard timeParts.count == 2, let hour = Int(timeParts[0]), let minute = Int(timeParts[1]),
            minute >= 0, minute <= 59
        else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: dayBasis)
        if parts.count == 2 {
            let meridiem = parts[1].uppercased()
            guard meridiem == "AM" || meridiem == "PM", hour >= 1, hour <= 12 else { return nil }
            components.hour = hour == 12 ? 0 : hour + (meridiem == "PM" ? 12 : 0)
        } else {
            guard hour >= 0, hour <= 23 else { return nil }
            components.hour = hour
        }
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Matches `14:05`, `2:05 PM`, and `2:05 pm`, only when actual text
    /// follows. The trailing requirement is a lookahead, so the match itself
    /// is exactly the stamp and the title after it is left intact.
    static let stampPattern = "^\\d{1,2}:\\d{2}(\\s?(AM|PM))?(?=\\s+\\S)"
}
