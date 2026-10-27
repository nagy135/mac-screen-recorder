import Foundation

public enum RecordingFile {
    /// Local time, with milliseconds and a collision suffix so previous clips survive.
    public static func destination(in directory: URL, at date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let timestamp = formatter.string(from: date)
        var candidate = directory.appendingPathComponent("\(timestamp).mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(timestamp)-\(suffix).mp4")
            suffix += 1
        }
        return candidate
    }
}
