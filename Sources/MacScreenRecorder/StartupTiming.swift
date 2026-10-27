import Foundation
import ScreenCaptureKit

/// Opt-in monotonic timestamps; normal launches do not log or observe frame buffers.
@MainActor
enum StartupTiming {
    static let enabled = CommandLine.arguments.contains("--measure-startup")
    private static let origin = DispatchTime.now().uptimeNanoseconds

    static func mark(_ stage: String, at timestamp: UInt64? = nil) {
        guard enabled else { return }
        let start = origin
        let now = timestamp ?? DispatchTime.now().uptimeNanoseconds
        let milliseconds = Double(now >= start ? now - start : 0) / 1_000_000
        let event: [String: Any] = ["stage": stage, "elapsed_ms": milliseconds]
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardError.write(Data("STARTUP_TIMING \(json)\n".utf8))
    }
}

/// Observe only the first complete sample's arrival; pixels are neither copied nor saved.
final class FirstFrameProbe: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var observed = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: status) == .complete else { return }
        let first = lock.withLock {
            guard !observed else { return false }
            observed = true
            return true
        }
        guard first else { return }
        let arrival = DispatchTime.now().uptimeNanoseconds
        Task { @MainActor in StartupTiming.mark("first_complete_frame_arrived", at: arrival) }
    }
}
