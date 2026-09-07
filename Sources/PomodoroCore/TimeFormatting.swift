import Foundation

public enum TimeFormatting {
    /// Formats a countdown as mm:ss (or h:mm:ss above an hour), rounding up so a
    /// fresh 25-minute timer reads 25:00 and only reaches 00:00 when it is done.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
