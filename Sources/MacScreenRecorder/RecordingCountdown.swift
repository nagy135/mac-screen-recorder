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
    private let hint = NSTextField(labelWithString: "Move away to restart from 3")
    private let settingsButton = NSButton(title: "Allow microphone in System Settings", target: nil, action: nil)
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
        countdownView.autoresizingMask = [.minXMargin, .maxXMargin]
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
        addLabel("Hover for audio", to: countdownView,
                 frame: NSRect(x: 10, y: 5, width: 160, height: 14), size: 10, centered: true)
        for index in 0..<3 {
            let step = NSView(frame: NSRect(x: 69 + index * 16, y: 25, width: 10, height: 4))
            step.wantsLayer = true
            step.layer?.cornerRadius = 2
            countdownView.addSubview(step)
            steps.append(step)
        }

        optionsView.frame = NSRect(x: -50, y: 0, width: 280, height: 184)
        optionsView.autoresizingMask = [.minXMargin, .maxXMargin]
        optionsView.wantsLayer = true
        optionsView.isHidden = true
        glass.addSubview(optionsView)
        addLabel("Record audio", to: optionsView,
                 frame: NSRect(x: 22, y: 146, width: 236, height: 22), size: 17, bold: true)
        addLabel("Choose what goes into your video", to: optionsView,
                 frame: NSRect(x: 22, y: 126, width: 236, height: 16), size: 11)
        addAudioRow("Mac audio", symbol: "speaker.wave.2", y: 88, control: systemAudioSwitch,
                    action: #selector(systemAudioChanged))
        addAudioRow("Microphone", symbol: "mic", y: 49, control: microphoneSwitch,
                    action: #selector(microphoneChanged))
        hint.frame = NSRect(x: 12, y: 13, width: 256, height: 18)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = NSColor.white.withAlphaComponent(0.65)
        hint.alignment = .center
        optionsView.addSubview(hint)
        settingsButton.frame = hint.frame
        settingsButton.isBordered = false
        settingsButton.font = .systemFont(ofSize: 11)
        settingsButton.contentTintColor = .systemOrange
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
        settingsButton.isHidden = true
        hint.isHidden = false
        hint.stringValue = "Move away to restart from 3"
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
        let width: CGFloat = visible ? 280 : 180
        let frame = panel.frame
        let target = NSRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: 184)
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
            updatePermissionHint(allowed: true)
        case .notDetermined:
            state.setWaitingForPermission(true)
            showOptions(true)
            microphoneSwitch.isEnabled = false
            hint.stringValue = "Waiting for microphone permission…"
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
                updatePermissionHint(allowed: allowed)
                showOptions(state.isPaused)
                restartTimer()
            }
        default:
            audio.microphone = false
            microphoneSwitch.state = .off
            updatePermissionHint(allowed: false)
        }
    }

    private func updatePermissionHint(allowed: Bool) {
        hint.stringValue = "Move away to restart from 3"
        hint.isHidden = !allowed
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
        let image = NSImageView(frame: NSRect(x: 23, y: y + 5, width: 20, height: 20))
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        optionsView.addSubview(image)
        addLabel(title, to: optionsView, frame: NSRect(x: 53, y: y + 5, width: 150, height: 20), size: 13)
        control.frame = NSRect(x: 218, y: y, width: 40, height: 30)
        control.target = self
        control.action = action
        control.setAccessibilityLabel(title)
        optionsView.addSubview(control)
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
