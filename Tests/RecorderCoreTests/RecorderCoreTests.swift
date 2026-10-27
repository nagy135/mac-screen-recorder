import Foundation
import Testing
@testable import RecorderCore

@Test func timestampedMP4NeverOverwritesExistingClips() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Date(timeIntervalSince1970: 1_700_000_000.123)
    let first = try RecordingFile.destination(in: directory, at: date)
    #expect(first.pathExtension == "mp4")
    #expect(first.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}\.mp4$"#, options: .regularExpression) != nil)
    try Data("existing recording".utf8).write(to: first)
    let second = try RecordingFile.destination(in: directory, at: date)
    #expect(second.deletingPathExtension().lastPathComponent.hasSuffix("-2"))
    try Data().write(to: second)
    let third = try RecordingFile.destination(in: directory, at: date)
    #expect(third.deletingPathExtension().lastPathComponent.hasSuffix("-3"))
    #expect(try String(contentsOf: first, encoding: .utf8) == "existing recording")
}

@Test func cannotSaveIntoAFile() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data().write(to: file)
    #expect(throws: (any Error).self) { try RecordingFile.destination(in: file) }
}

@Test(arguments: [
    (1920, 1080, 1920, 1080),
    (5120, 2880, 3840, 2160),
    (2560, 1440, 2560, 1440),
    (3440, 1440, 3440, 1440),
    (2160, 3840, 1214, 2160),
    (1513, 983, 1512, 982),
    (0, 0, 2, 2),
])
func captureFitsEncoderLimits(width: Int, height: Int, expectedWidth: Int, expectedHeight: Int) {
    let dimensions = CaptureDimensions(width: width, height: height)
    #expect(dimensions.width == expectedWidth)
    #expect(dimensions.height == expectedHeight)
    #expect(dimensions.width % 2 == 0 && dimensions.height % 2 == 0)
    #expect(dimensions.width <= 3840 && dimensions.height <= 2160)
}

@Test func hoveringAtLastSecondPausesAndRestartsTheEntireCountdown() {
    var countdown = CountdownState()
    countdown.tick()
    countdown.tick()
    #expect(countdown.remainingSeconds == 1)

    countdown.setHovering(true)
    for _ in 0..<10 { countdown.tick() }
    #expect(countdown.isPaused)
    #expect(countdown.remainingSeconds == 3)
    #expect(!countdown.isComplete)

    countdown.setHovering(false)
    countdown.tick()
    countdown.tick()
    #expect(!countdown.isComplete)
    countdown.tick()
    #expect(countdown.isComplete)
}

@Test func leavingDuringPermissionPromptDoesNotStartRecording() {
    var countdown = CountdownState()
    countdown.setHovering(true)
    countdown.setWaitingForPermission(true)
    countdown.setHovering(false)
    for _ in 0..<10 { countdown.tick() }
    #expect(countdown.isPaused)
    #expect(countdown.remainingSeconds == 3)

    countdown.setWaitingForPermission(false)
    #expect(!countdown.isPaused)
    countdown.tick()
    #expect(countdown.remainingSeconds == 2)
}

@Test func permissionCompletingWhileHoveringKeepsCountdownPaused() {
    var countdown = CountdownState()
    countdown.setHovering(true)
    countdown.setWaitingForPermission(true)
    countdown.setWaitingForPermission(false)
    countdown.tick()
    #expect(countdown.isPaused)
    #expect(countdown.remainingSeconds == 3)
}

@Test func repeatedHoverEventsAndLateEventsCannotRestartCompletedCountdown() {
    var countdown = CountdownState()
    countdown.tick()
    countdown.setHovering(false)
    #expect(countdown.remainingSeconds == 2)
    countdown.tick()
    countdown.tick()
    countdown.setHovering(true)
    countdown.setWaitingForPermission(true)
    countdown.tick()
    #expect(countdown.isComplete)
    #expect(!countdown.isPaused)
}
