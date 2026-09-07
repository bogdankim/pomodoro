import PomodoroCore
import SwiftUI

/// The brief HUD shown when a timer ends: what finished, which tasks were
/// completed during the session, and the next action.
struct SummaryView: View {
    let model: AppModel
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if let summary = model.summary {
                content(for: summary)
            }
        }
        .frame(width: 400, alignment: .leading)
    }

    private func content(for summary: SessionSummary) -> some View {
        let tint = summary.endedPhase.tint
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(
                    systemName: summary.endedPhase == .focus ? "checkmark.circle.fill" : "cup.and.saucer.fill"
                )
                .font(.system(size: 21))
                .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: summary))
                        .font(.headline)
                    Text(subtitle(for: summary))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !summary.completedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Completed during this session")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(summary.completedTasks.prefix(3)) { task in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                            Text(task.title)
                                .font(.callout)
                                .lineLimit(1)
                                .strikethrough(color: .secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    moreFooter(count: summary.completedTasks.count, shown: 3)
                }
            }

            if !summary.openTasks.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Open tasks")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(summary.openTasks.prefix(3)) { task in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Text(task.title)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Circle()
                                .fill(task.priority.tint)
                                .frame(width: 7, height: 7)
                                .help("\(task.priority.displayName) priority")
                        }
                    }
                    moreFooter(count: summary.openTasks.count, shown: 3)
                }
            }

            HStack(spacing: 10) {
                if !engineStartedAutomatically(after: summary) {
                    Button {
                        onStart()
                    } label: {
                        Label("Start \(nextPhase(after: summary).displayName)", systemImage: "play.fill")
                            .frame(minWidth: 104)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(nextPhase(after: summary).tint)
                    .keyboardShortcut(.defaultAction)
                }

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.glass)

                Spacer()
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func moreFooter(count: Int, shown: Int) -> some View {
        if count > shown {
            Text("+ \(count - shown) more")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private func title(for summary: SessionSummary) -> String {
        summary.endedPhase == .focus ? "Focus session complete" : "Break finished"
    }

    private func subtitle(for summary: SessionSummary) -> String {
        var parts: [String] = []
        parts.append(TimeFormatting.clock(summary.total).lowercased())
        if summary.completedTasks.isEmpty {
            if summary.endedPhase == .focus && summary.openCount > 0 {
                parts.append("\(summary.openCount) tasks open")
            }
        } else {
            let count = summary.completedTasks.count
            let noun = count == 1 ? "task" : "tasks"
            parts.append("\(count) \(noun) done")
        }
        return parts.joined(separator: " · ")
    }

    private func nextPhase(after summary: SessionSummary) -> PhaseKind {
        summary.endedPhase.isBreak ? .focus : (model.phase == nil ? model.suggestedPhase : model.phase!)
    }

    private func engineStartedAutomatically(after summary: SessionSummary) -> Bool {
        model.isRunning
    }
}
