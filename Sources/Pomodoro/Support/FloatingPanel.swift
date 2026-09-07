import AppKit
import SwiftUI

/// A borderless, non-activating panel that can become key (for text input)
/// without stealing focus from the user's current app. Used for the
/// Spotlight-style quick-add panel and the timer-end summary HUD.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class FloatingPanelController<Content: View>: NSObject, NSWindowDelegate {

    let panel: KeyPanel
    private let hostingView: NSHostingView<Content>
    private let minimumWidth: CGFloat
    private let verticalOffset: CGFloat
    private let becomesKeyOnShow: Bool
    private var isHidingProgrammatically = false

    init(
        minimumWidth: CGFloat,
        verticalOffset: CGFloat = 96,
        becomesKeyOnShow: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: minimumWidth, height: 120)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingView = NSHostingView(rootView: content())
        self.minimumWidth = minimumWidth
        self.verticalOffset = verticalOffset
        self.becomesKeyOnShow = becomesKeyOnShow

        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.delegate = self
        panel.contentView = hostingView
    }

    var isVisiblyShown: Bool {
        panel.isVisible && panel.alphaValue > 0.01
    }

    func show() {
        if isVisiblyShown {
            if becomesKeyOnShow { panel.makeKey() }
            return
        }
        resizeToFitContent()
        positionNearTopOfScreen()
        panel.alphaValue = 0
        if becomesKeyOnShow {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible, !isHidingProgrammatically else { return }
        isHidingProgrammatically = true
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            },
            completionHandler: { [panel] in
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                }
            })
        isHidingProgrammatically = false
    }

    func toggle() {
        isVisiblyShown ? hide() : show()
    }

    /// Sizes the window to the SwiftUI content's natural height, keeping the width fixed.
    private func resizeToFitContent() {
        let fitting = hostingView.fittingSize
        let width = max(minimumWidth, fitting.width)
        let height = max(40, fitting.height)
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func positionNearTopOfScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        let x = visible.midX - frame.width / 2
        let y = visible.maxY - frame.height - verticalOffset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
