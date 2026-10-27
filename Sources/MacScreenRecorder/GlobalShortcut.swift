import Carbon

@MainActor
final class GlobalShortcut {
    enum Action: UInt32 {
        case save = 1
        case trim = 2

        var keyCode: UInt32 { UInt32(self == .save ? kVK_ANSI_S : kVK_ANSI_T) }
        var label: String { self == .save ? "⌘⌥⇧S" : "⌘⌥⇧T" }
    }

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let action: @MainActor (Action) -> Void
    private static let signature: OSType = 0x4D535243 // MSRC

    init(action: @escaping @MainActor (Action) -> Void) throws {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
                )
                guard result == noErr else { return result }
                // Carbon dispatches application-target events on the main thread.
                return MainActor.assumeIsolated {
                    guard identifier.signature == GlobalShortcut.signature,
                          let selectedAction = Action(rawValue: identifier.id) else {
                        return OSStatus(eventNotHandledErr)
                    }
                    Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action(selectedAction)
                    return noErr
                }
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { throw ShortcutError.registration("stop shortcuts", status) }

        for selectedAction in [Action.save, .trim] {
            let identifier = EventHotKeyID(signature: Self.signature, id: selectedAction.rawValue)
            var hotKey: EventHotKeyRef?
            let registration = RegisterEventHotKey(
                selectedAction.keyCode, UInt32(cmdKey | optionKey | shiftKey),
                identifier, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey
            )
            guard registration == noErr, let hotKey else {
                unregister()
                throw ShortcutError.registration(selectedAction.label, registration)
            }
            hotKeys.append(hotKey)
        }
    }

    func unregister() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKeys.removeAll()
        handler = nil
    }
}

private enum ShortcutError: LocalizedError {
    case registration(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .registration(let shortcut, let code):
            "Could not register \(shortcut) (error \(code)). Another app may already use this shortcut."
        }
    }
}
