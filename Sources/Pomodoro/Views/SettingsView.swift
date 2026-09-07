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

            Section("Menu Bar") {
                Picker("Icon", selection: $settings.iconMode) {
                    ForEach(MenuBarIconMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Menu bar icon style")
            }

            Section {
                Picker("Shortcut opens", selection: $settings.quickAddOpens) {
                    Text("Floating panel").tag(QuickAddTarget.floatingPanel)
                    Text("Menu bar panel").tag(QuickAddTarget.menuBarPanel)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("What the global quick-add shortcut opens")
            } header: {
                Text("Quick Add")
            } footer: {
                Text("Add a task from anywhere by pressing ⌘⇧P.")
            }

            Section("General") {
                Toggle("Play a sound when a timer ends", isOn: $settings.soundEnabled)
                Toggle("Open Pomodoro at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
