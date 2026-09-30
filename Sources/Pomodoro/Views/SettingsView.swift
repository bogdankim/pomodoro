import SwiftUI

/// The native Settings window, opened from the gear in the popover footer.
struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Focus duration") {
                    DurationField(minutes: $settings.focusMinutes, range: 1...120, step: 1)
                }
                LabeledContent("Short break") {
                    DurationField(minutes: $settings.shortBreakMinutes, range: 1...30, step: 1)
                }
                LabeledContent("Long break") {
                    DurationField(minutes: $settings.longBreakMinutes, range: 1...60, step: 1)
                }
                LabeledContent("Long break every") {
                    DurationField(
                        minutes: $settings.longBreakEvery, range: 2...8, step: 1, unit: "focus sessions")
                }
                Toggle("Auto-start breaks", isOn: $settings.autoStartBreaks)
                Toggle("Auto-start focus sessions", isOn: $settings.autoStartFocus)
            } header: {
                Text("Timer")
            } footer: {
                Text(
                    "A long break follows the set number of focus sessions. Changes apply to the next phase.")
            }

            Section {
                Toggle("Progress ring", isOn: $settings.showProgressRing)
                    .disabled(
                        settings.tasksOnlyMode
                            || (settings.showProgressRing && !settings.showTime && !settings.showTaskCount))
                Toggle("Time", isOn: $settings.showTime)
                    .disabled(
                        settings.tasksOnlyMode
                            || (!settings.showProgressRing && settings.showTime && !settings.showTaskCount))
                Toggle("Tasks", isOn: $settings.showTaskCount)
                    .disabled(
                        settings.tasksOnlyMode
                            || (!settings.showProgressRing && !settings.showTime && settings.showTaskCount))
            } header: {
                Text("Menu Bar")
            } footer: {
                Text(
                    "Shown while a timer runs; combine them freely, but keep at least one. The task count is the number of open tasks."
                )
            }

            Section {
                Toggle("Tasks only", isOn: $settings.tasksOnlyMode)
            } header: {
                Text("Interface")
            } footer: {
                Text(
                    "Hides the timer everywhere. The popover shows just capture and your lists, and the menu bar item becomes the open-task count."
                )
            }

            Section {
                Toggle("Sync with Obsidian", isOn: $settings.vaultSyncEnabled)
                if settings.vaultSyncEnabled {
                    LabeledContent("Vault folder") {
                        HStack(spacing: 8) {
                            Text(vaultFolderName)
                                .foregroundStyle(settings.vaultPath.isEmpty ? .secondary : .primary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .help(settings.vaultPath)
                            Button("Choose…") { chooseVaultFolder() }
                        }
                    }
                }
            } header: {
                Text("Obsidian")
            } footer: {
                Text(obsidianFooter)
            }

            Section {
                Picker("Shortcut opens", selection: $settings.quickAddOpens) {
                    Text("Floating panel").tag(QuickAddTarget.floatingPanel)
                    Text("Menu bar panel").tag(QuickAddTarget.menuBarPanel)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("What the global quick-add shortcut opens")
                LabeledContent("Shortcut") {
                    HotKeyRecorder(combo: $settings.quickAddShortcut)
                }
            } header: {
                Text("Quick Add")
            } footer: {
                Text(
                    "Add a task from anywhere by pressing \(settings.quickAddShortcut.displayName). Click the shortcut to remap it."
                )
            }

            Section {
                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
            } header: {
                Text("Menu Bar Visibility")
            } footer: {
                Text(
                    "Hides the timer from the menu bar completely. The shortcut keeps working — it opens the capture panel, which is also where Settings remains reachable."
                )
            }

            Section("General") {
                Toggle("Play a sound when a timer ends", isOn: $settings.soundEnabled)
                Toggle("Open Pomodoro at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    private var vaultFolderName: String {
        guard !settings.vaultPath.isEmpty else { return "No folder selected" }
        return URL(fileURLWithPath: settings.vaultPath).lastPathComponent
    }

    private var obsidianFooter: String {
        var message =
            "Writes tasks and notes into today's note under Daily — tasks as checkboxes with a priority tag (#p1–#p3), notes as list items. Edits made in Obsidian sync back here."
        if settings.vaultSyncEnabled && settings.vaultPath.isEmpty {
            message += " Choose a vault folder to begin."
        }
        return message
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the Obsidian vault folder to sync tasks and notes with"
        panel.directoryURL =
            settings.vaultPath.isEmpty
            ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            : URL(fileURLWithPath: settings.vaultPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.vaultPath = url.path
    }
}
