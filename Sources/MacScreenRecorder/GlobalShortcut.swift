import Carbon

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) throws {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                // Carbon dispatches application-target events on the main thread.
                MainActor.assumeIsolated {
                    Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action()
                }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { throw ShortcutError.registration(status) }

        let identifier = EventHotKeyID(signature: 0x4D535243, id: 1) // MSRC
        let registration = RegisterEventHotKey(
            UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey | shiftKey),
            identifier, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey
        )
        guard registration == noErr else {
            if let handler { RemoveEventHandler(handler) }
            self.handler = nil
            throw ShortcutError.registration(registration)
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}

private enum ShortcutError: LocalizedError {
    case registration(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registration(let code):
            "Could not register ⌘⌥⇧S (error \(code)). Another app may already use this shortcut."
        }
    }
}
