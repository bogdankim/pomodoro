import PomodoroCore
import ServiceManagement
import SwiftUI

/// Where the global quick-add shortcut sends you.
enum QuickAddTarget: String, CaseIterable, Codable {
    case floatingPanel
    case menuBarPanel
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
    /// Which elements the status item shows while a phase is active. All three
    /// are independent; any combination is valid, including none (the idle
    /// timer symbol still appears when no phase runs).
    var showProgressRing: Bool {
        didSet {
            defaults.set(showProgressRing, forKey: "showProgressRing")
            onChange?()
        }
    }
    var showTime: Bool {
        didSet {
            defaults.set(showTime, forKey: "showTime")
            onChange?()
        }
    }
    var showTaskCount: Bool {
        didSet {
            defaults.set(showTaskCount, forKey: "showTaskCount")
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
            "showProgressRing": true,
            "showTime": true,
            "showTaskCount": false,
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
        if let migrated = Self.migrateIconMode(defaults: defaults) {
            showProgressRing = migrated.ring
            showTime = migrated.time
            showTaskCount = migrated.tasks
        } else {
            showProgressRing = defaults.object(forKey: "showProgressRing") as? Bool ?? true
            showTime = defaults.object(forKey: "showTime") as? Bool ?? true
            showTaskCount = defaults.bool(forKey: "showTaskCount")
        }
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

    /// One-time migration from the retired exclusive icon-mode enum: maps the
    /// stored mode onto the element checkboxes. Returns nil when the key is
    /// absent (fresh install) or already migrated (the key is removed after
    /// mapping).
    private static func migrateIconMode(defaults: UserDefaults) -> (ring: Bool, time: Bool, tasks: Bool)? {
        guard let raw = defaults.string(forKey: "iconMode") else { return nil }
        defaults.removeObject(forKey: "iconMode")
        switch raw {
        case "progressRing": return (true, false, false)
        case "timer": return (false, true, false)
        case "combined": return (true, true, false)
        default: return nil
        }
    }
}
