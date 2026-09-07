import Carbon.HIToolbox
import SwiftUI

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let settings = SettingsStore()
    let tasks = TaskListModel()

    private(set) lazy var model = AppModel(settings: settings, tasks: tasks)

    private(set) lazy var statusItem = StatusItemController(
        model: model,
        settings: settings,
        content: PopoverContent(model: model, tasks: tasks, settings: settings)
    )

    private(set) lazy var quickAddPanel: FloatingPanelController<QuickAddPanelView> = FloatingPanelController(
        minimumWidth: 520
    ) {
        QuickAddPanelView(
            onCommit: { [weak self] title, priority in
                guard let self else { return }
                tasks.add(title: title, priority: priority)
                quickAddPanel.hide()
            },
            onCancel: { [weak self] in
                self?.quickAddPanel.hide()
            }
        )
    }

    private(set) lazy var summaryPanel: FloatingPanelController<SummaryView> = FloatingPanelController(
        minimumWidth: 400,
        becomesKeyOnShow: false
    ) {
        SummaryView(
            model: model,
            onStart: { [weak self] in
                guard let self else { return }
                model.startSuggested()
                summaryPanel.hide()
            },
            onDismiss: { [weak self] in
                guard let self else { return }
                model.dismissSummary()
                summaryPanel.hide()
            }
        )
    }

    private(set) lazy var hotKey = GlobalHotKey(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(cmdKey | shiftKey)
    ) { [weak self] in
        self?.quickAdd()
    }

    /// The global shortcut opens either the floating capture panel or the menu
    /// bar popover with its input focused, per the Quick Add setting.
    private func quickAdd() {
        switch settings.quickAddOpens {
        case .floatingPanel:
            quickAddPanel.toggle()
        case .menuBarPanel:
            statusItem.togglePopover(focusQuickAdd: true)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = model
        _ = statusItem
        _ = quickAddPanel
        _ = summaryPanel
        _ = hotKey
        model.onSummaryAvailable = { [weak self] in
            self?.summaryPanel.show()
        }
        model.onStateChange = { [weak self] in
            self?.statusItem.refreshIcon()
        }
        settings.onChange = { [weak self] in
            guard let self else { return }
            statusItem.refreshIcon()
            model.refreshCountdownDisplay()
        }
    }
}
