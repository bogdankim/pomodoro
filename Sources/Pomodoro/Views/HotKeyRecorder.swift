import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A macOS-style keyboard shortcut recorder: shows the current combination,
/// click to start recording, press any key combination to capture it.
/// Escape or Return ends recording without changing the shortcut; a bare
/// modifier press is ignored while recording.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Text(recording ? "Press a shortcut…" : combo.displayName)
            .font(.callout)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 120)
            .background(
                recording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                if recording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { recording = true }
            .help("Click, then press the new shortcut")
            .accessibilityLabel("Quick-add shortcut, currently \(combo.displayName)")
            .onAppear { installMonitor() }
            .onDisappear { stopRecording() }
    }

    /// Captured through a local event monitor: with the recorder active,
    /// SwiftUI text fields and AppKit's key view loop would otherwise eat
    /// arrow keys, Tab, and other keys before the recorder sees them.
    private func installMonitor() {
        guard monitor == nil else { return }
        let state = RecordingState(combo: $combo, recording: $recording)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                state.handle(event)
            }
            return handled ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

/// Holds the recorder's live bindings for the event-monitor closure, which
/// cannot capture the view struct itself. `handle` returns true when the
/// event was consumed by the recorder.
@MainActor
private final class RecordingState {
    private let combo: Binding<KeyCombo>
    private let recording: Binding<Bool>

    init(combo: Binding<KeyCombo>, recording: Binding<Bool>) {
        self.combo = combo
        self.recording = recording
    }

    func handle(_ event: NSEvent) -> Bool {
        guard recording.wrappedValue else { return false }

        if event.keyCode == UInt16(kVK_Escape) || event.keyCode == UInt16(kVK_Return) {
            recording.wrappedValue = false
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        // A lone modifier keypress arrives with only itself in the flags;
        // ignore it so users can build a combination key by key.
        if isModifierKeyCode(event.keyCode) {
            return true
        }

        guard carbonModifiers != 0 else {
            // A plain key with no modifiers: keep recording, ignore the press.
            return true
        }

        let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        if candidate.isValid {
            combo.wrappedValue = candidate
        }
        recording.wrappedValue = false
        return true
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_CapsLock), UInt16(kVK_Function):
            true
        default:
            false
        }
    }
}
