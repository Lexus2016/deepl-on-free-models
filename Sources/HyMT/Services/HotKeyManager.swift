import AppKit
import Carbon.HIToolbox

private var sharedHotKeyManager: HotKeyManager?

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
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
    if status == noErr {
        sharedHotKeyManager?.fire(hotKeyID.id)
    }
    return noErr
}

/// System-wide shortcuts via Carbon. Carbon only announces the keystroke; it
/// never reads the keyboard, so registering a shortcut needs no permissions.
final class HotKeyManager {
    private struct Registration {
        let combo: KeyCombo
        let eventID: UInt32
        let reference: EventHotKeyRef
        var action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextEventID: UInt32 = 1
    private let signature: OSType = 0x48594D54

    init() {
        sharedHotKeyManager = self
    }

    @discardableResult
    func register(_ combo: KeyCombo, id: UInt32, action: @escaping () -> Void) -> Bool {
        guard combo.isValid else { return false }
        if var current = registrations[id],
           current.combo.keyCode == combo.keyCode,
           current.combo.carbonModifiers == combo.carbonModifiers {
            current.action = action
            registrations[id] = current
            return true
        }
        ensureHandler()
        guard handlerRef != nil else { return false }

        var ref: EventHotKeyRef?
        let eventID = nextEventID
        nextEventID += 1
        let hotKeyID = EventHotKeyID(signature: signature, id: eventID)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        guard status == noErr, let ref else { return false }
        unregister(id: id)
        registrations[id] = Registration(combo: combo, eventID: eventID, reference: ref, action: action)
        return true
    }

    private func unregister(id: UInt32) {
        if let current = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(current.reference)
        }
    }

    func unregisterAll() {
        for id in Array(registrations.keys) {
            unregister(id: id)
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }

    fileprivate func fire(_ id: UInt32) {
        registrations.values.first(where: { $0.eventID == id })?.action()
    }

    private func ensureHandler() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}
