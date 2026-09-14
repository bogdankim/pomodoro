import AppKit

/// SwiftUI's `onKeyPress` never receives Shift-Tab: AppKit's key view loop
/// consumes it for backward focus navigation before SwiftUI sees the event.
/// A local NSEvent monitor sits in front of that loop, so while the capture
/// field is focused it can intercept Shift-Tab and hand it to the capture
/// mode instead. Unmatched events pass through untouched.
@MainActor
final class CaptureModeKeyMonitor {

    // The token is only touched on the main actor; `nonisolated(unsafe)` lets
    // the deinit (which is nonisolated) remove it as a last-resort cleanup.
    nonisolated(unsafe) private var monitor: Any?
    private let shouldIntercept: () -> Bool
    private let onIntercept: () -> Void

    init(shouldIntercept: @escaping () -> Bool, onIntercept: @escaping () -> Void) {
        self.shouldIntercept = shouldIntercept
        self.onIntercept = onIntercept
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only a Bool crosses the isolation boundary; NSEvent is not Sendable.
            let shouldSwallow = MainActor.assumeIsolated { self.shouldSwallowShiftTab(event) }
            if shouldSwallow {
                MainActor.assumeIsolated { self.onIntercept() }
                return nil
            }
            return event
        }
    }

    private func shouldSwallowShiftTab(_ event: NSEvent) -> Bool {
        guard shouldIntercept(),
            event.keyCode == 48,  // Tab
            event.modifierFlags.contains(.shift),
            !event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.control),
            !event.modifierFlags.contains(.option)
        else { return false }
        return true
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
