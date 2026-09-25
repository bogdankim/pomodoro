import PomodoroCore
import ServiceManagement
import SwiftUI

/// Where the global quick-add shortcut sends you.
enum QuickAddTarget: String, CaseIterable, Codable {
    case floatingPanel
    case menuBarPanel
}

/// How the status item renders while a phase is active.
enum MenuBarIconMode: String, CaseIterable, Codable {
    case progressRing
    case timer
    case combined

    var displayName: String {
        switch self {
        case .progressRing: "Progress ring"
        case .timer: "Time"
        case .combined: "Ring and time"
        }
    }
}

/// App settings backed by UserDefaults. Stored properties write through on change
/// so every SwiftUI view observing them updates.
@MainActor
@Observable
final class SettingsStore {

    private let defaults: UserDefaults

    var focusMinutes: Int {
        didSet {
            defaults.set(focusMinutes, forKey: "focusMinutes")
            onChange?()
        }
    }
    var shortBreakMinutes: Int {
        didSet {
            defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes")
            onChange?()
        }
    }
    var longBreakMinutes: Int {
        didSet {
            defaults.set(longBreakMinutes, forKey: "longBreakMinutes")
            onChange?()
        }
    }
    var longBreakEvery: Int {
        didSet {
            defaults.set(longBreakEvery, forKey: "longBreakEvery")
            onChange?()
        }
    }
    var autoStartBreaks: Bool {
        didSet {
            defaults.set(autoStartBreaks, forKey: "autoStartBreaks")
            onChange?()
        }
    }
    var autoStartFocus: Bool {
        didSet {
            defaults.set(autoStartFocus, forKey: "autoStartFocus")
            onChange?()
        }
    }
    var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: "soundEnabled")
            onChange?()
        }
    }
    var iconMode: MenuBarIconMode {
        didSet {
            defaults.set(iconMode.rawValue, forKey: "iconMode")
            onChange?()
        }
    }

    var quickAddOpens: QuickAddTarget {
        didSet {
            defaults.set(quickAddOpens.rawValue, forKey: "quickAddOpens")
            onChange?()
        }
    }

    /// The global quick-add shortcut, remappable in Settings.
    var quickAddShortcut: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(quickAddShortcut) {
                defaults.set(data, forKey: "quickAddShortcut")
            }
            onChange?()
        }
    }

    /// Whether the timer lives in the menu bar at all. When off, the status
    /// item is removed; global shortcuts keep working so Settings stays
    /// reachable through the capture panel.
    var showInMenuBar: Bool {
        didSet {
            defaults.set(showInMenuBar, forKey: "showInMenuBar")
            onChange?()
        }
    }

    /// Called on every settings change so non-SwiftUI surfaces (the status item)
    /// can re-render.
    var onChange: (() -> Void)?

    /// Mirrors SMAppService state; reverts the toggle if registration fails.
    var launchAtLogin: Bool = false {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = oldValue
            }
        }
    }

    var durations: PhaseDurations {
        PhaseDurations(
            focus: Double(focusMinutes * 60),
            shortBreak: Double(shortBreakMinutes * 60),
            longBreak: Double(longBreakMinutes * 60)
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "focusMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "longBreakEvery": 4,
            "autoStartBreaks": false,
            "autoStartFocus": false,
            "soundEnabled": true,
            "iconMode": MenuBarIconMode.combined.rawValue,
            "quickAddOpens": QuickAddTarget.menuBarPanel.rawValue,
            "showInMenuBar": true,
        ])
        focusMinutes = defaults.integer(forKey: "focusMinutes")
        shortBreakMinutes = defaults.integer(forKey: "shortBreakMinutes")
        longBreakMinutes = defaults.integer(forKey: "longBreakMinutes")
        longBreakEvery = defaults.integer(forKey: "longBreakEvery")
        autoStartBreaks = defaults.bool(forKey: "autoStartBreaks")
        autoStartFocus = defaults.bool(forKey: "autoStartFocus")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        iconMode = (MenuBarIconMode(rawValue: defaults.string(forKey: "iconMode") ?? "")) ?? .combined
        quickAddOpens =
            (QuickAddTarget(rawValue: defaults.string(forKey: "quickAddOpens") ?? "")) ?? .menuBarPanel
        if let data = defaults.data(forKey: "quickAddShortcut"),
            let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
        {
            quickAddShortcut = combo
        } else {
            quickAddShortcut = .default
        }
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
