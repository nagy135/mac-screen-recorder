import AppKit
import RecorderCore

/// Records a short clip through the production Recorder without opening Finder.
/// Microphone modes require an existing macOS permission grant.
@main
struct AudioRecordingCheck {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let recorder = Recorder()
        let audio = RecordingAudioSettings(
            systemAudio: CommandLine.arguments.contains("--system-audio"),
            microphone: CommandLine.arguments.contains("--microphone")
        )
        recorder.beforeCapture = { audio }
        recorder.onPhaseChange = { phase in
            if case .recording = phase {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    recorder.stop()
                }
            }
        }
        recorder.onFinish = { url in
            guard let url else { fatalError("Recording was cancelled") }
            print(url.path)
            app.terminate(nil)
        }
        recorder.onFailure = { error in
            FileHandle.standardError.write(Data("Audio recording check failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        Task { await recorder.start() }
        withExtendedLifetime(recorder) { app.run() }
    }
}
