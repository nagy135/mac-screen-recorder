import AppKit
import CoreGraphics

@main
struct MacScreenRecorderApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--check-permission") {
            print(CGPreflightScreenCaptureAccess() ? "Screen recording: allowed" : "Screen recording: permission required")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = Recorder()
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?
    private var terminationPending = false
    private var smokeTestScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(stopRecording)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Mac Screen Recorder")
        }
        updateIndicator(.starting)

        recorder.onPhaseChange = { [weak self] phase in self?.updateIndicator(phase) }
        recorder.onFinish = { [weak self] url in
            if let url { NSLog("Saved recording: %@", url.path) }
            self?.quit()
        }
        recorder.onFailure = { [weak self] error in self?.showError(error) }
        do {
            shortcut = try GlobalShortcut { [weak self] in self?.recorder.stop() }
        } catch {
            showError(error)
            return
        }
        Task { await recorder.start() }
    }

    @objc private func stopRecording() { recorder.stop() }

    private func updateIndicator(_ phase: Recorder.Phase) {
        let color: NSColor
        let text: String
        switch phase {
        case .starting:
            color = .systemOrange
            text = "Starting recording — click or press ⌘⌥⇧S to cancel"
        case .recording:
            color = .systemRed
            text = "Recording — click or press ⌘⌥⇧S to stop and save"
            if CommandLine.arguments.contains("--smoke-test"), !smokeTestScheduled {
                smokeTestScheduled = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    recorder.stop()
                }
            }
        case .stopping:
            color = .systemOrange
            text = "Saving MP4…"
        case .finished:
            color = .systemGreen
            text = "Recording saved"
        case .failed:
            color = .systemOrange
            text = "Recording failed"
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8)).fill()
            return true
        }
        image.isTemplate = false
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = text
        statusItem?.button?.setAccessibilityValue(text)
    }

    private func showError(_ error: Error) {
        NSLog("Recording error: %@", error.localizedDescription)
        let alert = NSAlert()
        alert.messageText = "Could not record the screen"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let recordingError = error as? RecordingError, case .permission = recordingError {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        quit()
    }

    private func quit() {
        shortcut?.unregister()
        if terminationPending {
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            // No active recording exists when shortcut registration fails.
            NSApp.delegate = nil
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !recorder.isFinished else { return .terminateNow }
        terminationPending = true
        recorder.stop()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { shortcut?.unregister() }
}
