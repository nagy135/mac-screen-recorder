import AVFoundation
import CoreGraphics
import RecorderCore
import ScreenCaptureKit

@MainActor
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    enum Phase {
        case starting, recording, stopping, finished, failed
    }

    var onPhaseChange: ((Phase) -> Void)?
    var onFinish: ((URL?) -> Void)?
    var onFailure: ((Error) -> Void)?
    var beforeCapture: (() async -> Bool)?
    private(set) var phase: Phase = .starting {
        didSet { onPhaseChange?(phase) }
    }
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var frameProbe: FirstFrameProbe?
    private var destination: URL?
    private var captureStarted = false
    private var stopRequested = false
    private var stopInFlight = false
    private var terminal = false

    var isFinished: Bool { terminal }

    func start() async {
        do {
            StartupTiming.mark("permission_check_begin")
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                throw RecordingError.permission
            }
            StartupTiming.mark("permission_granted")
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            StartupTiming.mark("content_discovered")
            // A click/hotkey while content is loading must cancel rather than start a hidden capture.
            guard !stopRequested else {
                finishWithoutRecording()
                return
            }
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
                throw RecordingError.noDisplay
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let dimensions = CaptureDimensions(
                width: Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)),
                height: Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            )
            let config = SCStreamConfiguration()
            config.width = dimensions.width
            config.height = dimensions.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 5
            config.showsCursor = true
            config.capturesAudio = false
            config.captureMicrophone = false
            config.captureDynamicRange = .SDR

            if let beforeCapture {
                guard await beforeCapture(), !stopRequested else {
                    finishWithoutRecording()
                    return
                }
            }

            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Videos", isDirectory: true)
            let url = try RecordingFile.destination(in: directory)
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = url
            recordingConfig.outputFileType = .mp4
            recordingConfig.videoCodecType = .h264
            guard recordingConfig.availableOutputFileTypes.contains(.mp4),
                  recordingConfig.availableVideoCodecTypes.contains(.h264) else {
                throw RecordingError.unsupportedFormat
            }

            let recordingOutput = SCRecordingOutput(configuration: recordingConfig, delegate: self)
            let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
            if StartupTiming.enabled {
                let probe = FirstFrameProbe()
                try captureStream.addStreamOutput(
                    probe, type: .screen,
                    sampleHandlerQueue: DispatchQueue(label: "com.nagy135.mac-screen-recorder.startup-timing")
                )
                frameProbe = probe
            }
            // Attach before capture starts so the first frame reaches the file.
            try captureStream.addRecordingOutput(recordingOutput)
            destination = url
            output = recordingOutput
            stream = captureStream
            StartupTiming.mark("start_capture_requested")
            try await captureStream.startCapture()
            StartupTiming.mark("start_capture_returned")
            captureStarted = true
            // Covers a stop arriving while startCapture was suspended.
            if stopRequested { await stopCapture() }
        } catch {
            fail(error)
        }
    }

    func stop() {
        guard !terminal, !stopRequested else { return }
        stopRequested = true
        phase = .stopping
        if captureStarted {
            Task { await stopCapture() }
        }
    }

    private func stopCapture() async {
        guard !terminal, !stopInFlight, let stream else { return }
        stopInFlight = true
        do {
            try await stream.stopCapture()
            // Keep stream/output alive; didFinishRecording is the file-ready signal.
        } catch {
            fail(error)
        }
    }

    private func finishWithoutRecording() {
        terminal = true
        phase = .finished
        onFinish?(nil)
    }

    private func fail(_ error: Error) {
        guard !terminal else { return }
        terminal = true
        phase = .failed
        // Tear down capture before displaying an error. Keep any partial file for recovery.
        let currentStream = stream
        Task {
            if let currentStream { try? await currentStream.stopCapture() }
            stream = nil
            output = nil
            onFailure?(error)
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let callbackTime = DispatchTime.now().uptimeNanoseconds
        let identifier = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let output, ObjectIdentifier(output) == identifier, !terminal else { return }
            StartupTiming.mark("recording_output_started", at: callbackTime)
            if !stopRequested { phase = .recording }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let identifier = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let output, ObjectIdentifier(output) == identifier, !terminal else { return }
            terminal = true
            phase = .finished
            self.stream = nil
            self.output = nil
            onFinish?(destination)
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.fail(error) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in self?.fail(error) }
    }
}

enum RecordingError: LocalizedError {
    case permission, noDisplay, unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .permission:
            "Allow Mac Screen Recorder in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app."
        case .noDisplay:
            "No display is available to record. Connect a display and reopen the app."
        case .unsupportedFormat:
            "This Mac does not report support for recording H.264 MP4 files."
        }
    }
}
