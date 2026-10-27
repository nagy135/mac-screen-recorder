import AppKit
import CoreGraphics

@main
struct MacScreenRecorderApp {
    @MainActor
    static func main() {
        StartupTiming.mark("process_entry")
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
    private let countdown = RecordingCountdown()
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?
    private var terminationPending = false
    private var smokeTestScheduled = false
    private var completionAction: GlobalShortcut.Action?

    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupTiming.mark("application_ready")
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
        recorder.beforeCapture = { [weak self] in
            guard let self else { return nil }
            return await countdown.run()
        }
        recorder.onFinish = { [weak self] url in
            Task { @MainActor in await self?.finishRecording(url) }
        }
        recorder.onFailure = { [weak self] error in self?.showError(error) }
        do {
            shortcut = try GlobalShortcut { [weak self] action in self?.requestStop(action) }
        } catch {
            showError(error)
            return
        }
        Task { await recorder.start() }
    }

    @objc private func stopRecording() {
        requestStop(.save)
    }

    private func requestStop(_ action: GlobalShortcut.Action) {
        // The first stop request determines the destination, even if more keys
        // arrive while the MP4 is being finalized.
        guard completionAction == nil, !recorder.isFinished else { return }
        completionAction = action
        countdown.cancel()
        recorder.stop()
    }

    private func finishRecording(_ url: URL?) async {
        shortcut?.unregister()
        if let url {
            NSLog("Saved recording: %@", url.path)
            if completionAction == .trim {
                do {
                    try await LosslessCut.open(url)
                    NSLog("Opened recording in LosslessCut: %@", url.path)
                } catch {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    let alert = NSAlert()
                    alert.messageText = "Recording saved; could not open LosslessCut"
                    alert.informativeText = "\(error.localizedDescription)\n\nYour recording is safe at \(url.path)."
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        quit()
    }

    private func updateIndicator(_ phase: Recorder.Phase) {
        let color: NSColor
        let text: String
        switch phase {
        case .starting:
            color = .systemOrange
            text = "Starting recording — click, ⌘⌥⇧S or ⌘⌥⇧T to cancel"
        case .recording:
            color = .systemRed
            text = "Recording — click or ⌘⌥⇧S to save; ⌘⌥⇧T to open in LosslessCut"
            if (CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--smoke-test-trim")), !smokeTestScheduled {
                smokeTestScheduled = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    requestStop(CommandLine.arguments.contains("--smoke-test-trim") ? .trim : .save)
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
        if case .recording = phase { StartupTiming.mark("recording_indicator_updated") }
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
        countdown.cancel()
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
        stopRecording()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { shortcut?.unregister() }
}
