public struct CaptureDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    /// Keep Retina detail where possible, bounded to 4K SDR for H.264 compatibility.
    /// The encoder needs even dimensions. Portrait and ultrawide aspect ratios survive.
    public init(width: Int, height: Int) {
        let sourceWidth = max(2, width)
        let sourceHeight = max(2, height)
        let scale = min(1, 3840.0 / Double(sourceWidth), 2160.0 / Double(sourceHeight))
        self.width = max(2, Int(Double(sourceWidth) * scale) / 2 * 2)
        self.height = max(2, Int(Double(sourceHeight) * scale) / 2 * 2)
    }
}
