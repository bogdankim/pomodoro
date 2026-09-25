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
    let notes = NoteListModel()

    private(set) lazy var model = AppModel(settings: settings, tasks: tasks)

    private(set) lazy var statusItem = StatusItemController(
        model: model,
        settings: settings,
        tasks: tasks,
        content: PopoverContent(model: model, tasks: tasks, notes: notes, settings: settings)
    )

    private(set) lazy var quickAddPanel: FloatingPanelController<QuickAddPanelView> = FloatingPanelController(
        minimumWidth: 520
    ) {
        QuickAddPanelView(
            onCommit: { [weak self] title, priority, mode in
                guard let self else { return }
                switch mode {
                case .task:
                    tasks.add(title: title, priority: priority)
                case .note:
                    notes.add(text: title)
                }
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
        keyCode: settings.quickAddShortcut.keyCode,
        modifiers: settings.quickAddShortcut.modifiers
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
            if settings.showInMenuBar {
                statusItem.togglePopover(focusQuickAdd: true)
            } else {
                // The status item is hidden; the capture panel is the only
                // reachable surface, so open that.
                quickAddPanel.show()
            }
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
        tasks.onOpenCountChange = { [weak self] in
            self?.statusItem.refreshIcon()
        }
        settings.onChange = { [weak self] in
            guard let self else { return }
            statusItem.refreshIcon()
            model.refreshCountdownDisplay()
            hotKey?.update(settings.quickAddShortcut)
            statusItem.setVisible(settings.showInMenuBar)
        }
    }
}
