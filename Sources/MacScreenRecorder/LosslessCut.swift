import AppKit

enum LosslessCut {
    @MainActor
    static func open(_ video: URL) async throws {
        let workspace = NSWorkspace.shared
        let standardLocations = [
            URL(fileURLWithPath: "/Applications/LosslessCut.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/LosslessCut.app", isDirectory: true),
        ]
        let application = workspace.urlForApplication(withBundleIdentifier: "no.mifi.losslesscut-mac")
            ?? workspace.urlForApplication(withBundleIdentifier: "no.mifi.losslesscut")
            ?? standardLocations.first { FileManager.default.fileExists(atPath: $0.path) }
        guard let application else { throw OpenError.notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await workspace.open([video], withApplicationAt: application, configuration: configuration)
    }

    private enum OpenError: LocalizedError {
        case notInstalled

        var errorDescription: String? {
            "LosslessCut was not found. Install it with brew install --cask losslesscut, then open the saved MP4."
        }
    }
}
