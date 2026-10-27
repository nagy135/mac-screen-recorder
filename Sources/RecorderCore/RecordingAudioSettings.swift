/// Audio sources selected for one recording. New recordings start with audio off.
public struct RecordingAudioSettings: Equatable, Sendable {
    public var systemAudio: Bool
    public var microphone: Bool

    public init(systemAudio: Bool = false, microphone: Bool = false) {
        self.systemAudio = systemAudio
        self.microphone = microphone
    }
}
