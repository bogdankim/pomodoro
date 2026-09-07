import PomodoroCore
import SwiftUI

/// The popover shown when the menu bar item is clicked: timer, controls, and
/// the task list. The system supplies the Liquid Glass panel background; this
/// content adds no material of its own.
struct PopoverContent: View {
    let model: AppModel
    let tasks: TaskListModel
    let settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            TimerSection(model: model, settings: settings)
            ControlsRow(model: model)

            Divider()
                .padding(.vertical, 12)

            QuickAddField(tasks: tasks)
                .padding(.bottom, 8)

            TaskListSection(tasks: tasks)

            Divider()
                .padding(.top, 12)

            FooterBar(model: model, tasks: tasks)
        }
        .frame(width: 300)
    }
}

// MARK: - Timer

private struct TimerSection: View {
    let model: AppModel
    let settings: SettingsStore

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                TimelineView(.animation) { context in
                    TimerRing(fill: ringFill(at: context.date), tint: currentPhase.tint)
                }

                VStack(spacing: 1) {
                    Text(model.timeText)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: model.displaySeconds)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(caption), \(model.timeText) remaining")

            SessionDots(
                completed: model.cycleCompleted,
                every: settings.longBreakEvery
            )
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var caption: String {
        if model.isPaused { return "Paused" }
        return (model.phase ?? model.suggestedPhase).displayName
    }

    private var currentPhase: PhaseKind {
        model.phase ?? model.suggestedPhase
    }

    /// Focus is a capacity that drains from full; breaks fill up as they elapse.
    private func ringFill(at date: Date) -> Double {
        let elapsed = model.engine.progress(now: date)
        return currentPhase.isBreak ? elapsed : 1 - elapsed
    }
}

struct TimerRing: View {
    let fill: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(fill, 0.004))
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 0.25), value: fill)
    }
}

private struct SessionDots: View {
    let completed: Int
    let every: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, every), id: \.self) { index in
                Circle()
                    .fill(index < completed ? Color.orange : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(every) focus sessions completed in this cycle")
    }
}

// MARK: - Controls

private struct ControlsRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            primaryButton
            if model.showPhaseControls {
                Button {
                    model.skip()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 44, height: 24)
                }
                .buttonStyle(.glass)
                .help("Skip to the next phase")

                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 44, height: 24)
                }
                .buttonStyle(.glass)
                .help("Reset the timer")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var primaryButton: some View {
        Button {
            model.toggleRun()
        } label: {
            Label(primaryTitle, systemImage: primarySymbol)
                .frame(minWidth: 96, minHeight: 24)
        }
        .buttonStyle(.glassProminent)
        .tint((model.phase ?? model.suggestedPhase).tint)
        .help(primaryTitle)
    }

    private var primaryTitle: String {
        if model.isRunning { return "Pause" }
        if model.isPaused { return "Resume" }
        return "Start \(model.suggestedPhase.displayName)"
    }

    private var primarySymbol: String {
        model.isRunning ? "pause.fill" : "play.fill"
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let model: AppModel
    let tasks: TaskListModel

    var body: some View {
        HStack(spacing: 14) {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit Pomodoro")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footerText: String {
        if model.focusSessionsToday > 0 {
            let sessions = model.focusSessionsToday == 1 ? "session" : "sessions"
            return "\(model.focusSessionsToday) focus \(sessions) today"
        }
        return "Press ⌘⇧P to add a task from anywhere"
    }
}
