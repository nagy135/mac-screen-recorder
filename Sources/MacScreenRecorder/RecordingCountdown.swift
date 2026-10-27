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
    private let optionsView = CountdownOptionsView()
    private let number = NSTextField(labelWithString: "3")
    private let numberMotion = NSView()
    private let titleMotion = NSView()
    private let startingLabel = NSTextField(labelWithString: "Starting recording")
    private let hoverHint = NSTextField(labelWithString: "Hover for options")
    private let audioTitle = NSTextField(labelWithString: "Audio")
    private let cancelButton = NSButton()
    private let systemAudioSwitch = NSSwitch()
    private let microphoneSwitch = NSSwitch()
    private let settingsButton = NSButton()
    private var steps: [NSView] = []
    private var audioRows: [NSView] = []
    private var shortcutHints: [NSView] = []
    private var state = CountdownState()
    private var audio = RecordingAudioSettings()
    private var timer: Task<Void, Never>?
    private var continuation: CheckedContinuation<RecordingAudioSettings?, Never>?
    private var runID = UUID()
    private var showingOptions = false
    private var transitionTimer: Timer?
    private var transitionProgress = 0.0
    private var transitionVelocity = 0.0
    private var transitionTime = 0.0
    private var transitionCenter = NSPoint.zero
    private let microphoneAuthorizationStatus: () -> AVAuthorizationStatus
    private let requestMicrophoneAccess: () async -> Bool
    private let reduceMotion: () -> Bool

    init(microphoneAuthorizationStatus: @escaping () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }, requestMicrophoneAccess: @escaping () async -> Bool = {
        await AVCaptureDevice.requestAccess(for: .audio)
    }, reduceMotion: @escaping () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }) {
        self.microphoneAuthorizationStatus = microphoneAuthorizationStatus
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.reduceMotion = reduceMotion
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
        countdownView.identifier = NSUserInterfaceItemIdentifier("countdown-content")
        glass.addSubview(countdownView)
        numberMotion.frame = bounds
        numberMotion.wantsLayer = true
        countdownView.addSubview(numberMotion)
        number.font = .monospacedDigitSystemFont(ofSize: 72, weight: .medium)
        number.textColor = .white
        number.alignment = .center
        number.frame = NSRect(x: 20, y: 65, width: 140, height: 92)
        number.setAccessibilityLabel("Recording countdown")
        numberMotion.addSubview(number)
        addLabel("Starting recording", to: countdownView,
                 frame: NSRect(x: 10, y: 40, width: 160, height: 18), size: 12, centered: true,
                 label: startingLabel)
        addLabel("Hover for options", to: countdownView,
                 frame: NSRect(x: 10, y: 5, width: 160, height: 14), size: 10, centered: true,
                 label: hoverHint)
        for index in 0..<3 {
            let step = NSView(frame: NSRect(x: 69 + index * 16, y: 25, width: 10, height: 4))
            step.wantsLayer = true
            step.identifier = NSUserInterfaceItemIdentifier("countdown-segment-\(index)")
            step.layer?.mask = CAShapeLayer()
            glass.addSubview(step)
            steps.append(step)
        }

        optionsView.frame = NSRect(x: -30, y: 0, width: 240, height: 184)
        optionsView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        optionsView.wantsLayer = true
        optionsView.isHidden = true
        glass.addSubview(optionsView)
        titleMotion.frame = NSRect(x: 0, y: 0, width: 240, height: 184)
        titleMotion.wantsLayer = true
        optionsView.addSubview(titleMotion)
        addLabel("Audio", to: titleMotion,
                 frame: NSRect(x: 20, y: 148, width: 140, height: 20), size: 13, bold: true,
                 label: audioTitle)
        cancelButton.frame = NSRect(x: 166, y: 146, width: 58, height: 24)
        cancelButton.title = "Cancel"
        cancelButton.font = .systemFont(ofSize: 11, weight: .semibold)
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 7
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
        settingsButton.frame = NSRect(x: 137, y: 5, width: 18, height: 20)
        settingsButton.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .systemOrange
        settingsButton.toolTip = "Allow microphone access in System Settings"
        settingsButton.setAccessibilityLabel("Open microphone permissions")
        settingsButton.target = self
        settingsButton.action = #selector(openMicrophoneSettings)
        settingsButton.isHidden = true
        audioRows[1].addSubview(settingsButton)
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
        stopTransition()
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
        countdownView.setAccessibilityHidden(visible)
        optionsView.setAccessibilityHidden(!visible)
        if transitionTimer == nil {
            transitionCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        }
        guard panel.isVisible, !reduceMotion() else {
            stopTransition()
            transitionProgress = visible ? 1 : 0
            applyTransition(settled: true)
            return
        }

        countdownView.isHidden = false
        optionsView.isHidden = false
        guard transitionTimer == nil else { return }
        transitionTime = CACurrentMediaTime()
        let animation = Timer(timeInterval: 1.0 / 60, target: self,
                              selector: #selector(advanceTransition), userInfo: nil, repeats: true)
        transitionTimer = animation
        // Continue while a switch or button is tracking the pointer.
        RunLoop.main.add(animation, forMode: .common)
        applyTransition(settled: false)
    }

    @objc private func advanceTransition() {
        let now = CACurrentMediaTime()
        let delta = min(now - transitionTime, 0.032)
        transitionTime = now
        let target = showingOptions ? 1.0 : 0.0
        if reduceMotion() {
            transitionProgress = target
            stopTransition()
            applyTransition(settled: true)
            return
        }
        // Exact critically damped spring; retarget without discarding position or velocity.
        let displacement = transitionProgress - target
        let coefficient = transitionVelocity + 19 * displacement
        let decay = exp(-19 * delta)
        transitionProgress = target + (displacement + coefficient * delta) * decay
        transitionVelocity = (transitionVelocity - 19 * coefficient * delta) * decay
        let settled = abs(target - transitionProgress) < 0.0005 && abs(transitionVelocity) < 0.008
        if settled {
            transitionProgress = target
            stopTransition()
        }
        applyTransition(settled: settled)
    }

    private func stopTransition() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        transitionVelocity = 0
    }

    private func applyTransition(settled: Bool) {
        let progress = min(1, max(0, transitionProgress))
        let width = 180 + 60 * progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(NSRect(x: transitionCenter.x - width / 2, y: transitionCenter.y - 92,
                              width: width, height: 184), display: true)
        countdownView.frame = NSRect(x: (width - 180) / 2, y: 0, width: 180, height: 184)
        optionsView.frame = NSRect(x: (width - 240) / 2, y: 0, width: 240, height: 184)
        countdownView.alphaValue = 1
        optionsView.alphaValue = 1
        numberMotion.alphaValue = 1 - smoothstep(0.04, 0.52, progress)
        let scale = 1 - 0.42 * progress
        var numeralTransform = CATransform3DMakeScale(scale, scale, 1)
        numeralTransform.m41 = 90 * (1 - scale) - 69 * progress
        numeralTransform.m42 = 111 * (1 - scale) + 47 * progress
        numberMotion.layer?.sublayerTransform = numeralTransform
        startingLabel.alphaValue = 1 - smoothstep(0.02, 0.40, progress)
        startingLabel.setFrameOrigin(NSPoint(x: 10 - 16 * progress, y: 40 + 10 * progress))
        hoverHint.alphaValue = 1 - smoothstep(0, 0.25, progress)
        titleMotion.alphaValue = smoothstep(0.35, 0.91, progress)
        titleMotion.layer?.sublayerTransform = CATransform3DMakeTranslation(
            69 * (1 - progress), -47 * (1 - progress), 0
        )
        for (index, row) in audioRows.enumerated() {
            row.alphaValue = smoothstep(index == 0 ? 0.44 : 0.53, index == 0 ? 0.91 : 0.98, progress)
            row.setFrameOrigin(NSPoint(x: 20, y: (index == 0 ? 107 : 71) - (index == 0 ? 7 : 9) * (1 - progress)))
        }
        for hint in shortcutHints {
            hint.alphaValue = smoothstep(0.61, 1, progress)
            hint.setFrameOrigin(NSPoint(x: hint.frame.minX, y: 21 - 5 * (1 - progress)))
        }
        applySegments(progress: progress, width: width)
        optionsView.acceptsInteraction = showingOptions && progress > 0.65
        if settled {
            countdownView.isHidden = showingOptions
            optionsView.isHidden = !showingOptions
            panel.invalidateShadow()
        }
        CATransaction.commit()
    }

    private func applySegments(progress: Double, width: Double) {
        let travel = smoothstep(0.04, 0.94, progress)
        let widen = smoothstep(0.28, 0.93, progress)
        let railWidth = 42 + 16 * widen
        let gap = 6 * (1 - widen)
        let segmentWidth = (railWidth - 2 * gap) / 3
        let height = 4 + 20 * widen
        let center = NSPoint(x: width / 2 + 75 * travel, y: 27 + 131 * travel)
        // The real hit target follows the red capsule as its label appears.
        cancelButton.setFrameOrigin(NSPoint(x: 166 + 75 * (travel - 1), y: center.y - 12))
        cancelButton.alphaValue = smoothstep(0.66, 0.96, progress)
        for (index, step) in steps.enumerated() {
            step.frame = NSRect(x: center.x - railWidth / 2 + Double(index) * (segmentWidth + gap),
                                y: center.y - height / 2, width: segmentWidth + 0.25 * widen, height: height)
            let innerRadius = 2 * (1 - widen)
            let leftRadius = index == 0 ? 2 + 5 * widen : innerRadius
            let rightRadius = index == 2 ? 2 + 5 * widen : innerRadius
            if let mask = step.layer?.mask as? CAShapeLayer {
                mask.frame = step.bounds
                mask.path = segmentPath(size: step.bounds.size, left: leftRadius, right: rightRadius)
            }
            let glow = index < state.remainingSeconds ? 1 : smoothstep(0, 0.35, progress)
            step.layer?.backgroundColor = NSColor.systemRed.blended(
                withFraction: 1 - glow, of: NSColor.white.withAlphaComponent(0.2)
            )?.cgColor
        }
    }

    private func segmentPath(size: NSSize, left: Double, right: Double) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: size.width - right, y: 0))
        path.addQuadCurve(to: CGPoint(x: size.width, y: right), control: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: size.height - right))
        path.addQuadCurve(to: CGPoint(x: size.width - right, y: size.height), control: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: left, y: size.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: size.height - left), control: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: left))
        path.addQuadCurve(to: CGPoint(x: left, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }

    private func smoothstep(_ start: Double, _ end: Double, _ value: Double) -> Double {
        let progress = min(1, max(0, (value - start) / (end - start)))
        return progress * progress * (3 - 2 * progress)
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
                          size: CGFloat, centered: Bool = false, bold: Bool = false,
                          label suppliedLabel: NSTextField? = nil) {
        let label = suppliedLabel ?? NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: bold ? .semibold : .medium)
        label.textColor = NSColor.white.withAlphaComponent(bold ? 1 : 0.75)
        label.alignment = centered ? .center : .left
        view.addSubview(label)
    }

    private func addAudioRow(_ title: String, symbol: String, y: CGFloat,
                             control: NSSwitch, action: Selector) {
        let row = NSView(frame: NSRect(x: 20, y: y, width: 200, height: 30))
        row.wantsLayer = true
        optionsView.addSubview(row)
        audioRows.append(row)
        let image = NSImageView(frame: NSRect(x: 0, y: 5, width: 18, height: 20))
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        row.addSubview(image)
        addLabel(title, to: row, frame: NSRect(x: 26, y: 5, width: 110, height: 20), size: 12)
        control.frame = NSRect(x: 164, y: 0, width: 36, height: 30)
        control.target = self
        control.action = action
        control.setAccessibilityLabel(title)
        row.addSubview(control)
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
        shortcutHints.append(group)
    }
}

@MainActor
private final class CountdownOptionsView: NSView {
    var acceptsInteraction = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        acceptsInteraction ? super.hitTest(point) : nil
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
