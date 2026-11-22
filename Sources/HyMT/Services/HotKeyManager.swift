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
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 10
    private let signature: OSType = 0x48594D54

    init() {
        sharedHotKeyManager = self
    }

    @discardableResult
    func register(_ combo: KeyCombo, id: UInt32? = nil, action: @escaping () -> Void) -> Bool {
        let identifier = id ?? nextID
        nextID = max(nextID, identifier + 1)
        unregister(id: identifier)
        guard combo.isValid else { return false }
        ensureHandler()
        actions[identifier] = action

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            actions[identifier] = nil
            return false
        }
        refs[identifier] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        actions[id] = nil
    }

    func unregisterAll() {
        for id in Array(refs.keys) {
            unregister(id: id)
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
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
