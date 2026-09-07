import AppKit
import PomodoroCore
import SwiftUI

enum SoundPlayer {
    /// Plays a named system sound (Basso, Glass, Ping, Pop, ...).
    static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}

extension Notification.Name {
    /// Posted when the popover should focus its quick-add field.
    static let focusQuickAddField = Notification.Name("Pomodoro.focusQuickAddField")
}

/// Blurs, fades, and lifts slightly; used when a completed task leaves the list.
struct BlurOutModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static var blurOut: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .opacity,
            removal: .modifier(
                active: BlurOutModifier(radius: 8, opacity: 0, offsetY: -4),
                identity: BlurOutModifier(radius: 0, opacity: 1, offsetY: 0)
            )
        )
    }
}

extension PhaseKind {
    /// Phase color from the system palette, mirroring Apple's Timer app (orange focus).
    var tint: Color {
        switch self {
        case .focus: .orange
        case .shortBreak: .green
        case .longBreak: .indigo
        }
    }

    var symbolName: String {
        switch self {
        case .focus: "timer"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "cup.and.saucer.fill"
        }
    }
}

extension TaskItem.Priority {
    /// Priority colors follow the Reminders convention: blue, orange, red.
    var tint: Color {
        switch self {
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }

    /// The next priority in Tab order: low, medium, high, wrapping to low.
    var next: TaskItem.Priority {
        switch self {
        case .low: .medium
        case .medium: .high
        case .high: .low
        }
    }
}
