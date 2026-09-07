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
    private var anchorView: NSView?

    init(model: AppModel, settings: SettingsStore, content: PopoverContent) {
        self.model = model
        self.settings = settings

        super.init()

        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = .preferredContentSize
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

    // MARK: - Popover

    @objc private func statusItemClicked() {
        togglePopover()
    }

    func togglePopover(focusQuickAdd: Bool = false) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(focusQuickAdd: focusQuickAdd)
        }
    }

    func showPopover(focusQuickAdd: Bool) {
        guard let button = statusItem.button, let statusBar = button.superview else { return }

        // Anchor to a fixed snapshot of the button's frame rather than the
        // button itself: the icon changes width while the popover is open
        // (timer symbol when idle, ring and time when running), and a popover
        // anchored to the button would be dragged along with it.
        if anchorView == nil {
            anchorView = NSView(frame: button.frame)
            statusBar.addSubview(anchorView!)
        }
        anchorView?.frame = button.frame

        if focusQuickAdd {
            // The user asked for the panel from a global shortcut, so taking
            // key focus is expected; without it the popover cannot accept typing.
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.show(relativeTo: anchorView!.bounds, of: anchorView!, preferredEdge: .minY)
        if focusQuickAdd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .focusQuickAddField, object: nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {}

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
