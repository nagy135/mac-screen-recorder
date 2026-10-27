import AppKit
import AVFoundation
import QuartzCore
import RecorderCore

/// A nonactivating HUD that leaves the screen before capture starts.
@MainActor
final class RecordingCountdown: NSObject {
    private let panel: NSPanel
    private let glass: CountdownHoverView
    private let countdownView = NSView()
    private let optionsView = NSView()
    private let number = NSTextField(labelWithString: "3")
    private let systemAudioSwitch = NSSwitch()
    private let microphoneSwitch = NSSwitch()
    private let settingsButton = NSButton()
    private var steps: [NSView] = []
    private var state = CountdownState()
    private var audio = RecordingAudioSettings()
    private var timer: Task<Void, Never>?
    private var continuation: CheckedContinuation<RecordingAudioSettings?, Never>?
    private var runID = UUID()
    private var showingOptions = false
    private var transitionID = UUID()
    private let microphoneAuthorizationStatus: () -> AVAuthorizationStatus
    private let requestMicrophoneAccess: () async -> Bool

    init(microphoneAuthorizationStatus: @escaping () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }, requestMicrophoneAccess: @escaping () async -> Bool = {
        await AVCaptureDevice.requestAccess(for: .audio)
    }) {
        self.microphoneAuthorizationStatus = microphoneAuthorizationStatus
        self.requestMicrophoneAccess = requestMicrophoneAccess
        let bounds = NSRect(x: 0, y: 0, width: 180, height: 184)
        panel = NSPanel(
            contentRect: bounds,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        glass = CountdownHoverView(frame: bounds)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setAccessibilityLabel("Recording countdown")

        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 24
        glass.layer?.masksToBounds = true
        // Mask the WindowServer backdrop as well as the foreground layer.
        // A layer corner radius alone leaves a faint rectangular blur outside it.
        let radius: CGFloat = 24
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1),
                           flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        glass.maskImage = mask
        glass.onHover = { [weak self] hovering in self?.setHovering(hovering) }
        panel.contentView = glass

        countdownView.frame = bounds
        countdownView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        countdownView.wantsLayer = true
        glass.addSubview(countdownView)
        number.font = .monospacedDigitSystemFont(ofSize: 72, weight: .medium)
        number.textColor = .white
        number.alignment = .center
        number.frame = NSRect(x: 20, y: 65, width: 140, height: 92)
        number.setAccessibilityLabel("Recording countdown")
        countdownView.addSubview(number)
        addLabel("Starting recording", to: countdownView,
                 frame: NSRect(x: 10, y: 40, width: 160, height: 18), size: 12, centered: true)
        addLabel("Hover for options", to: countdownView,
                 frame: NSRect(x: 10, y: 5, width: 160, height: 14), size: 10, centered: true)
        for index in 0..<3 {
            let step = NSView(frame: NSRect(x: 69 + index * 16, y: 25, width: 10, height: 4))
            step.wantsLayer = true
            step.layer?.cornerRadius = 2
            countdownView.addSubview(step)
            steps.append(step)
        }

        optionsView.frame = NSRect(x: -30, y: 0, width: 240, height: 184)
        optionsView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        optionsView.wantsLayer = true
        optionsView.isHidden = true
        glass.addSubview(optionsView)
        addLabel("Audio", to: optionsView,
                 frame: NSRect(x: 20, y: 148, width: 140, height: 20), size: 13, bold: true)
        let cancelButton = NSButton()
        cancelButton.frame = NSRect(x: 166, y: 146, width: 58, height: 24)
        cancelButton.title = "Cancel"
        cancelButton.font = .systemFont(ofSize: 11, weight: .semibold)
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 7
        cancelButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        cancelButton.contentTintColor = .white
        cancelButton.toolTip = "Cancel recording"
        cancelButton.setAccessibilityLabel("Cancel recording")
        cancelButton.target = self
        cancelButton.action = #selector(cancelFromButton)
        optionsView.addSubview(cancelButton)
        addAudioRow("Mac audio", symbol: "speaker.wave.2", y: 107, control: systemAudioSwitch,
                    action: #selector(systemAudioChanged))
        addAudioRow("Microphone", symbol: "mic", y: 71, control: microphoneSwitch,
                    action: #selector(microphoneChanged))
        addShortcutHint(action: .save, x: 12, width: 88)
        addShortcutHint(action: .trim, x: 112, width: 116)
        settingsButton.frame = NSRect(x: 157, y: 76, width: 18, height: 20)
        settingsButton.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .systemOrange
        settingsButton.toolTip = "Allow microphone access in System Settings"
        settingsButton.setAccessibilityLabel("Open microphone permissions")
        settingsButton.target = self
        settingsButton.action = #selector(openMicrophoneSettings)
        settingsButton.isHidden = true
        optionsView.addSubview(settingsButton)
    }

    func run() async -> RecordingAudioSettings? {
        cancel()
        state = CountdownState()
        audio = RecordingAudioSettings()
        systemAudioSwitch.state = .off
        microphoneSwitch.state = .off
        microphoneSwitch.isEnabled = true
        microphoneSwitch.toolTip = "Record the default microphone"
        settingsButton.isHidden = true
        showOptions(false)
        if let screen = NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            restartTimer()
            panel.orderFrontRegardless()
            setHovering(glass.containsMouse)
        }
    }

    func cancel() {
        runID = UUID()
        finish(nil)
    }

    @objc private func cancelFromButton() {
        cancel()
    }

    private func finish(_ result: RecordingAudioSettings?) {
        transitionID = UUID()
        let pending = continuation
        continuation = nil
        timer?.cancel()
        timer = nil
        panel.orderOut(nil)
        pending?.resume(returning: result)
    }

    private func setHovering(_ hovering: Bool) {
        guard continuation != nil, !state.isComplete, hovering != state.isHovering else { return }
        state.setHovering(hovering)
        showOptions(state.isPaused)
        restartTimer()
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        guard continuation != nil, !state.isPaused, !state.isComplete else { return }
        updateNumber()
        timer = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while !state.isComplete {
                    try await Task.sleep(for: .seconds(1))
                    try Task.checkCancellation()
                    state.tick()
                    if !state.isComplete { updateNumber() }
                }
                panel.orderOut(nil)
                StartupTiming.mark("countdown_hidden")
                // Let WindowServer present the removal before ScreenCaptureKit starts.
                try await Task.sleep(for: .milliseconds(150))
                try Task.checkCancellation()
                StartupTiming.mark("countdown_complete")
                finish(audio)
            } catch {
                // Hover, cancellation, and permission changes invalidate this timer.
            }
        }
    }

    private func updateNumber() {
        number.stringValue = String(state.remainingSeconds)
        for (index, step) in steps.enumerated() {
            step.layer?.backgroundColor = (index < state.remainingSeconds
                ? NSColor.systemRed : NSColor.white.withAlphaComponent(0.2)).cgColor
        }
        StartupTiming.mark("countdown_\(state.remainingSeconds)")
    }

    private func showOptions(_ visible: Bool) {
        guard visible != showingOptions || !panel.isVisible else { return }
        showingOptions = visible
        let currentTransition = UUID()
        transitionID = currentTransition
        let width: CGFloat = visible ? 240 : 180
        let height: CGFloat = 184
        let frame = panel.frame
        let target = NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2,
                            width: width, height: height)
        guard panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(target, display: true)
            countdownView.alphaValue = visible ? 0 : 1
            optionsView.alphaValue = visible ? 1 : 0
            countdownView.isHidden = visible
            optionsView.isHidden = !visible
            panel.invalidateShadow()
            return
        }

        countdownView.isHidden = false
        optionsView.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
            countdownView.animator().alphaValue = visible ? 0 : 1
            optionsView.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.transitionID == currentTransition else { return }
                self.countdownView.isHidden = visible
                self.optionsView.isHidden = !visible
                self.panel.invalidateShadow()
            }
        }
    }

    @objc private func systemAudioChanged() {
        audio.systemAudio = systemAudioSwitch.state == .on
    }

    @objc private func microphoneChanged() {
        guard microphoneSwitch.state == .on else {
            audio.microphone = false
            return
        }
        switch microphoneAuthorizationStatus() {
        case .authorized:
            audio.microphone = true
            updateMicrophoneStatus(allowed: true)
        case .notDetermined:
            state.setWaitingForPermission(true)
            showOptions(true)
            microphoneSwitch.isEnabled = false
            microphoneSwitch.toolTip = "Waiting for microphone permission…"
            restartTimer()
            let currentRun = runID
            let requestAccess = requestMicrophoneAccess
            Task { @MainActor [weak self] in
                let allowed = await requestAccess()
                guard let self, runID == currentRun, continuation != nil else { return }
                audio.microphone = allowed
                microphoneSwitch.state = allowed ? .on : .off
                microphoneSwitch.isEnabled = true
                state.setWaitingForPermission(false)
                state.setHovering(glass.containsMouse)
                updateMicrophoneStatus(allowed: allowed)
                showOptions(state.isPaused)
                restartTimer()
            }
        default:
            audio.microphone = false
            microphoneSwitch.state = .off
            updateMicrophoneStatus(allowed: false)
        }
    }

    private func updateMicrophoneStatus(allowed: Bool) {
        microphoneSwitch.toolTip = allowed ? "Record the default microphone"
            : "Microphone access is off. Allow it in System Settings."
        settingsButton.isHidden = allowed
    }

    @objc private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func addLabel(_ text: String, to view: NSView, frame: NSRect,
                          size: CGFloat, centered: Bool = false, bold: Bool = false) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: bold ? .semibold : .medium)
        label.textColor = NSColor.white.withAlphaComponent(bold ? 1 : 0.75)
        label.alignment = centered ? .center : .left
        view.addSubview(label)
    }

    private func addAudioRow(_ title: String, symbol: String, y: CGFloat,
                             control: NSSwitch, action: Selector) {
        let image = NSImageView(frame: NSRect(x: 20, y: y + 5, width: 18, height: 20))
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        optionsView.addSubview(image)
        addLabel(title, to: optionsView, frame: NSRect(x: 46, y: y + 5, width: 110, height: 20), size: 12)
        control.frame = NSRect(x: 184, y: y, width: 36, height: 30)
        control.target = self
        control.action = action
        control.setAccessibilityLabel(title)
        optionsView.addSubview(control)
    }

    private func addShortcutHint(action: GlobalShortcut.Action, x: CGFloat, width: CGFloat) {
        let group = NSView(frame: NSRect(x: x, y: 21, width: width, height: 20))
        let title = action == .save ? "Stop and save" : "Stop and trim"
        group.toolTip = "\(title) (\(action.label)); cancels during countdown"
        let destination = action == .save ? "Finder" : "LosslessCut"
        let label = NSTextField(labelWithString: "\(action.label) → \(destination)")
        label.frame = NSRect(x: 0, y: 1, width: width, height: 18)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.4)
        label.setAccessibilityLabel("\(title): Command Option Shift \(action.label.last!)")
        group.addSubview(label)
        optionsView.addSubview(group)
    }
}

@MainActor
private final class CountdownHoverView: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    var containsMouse: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
