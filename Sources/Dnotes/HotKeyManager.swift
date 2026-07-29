import AppKit
import Carbon.HIToolbox
import DnotesCore

enum HotKeyError: Error, Equatable {
    case registrationFailed(OSStatus)
}

enum HotKeyID {
    static let capture: UInt32 = 1
    static let mainWindow: UInt32 = 2
}

/// One Carbon event handler for the whole app, plus a table of registrations.
/// `RegisterEventHotKey` needs no Accessibility permission (§11), so there is no
/// prompt on first launch.
@MainActor
final class HotKeyManager {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    static let signature = OSType(0x646E_7473)   // 'dnts'

    func register(_ combo: HotKeyCombo,
                  id: UInt32,
                  handler: @escaping @MainActor () -> Void) throws {
        installEventHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { throw HotKeyError.registrationFailed(status) }
        refs[id] = ref
        handlers[id] = handler
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = pressed.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { manager.fire(id) }
                }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
    }
}
