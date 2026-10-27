import AppKit

/// A nonactivating HUD that finishes and leaves the screen before capture starts.
@MainActor
final class RecordingCountdown {
    private let panel: NSPanel
    private let number = NSTextField(labelWithString: "3")
    private var steps: [NSView] = []
    private var task: Task<Bool, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 184),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let glass = NSVisualEffectView(frame: panel.contentView!.bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 24
        glass.layer?.masksToBounds = true
        panel.contentView = glass

        number.font = .monospacedDigitSystemFont(ofSize: 72, weight: .medium)
        number.textColor = .white
        number.alignment = .center
        number.frame = NSRect(x: 20, y: 65, width: 140, height: 92)
        number.setAccessibilityLabel("Recording countdown")
        glass.addSubview(number)

        let caption = NSTextField(labelWithString: "Starting recording")
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = NSColor.white.withAlphaComponent(0.75)
        caption.alignment = .center
        caption.frame = NSRect(x: 10, y: 40, width: 160, height: 18)
        glass.addSubview(caption)

        for index in 0..<3 {
            let step = NSView(frame: NSRect(x: 69 + index * 16, y: 23, width: 10, height: 4))
            step.wantsLayer = true
            step.layer?.cornerRadius = 2
            glass.addSubview(step)
            steps.append(step)
        }
    }

    func run() async -> Bool {
        let countdown = Task { @MainActor in
            defer { panel.orderOut(nil) }
            if let screen = NSScreen.screens.first {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(
                    x: frame.midX - panel.frame.width / 2,
                    y: frame.midY - panel.frame.height / 2
                ))
            }
            do {
                for value in (1...3).reversed() {
                    try Task.checkCancellation()
                    number.stringValue = String(value)
                    for (index, step) in steps.enumerated() {
                        step.layer?.backgroundColor = (index < value
                            ? NSColor.systemRed
                            : NSColor.white.withAlphaComponent(0.2)).cgColor
                    }
                    panel.orderFrontRegardless()
                    StartupTiming.mark("countdown_\(value)")
                    try await Task.sleep(for: .seconds(1))
                }
                panel.orderOut(nil)
                StartupTiming.mark("countdown_hidden")
                // Let WindowServer present the removal before ScreenCaptureKit starts.
                try await Task.sleep(for: .milliseconds(150))
                StartupTiming.mark("countdown_complete")
                return true
            } catch {
                return false
            }
        }
        task = countdown
        let completed = await countdown.value
        task = nil
        return completed
    }

    func cancel() {
        task?.cancel()
        panel.orderOut(nil)
    }
}
