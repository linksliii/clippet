import AppKit
import Carbon.HIToolbox

struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_V),
                                       modifiers: UInt32(cmdKey) | UInt32(shiftKey))

    static let stackPaste = HotKeyCombo(keyCode: UInt32(kVK_ANSI_C),
                                        modifiers: UInt32(cmdKey) | UInt32(shiftKey))
}

final class HotKeyCenter {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    private var registered: [(ref: EventHotKeyRef, id: UInt32)] = []

    static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr, let handler = HotKeyCenter.handlers[hkID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            handler()
            return noErr
        }, 1, &spec, nil, nil)
    }

    @discardableResult
    func register(_ combo: HotKeyCombo, handler: @escaping () -> Void) -> Bool {
        HotKeyCenter.installHandlerIfNeeded()
        let id = HotKeyCenter.nextID
        HotKeyCenter.nextID += 1

        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x50535443), id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let validRef = ref else {
            NSLog("Clippet: hot key registration failed (\(status))")
            return false
        }
        HotKeyCenter.handlers[id] = handler
        registered.append((validRef, id))
        return true
    }

    func unregisterAll() {
        for (ref, id) in registered {
            UnregisterEventHotKey(ref)
            HotKeyCenter.handlers.removeValue(forKey: id)
        }
        registered.removeAll()
    }

    deinit { unregisterAll() }
}
