import AppKit
import SwiftUI

/// Owns the status bar item and its popover.
///
/// The icon is drawn directly into template NSImages rather than hosted as a
/// SwiftUI view: status items only render text and images reliably, and this
/// keeps the ring monochrome and legible in both menu bar appearances.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: AppModel
    private let settings: SettingsStore
    private var hosting: NSHostingController<PopoverContent>!
    private var anchorWindow: NSWindow?
    private var lastPopoverCloseDate: Date?

    init(model: AppModel, settings: SettingsStore, content: PopoverContent) {
        self.model = model
        self.settings = settings

        super.init()

        let hosting = NSHostingController(rootView: content)
        // The popover's size is owned by this controller, not by SwiftUI:
        // preferredContentSize would make NSPopover snap the window to a new
        // height in a single frame whenever the list changes.
        hosting.sizingOptions = []
        self.hosting = hosting
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.setAccessibilityLabel("Pomodoro")
            button.toolTip = "Pomodoro"
        }
        refreshIcon()
    }

    var isPopoverShown: Bool {
        popover.isShown
    }

    /// Shows or hides the status item entirely. When hidden, the popover is
    /// dismissed first; global shortcuts remain functional and are the way
    /// back in (the capture panel's hint points to Settings).
    func setVisible(_ visible: Bool) {
        guard statusItem.isVisible != visible else { return }
        if !visible, popover.isShown {
            popover.performClose(nil)
        }
        statusItem.isVisible = visible
    }

    // MARK: - Popover

    @objc private func statusItemClicked() {
        togglePopover()
    }

    func togglePopover(focusQuickAdd: Bool = true) {
        if popover.isShown {
            popover.performClose(nil)
        } else if let lastPopoverCloseDate,
            Date().timeIntervalSince(lastPopoverCloseDate) < 0.25
        {
            // The system just dismissed the transient popover (a click outside,
            // including on the status item itself); don't immediately reopen.
            return
        } else {
            showPopover(focusQuickAdd: focusQuickAdd)
        }
    }

    func showPopover(focusQuickAdd: Bool) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        // Anchor to a dedicated, fixed-size transparent window pinned over the
        // status item. The status item's own window resizes whenever the icon
        // changes (timer symbol when idle, ring and time when running), and an
        // NSPopover anchored inside it gets dragged along with every resize.
        // The anchor window never resizes while the popover is open, so the
        // panel stays put; it is re-pinned to the icon on each show.
        if anchorWindow == nil {
            let anchor = NSWindow(
                contentRect: buttonWindow.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            anchor.isOpaque = false
            anchor.backgroundColor = .clear
            anchor.level = .statusBar
            anchor.ignoresMouseEvents = true
            anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            anchor.isReleasedWhenClosed = false
            anchor.contentView = NSView(frame: NSRect(origin: .zero, size: buttonWindow.frame.size))
            anchor.orderFrontRegardless()
            anchorWindow = anchor
        }
        anchorWindow?.setFrameOrigin(buttonWindow.frame.origin)
        anchorWindow?.setContentSize(buttonWindow.frame.size)

        if focusQuickAdd {
            // The user asked for the panel from a global shortcut, so taking
            // key focus is expected; without it the popover cannot accept typing.
            NSApp.activate(ignoringOtherApps: true)
        }
        measureAndSizePopover()
        if let anchorView = anchorWindow?.contentView {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        }
        observePopoverNaturalHeight()
        if focusQuickAdd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .focusQuickAddField, object: nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseDate = Date()
        heightNotificationObserver = nil
    }

    // MARK: - Animated popover resizing

    /// NSPopover sizes its window from the content view controller's
    /// `preferredContentSize`. The content reports its natural height
    /// (`fixedSize` layout, unaffected by the window's current frame), and
    /// this controller steps `preferredContentSize` toward it along a 0.2s
    /// cubic ease-out — the same curve the list rows animate with — so
    /// NSPopover's resizes blend into one glide. The top edge stays pinned
    /// under the status item, so header and footer never move.

    private var heightNotificationObserver: NSObjectProtocol?
    private var heightAnimator: Timer?

    private func observePopoverNaturalHeight() {
        guard heightNotificationObserver == nil else { return }
        heightNotificationObserver = NotificationCenter.default.addObserver(
            forName: .popoverNaturalHeightChanged, object: nil, queue: .main
        ) { [weak self] notification in
            let naturalHeight = notification.userInfo?["height"] as? CGFloat ?? 0
            MainActor.assumeIsolated {
                guard let self, naturalHeight > 0 else { return }
                self.animatePreferredContentSize(to: naturalHeight)
            }
        }
    }

    /// Steps preferredContentSize along a cubic ease-out over 0.2s, matching
    /// the list rows' animation.
    private func animatePreferredContentSize(to target: CGFloat) {
        heightAnimator?.invalidate()
        heightAnimator = nil
        let start = hosting.preferredContentSize.height
        guard abs(target - start) > 0.5 else { return }

        let duration = 0.2
        let tickInterval = 1.0 / 120.0
        var elapsed: TimeInterval = 0
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                elapsed += tickInterval
                let progress = min(elapsed / duration, 1)
                let eased = 1 - pow(1 - progress, 3)
                let height = start + (target - start) * eased
                self.hosting.preferredContentSize = NSSize(width: 300, height: height)
                if progress >= 1 {
                    self.heightAnimator?.invalidate()
                    self.heightAnimator = nil
                    self.hosting.preferredContentSize = NSSize(width: 300, height: target)
                }
            }
        }
        heightAnimator = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Sizes the popover to the content's natural height. Called on every
    /// open, before `popover.show`.
    private func measureAndSizePopover() {
        let root = hosting.view
        root.layoutSubtreeIfNeeded()
        let natural = root.fittingSize.height
        guard natural > 0 else { return }
        heightAnimator?.invalidate()
        heightAnimator = nil
        hosting.preferredContentSize = NSSize(width: 300, height: natural)
    }

    // MARK: - Icon

    func refreshIcon() {
        guard let button = statusItem.button else { return }

        guard model.isActive else {
            button.image = Self.symbolImage()
            button.attributedTitle = NSAttributedString()
            return
        }

        // Focus drains from full (a depleting capacity); breaks fill up.
        let phase = model.phase ?? .focus
        let elapsed = model.engine.progress(now: Date())
        let fill = phase.isBreak ? elapsed : 1 - elapsed
        switch settings.iconMode {
        case .progressRing:
            button.image = Self.ringImage(fill: fill)
            button.attributedTitle = NSAttributedString()
        case .timer:
            button.image = nil
            button.attributedTitle = Self.timeText(model.timeText)
        case .combined:
            button.image = Self.ringImage(fill: fill)
            button.attributedTitle = Self.timeText(model.timeText)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        }
    }

    private static func symbolImage() -> NSImage {
        let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoro")!
        return image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))!
    }

    /// A template image of the progress ring: a 17pt ring inside a wider canvas
    /// whose trailing 5pt are transparent, giving the time text a clear gap.
    private static func ringImage(fill: Double) -> NSImage {
        let ringSize: CGFloat = 17
        let pointWidth: CGFloat = ringSize + 5
        let scale: CGFloat = 2
        let context = CGContext(
            data: nil,
            width: Int(pointWidth * scale),
            height: Int(ringSize * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)

        let rect = CGRect(x: 1, y: 1, width: ringSize - 2, height: ringSize - 2)
        let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
        let radius = rect.width / 2

        context.setStrokeColor(CGColor(gray: 0, alpha: 0.32))
        context.setLineWidth(1.75)
        context.addEllipse(in: rect)
        context.strokePath()

        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1.75)
        context.setLineCap(.round)
        let endAngle = .pi / 2 - max(fill, 0.02) * 2 * .pi
        context.addArc(
            center: center, radius: radius, startAngle: .pi / 2, endAngle: endAngle, clockwise: true)
        context.strokePath()

        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: pointWidth, height: ringSize))
        image.isTemplate = true
        return image
    }

    private static func timeText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ])
    }
}
