import AppKit
import RecorderCore
import ScreenCaptureKit

/// Exercises the real HUD and its tracking-event handlers without recording the desktop.
@main
struct CountdownCheck {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Keep the live pointer from competing with the app-local tracking events below.
        let trackingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseEntered, .mouseExited]) { _ in nil }
        Task { @MainActor in
            do {
                let countdown = RecordingCountdown(microphoneAuthorizationStatus: { .authorized })
                let result = Task { await countdown.run() }
                try await Task.sleep(for: .milliseconds(100))
                let panel = app.windows.first { $0.isVisible && $0 is NSPanel }!
                let content = panel.contentView!
                let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                                              modifierFlags: [], timestamp: 0,
                                              windowNumber: panel.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 0, pressure: 0)!
                content.mouseExited(with: event)
                try await Task.sleep(for: .milliseconds(2_100))
                let number = descendants(content).compactMap { $0 as? NSTextField }
                    .first { $0.accessibilityLabel() == "Recording countdown" }!
                precondition(number.stringValue == "1", "Countdown must run 3, 2, 1; received \(number.stringValue)")
                let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
                content.mouseEntered(with: event)
                try await Task.sleep(for: .milliseconds(100))
                precondition(panel.frame.width > 180 && panel.frame.width < 240,
                             "Morph must animate the shell between its endpoints")
                let countdownView = descendants(content).first { $0.identifier?.rawValue == "countdown-content" }!
                let segments = descendants(content).filter { $0.identifier?.rawValue.hasPrefix("countdown-segment-") == true }
                    .sorted { $0.identifier!.rawValue < $1.identifier!.rawValue }
                precondition(segments.count == 3 && segments[0].frame.midY > 27 && segments[0].frame.midY < 158,
                             "Red countdown segments must travel upward toward Cancel")
                precondition(segments[0].frame.height > 4 && segments[0].frame.height < 24,
                             "The moving segments must grow into the button capsule")
                saveSnapshot(content, to: "dist/countdown-morph-transition.png")
                try await saveWindowSnapshot(panel, to: "dist/countdown-morph-window.png")
                try await Task.sleep(for: .milliseconds(650))
                precondition(panel.frame.width == 240, "Hover must expand the HUD")
                precondition(abs(panel.frame.midX - center.x) < 1 && abs(panel.frame.midY - center.y) < 1,
                             "Morph must keep the HUD centered")
                precondition(countdownView.isHidden, "Settling must hide outgoing countdown content")
                let cancel = descendants(content).compactMap { $0 as? NSButton }
                    .first { $0.accessibilityLabel() == "Cancel recording" }!
                let capsule = segments.reduce(NSRect.null) { $0.union($1.frame) }
                precondition(abs(capsule.minX - cancel.frame.minX) < 0.5 &&
                             abs(capsule.maxX - cancel.frame.maxX) < 0.5 &&
                             capsule.minY == cancel.frame.minY && capsule.height == cancel.frame.height,
                             "The red segments must join into the actual Cancel button background")
                let switches = descendants(content).compactMap { $0 as? NSSwitch }
                let systemAudio = switches.first { $0.accessibilityLabel() == "Mac audio" }!
                let microphone = switches.first { $0.accessibilityLabel() == "Microphone" }!
                precondition(systemAudio.state == .off && microphone.state == .off)
                systemAudio.state = .on
                systemAudio.sendAction(systemAudio.action, to: systemAudio.target)
                microphone.state = .on
                microphone.sendAction(microphone.action, to: microphone.target)
                systemAudio.state = .off
                systemAudio.sendAction(systemAudio.action, to: systemAudio.target)
                precondition(microphone.state == .on, "Audio choices must be independent")
                systemAudio.state = .on
                systemAudio.sendAction(systemAudio.action, to: systemAudio.target)
                saveSnapshot(content, to: "dist/countdown-audio-options.png")
                try await saveWindowSnapshot(panel, to: "dist/countdown-audio-window.png")
                try await Task.sleep(for: .milliseconds(3_200))
                precondition(panel.isVisible, "Hover must pause longer than the original countdown")
                content.mouseExited(with: event)
                try await Task.sleep(for: .milliseconds(750))
                precondition(panel.frame.width == 180)
                precondition(number.superview?.layer?.sublayerTransform.m11 == 1 &&
                             segments[0].frame == NSRect(x: 69, y: 25, width: 10, height: 4),
                             "Returning must restore the original numeral scale and red segments")
                precondition(number.stringValue == "3", "Leaving must restart from three")
                saveSnapshot(content, to: "dist/countdown-restarted.png")
                try await Task.sleep(for: .milliseconds(350))
                precondition(number.stringValue == "2")
                try await saveWindowSnapshot(panel, to: "dist/countdown-rounded-window.png")
                content.mouseEntered(with: event)
                try await Task.sleep(for: .milliseconds(30))
                let reversingWidth = panel.frame.width
                content.mouseExited(with: event)
                precondition(panel.frame.width == reversingWidth, "Reversing must not jump to an endpoint")
                try await Task.sleep(for: .milliseconds(30))
                content.mouseEntered(with: event)
                try await Task.sleep(for: .milliseconds(750))
                precondition(panel.frame.width == 240, "Rapid hover reversals must finish expanded")
                precondition(countdownView.isHidden, "An old transition must not hide the incoming settings")
                precondition(systemAudio.state == .on, "Re-entering must retain choices")
                content.mouseExited(with: event)
                let restarted = ContinuousClock.now
                let selected = await result.value
                precondition(restarted.duration(to: .now) >= .seconds(3))
                precondition(selected == RecordingAudioSettings(systemAudio: true, microphone: true))
                precondition(!panel.isVisible, "HUD must be hidden before capture")

                let cancelled = Task { await countdown.run() }
                try await Task.sleep(for: .milliseconds(100))
                content.mouseEntered(with: event)
                precondition(systemAudio.state == .off, "Each recording starts with audio off")
                let cancelButton = descendants(content).compactMap { $0 as? NSButton }
                    .first { $0.accessibilityLabel() == "Cancel recording" }!
                cancelButton.performClick(nil)
                precondition(!panel.isVisible, "The cancel button must close the HUD")
                countdown.cancel()
                let cancelledResult = await cancelled.value
                precondition(cancelledResult == nil, "Cancellation must return no settings")
                precondition(!panel.isVisible)

                let hiding = Task { await countdown.run() }
                try await Task.sleep(for: .milliseconds(100))
                content.mouseExited(with: event)
                for _ in 0..<400 {
                    if !panel.isVisible { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                precondition(!panel.isVisible, "Countdown must hide before capture")
                countdown.cancel()
                let hidingResult = await hiding.value
                precondition(hidingResult == nil, "Cancellation during hide delay must prevent capture")
                try await checkPermission(allowed: true, event: event)
                try await checkPermission(allowed: false, event: event)
                try await checkCancelledPermission(event: event)
                try await checkReducedMotion(event: event)
                print("Countdown HUD passed: reversible red-segment morph, Cancel capsule alignment, reduced motion, hover/pause, repeated restart, independent audio selection, reset, cancellation, hide delay, and granted/denied/cancelled permission prompts")
                app.terminate(nil)
            } catch {
                fatalError("Countdown HUD check failed: \(error)")
            }
        }
        app.run()
        if let trackingMonitor { NSEvent.removeMonitor(trackingMonitor) }
    }

    @MainActor
    private static func checkReducedMotion(event: NSEvent) async throws {
        var reduced = false
        let countdown = RecordingCountdown(reduceMotion: { reduced })
        let result = Task { await countdown.run() }
        try await Task.sleep(for: .milliseconds(100))
        let panel = NSApp.windows.first { $0.isVisible && $0 is NSPanel }!
        let content = panel.contentView!
        content.mouseExited(with: event)
        content.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(60))
        reduced = true
        try await Task.sleep(for: .milliseconds(50))
        precondition(panel.frame.width == 240, "Enabling Reduce Motion during a transition must snap to settings")
        precondition(descendants(content).allSatisfy { $0.contentFilters.isEmpty },
                     "Reduced motion must leave no content blur filters")
        content.mouseExited(with: event)
        precondition(panel.frame.width == 180, "Reduce Motion must return to countdown immediately")
        content.mouseEntered(with: event)
        precondition(panel.frame.width == 240, "Reduce Motion must open settings immediately")
        countdown.cancel()
        let selected = await result.value
        precondition(selected == nil)
    }

    @MainActor
    private static func checkPermission(allowed: Bool, event: NSEvent) async throws {
        var resolvePermission: CheckedContinuation<Bool, Never>?
        let countdown = RecordingCountdown(microphoneAuthorizationStatus: { .notDetermined },
                                           requestMicrophoneAccess: {
            await withCheckedContinuation { resolvePermission = $0 }
        })
        let result = Task { await countdown.run() }
        try await Task.sleep(for: .milliseconds(100))
        let panel = NSApp.windows.first { $0.isVisible && $0 is NSPanel }!
        let content = panel.contentView!
        content.mouseEntered(with: event)
        let microphone = descendants(content).compactMap { $0 as? NSSwitch }
            .first { $0.accessibilityLabel() == "Microphone" }!
        microphone.state = .on
        microphone.sendAction(microphone.action, to: microphone.target)
        content.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(3_200))
        precondition(panel.isVisible && panel.frame.width == 240, "Permission prompt must hold the controls open")
        precondition(!microphone.isEnabled)
        resolvePermission!.resume(returning: allowed)
        try await Task.sleep(for: .milliseconds(50))
        precondition(microphone.isEnabled)
        precondition(microphone.state == (allowed ? .on : .off))
        content.mouseExited(with: event)
        let selected = await result.value
        precondition(selected == RecordingAudioSettings(microphone: allowed))
    }

    @MainActor
    private static func checkCancelledPermission(event: NSEvent) async throws {
        var resolvePermission: CheckedContinuation<Bool, Never>?
        let countdown = RecordingCountdown(microphoneAuthorizationStatus: { .notDetermined },
                                           requestMicrophoneAccess: {
            await withCheckedContinuation { resolvePermission = $0 }
        })
        let cancelled = Task { await countdown.run() }
        try await Task.sleep(for: .milliseconds(100))
        let panel = NSApp.windows.first { $0.isVisible && $0 is NSPanel }!
        let content = panel.contentView!
        content.mouseEntered(with: event)
        let microphone = descendants(content).compactMap { $0 as? NSSwitch }
            .first { $0.accessibilityLabel() == "Microphone" }!
        microphone.state = .on
        microphone.sendAction(microphone.action, to: microphone.target)
        try await Task.sleep(for: .milliseconds(50))
        countdown.cancel()
        let cancelledResult = await cancelled.value
        precondition(cancelledResult == nil)
        let next = Task { await countdown.run() }
        try await Task.sleep(for: .milliseconds(100))
        resolvePermission!.resume(returning: true)
        try await Task.sleep(for: .milliseconds(50))
        precondition(microphone.state == .off, "A cancelled permission request must not change the next run")
        countdown.cancel()
        let nextResult = await next.value
        precondition(nextResult == nil)
    }

    @MainActor
    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    private static func saveSnapshot(_ view: NSView, to path: String) {
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: image)
        try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    @MainActor
    private static func saveWindowSnapshot(_ panel: NSWindow, to path: String) async throws {
        guard CommandLine.arguments.contains("--capture-window") else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let window = content.windows.first { $0.windowID == CGWindowID(panel.windowNumber) }!
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0,
                     "The composited window's corners must be transparent")
    }
}
