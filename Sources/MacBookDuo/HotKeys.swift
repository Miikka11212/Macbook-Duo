import Carbon

final class HotKeys {
    var onKey: ((UInt32) -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [UInt32: EventHotKeyRef] = [:]
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            owner.onKey?(id.id)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func register(_ id: UInt32, code: UInt32, modifiers: UInt32) -> Bool {
        var key: EventHotKeyRef?
        let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x44554F31, id: id), GetApplicationEventTarget(), 0, &key)
        if let key, status == noErr { keys[id] = key; return true }
        return false
    }
    func preview(_ enabled: Bool) {
        if let key = keys.removeValue(forKey: 4) { UnregisterEventHotKey(key) }
        if enabled { register(4, code: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey)) }
    }
    func unregisterAll() {
        for key in keys.values { UnregisterEventHotKey(key) }
        keys.removeAll()
    }
    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }
}
