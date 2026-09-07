import AppKit
import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut via Carbon's hot key API, which
/// needs no accessibility permission. The action runs on the main actor.
@MainActor
final class GlobalHotKey {

    private static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var registeredID: UInt32 = 0

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        if !GlobalHotKey.handlerInstalled {
            var eventTypes = [
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard),
                    eventKind: UInt32(kEventHotKeyPressed)
                )
            ]
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                1,
                &eventTypes,
                nil,
                nil
            )
            guard status == noErr else { return nil }
            GlobalHotKey.handlerInstalled = true
        }

        let id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x504F_4D44) /* 'POMD' */, id: id)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard registerStatus == noErr, ref != nil else { return nil }

        hotKeyRef = ref
        registeredID = id
        GlobalHotKey.handlers[id] = action
    }

    /// The hot key stays registered for the process lifetime; there is no
    /// unregistration path (deinit cannot touch the non-Sendable ref).
    fileprivate static func fire(id: UInt32) {
        handlers[id]?()
    }
}

/// Runs on the main thread (Carbon dispatches application event handlers there),
/// so the main-actor hop can be asserted.
private func hotKeyEventHandler(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    MainActor.assumeIsolated {
        GlobalHotKey.fire(id: hotKeyID.id)
    }
    return noErr
}
