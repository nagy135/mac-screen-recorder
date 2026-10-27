// Compile together with GlobalShortcut.swift. Exercises Carbon event routing
// without synthesizing keyboard input or starting a recording.
import AppKit
import Carbon

@main
struct ShortcutRoutingCheck {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        var received: [GlobalShortcut.Action] = []
        let shortcuts = try GlobalShortcut { received.append($0) }
        defer { shortcuts.unregister() }

        func send(identifier: EventHotKeyID) -> OSStatus {
            var event: EventRef?
            let created = CreateEvent(
                nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event
            )
            guard created == noErr, let event else { return created }
            defer { ReleaseEvent(event) }
            var identifier = identifier
            let parameter = SetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                MemoryLayout<EventHotKeyID>.size, &identifier
            )
            guard parameter == noErr else { return parameter }
            return SendEventToEventTarget(event, GetApplicationEventTarget())
        }

        precondition(send(identifier: EventHotKeyID(signature: 0x4D535243, id: 1)) == noErr)
        precondition(send(identifier: EventHotKeyID(signature: 0x4D535243, id: 2)) == noErr)
        precondition(received == [.save, .trim], "Stop shortcuts dispatched to the wrong destination")
        _ = send(identifier: EventHotKeyID(signature: 0x4D535243, id: 99))
        _ = send(identifier: EventHotKeyID(signature: 0x42414421, id: 1))
        precondition(received == [.save, .trim], "An unrelated event triggered a stop action")

        shortcuts.unregister()
        let secondRegistration = try GlobalShortcut { _ in }
        secondRegistration.unregister()
        print("Both global shortcuts register, route distinct actions, ignore unrelated events, and unregister cleanly.")
    }
}
