import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift generate-icon.swift <AppIcon.iconset>")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawCamera() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.23, blue: 0.31, alpha: 1),
               ending: NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.16, alpha: 1))!
        .draw(in: tile, angle: -90)

    let body = NSBezierPath(roundedRect: NSRect(x: 240, y: 318, width: 544, height: 366), xRadius: 68, yRadius: 68)
    let housing = NSBezierPath()
    housing.move(to: NSPoint(x: 354, y: 660))
    housing.line(to: NSPoint(x: 390, y: 724))
    housing.curve(to: NSPoint(x: 416, y: 740), controlPoint1: NSPoint(x: 396, y: 735), controlPoint2: NSPoint(x: 404, y: 740))
    housing.line(to: NSPoint(x: 562, y: 740))
    housing.curve(to: NSPoint(x: 588, y: 724), controlPoint1: NSPoint(x: 574, y: 740), controlPoint2: NSPoint(x: 582, y: 735))
    housing.line(to: NSPoint(x: 624, y: 660))
    housing.close()
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    body.fill()
    housing.fill()
    NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.33, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 374, y: 366, width: 280, height: 280)).fill()
    NSColor(calibratedRed: 0.35, green: 0.47, blue: 0.60, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 400, y: 392, width: 228, height: 228)).fill()
    NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 418, y: 410, width: 192, height: 192)).fill()
    NSColor(calibratedWhite: 1, alpha: 0.28).setFill()
    NSBezierPath(ovalIn: NSRect(x: 452, y: 526, width: 54, height: 38)).fill()
    NSColor(calibratedRed: 0.96, green: 0.22, blue: 0.25, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 688, y: 601, width: 40, height: 40)).fill()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        drawCamera()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
