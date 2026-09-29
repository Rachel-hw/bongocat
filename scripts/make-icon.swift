import AppKit

// A simple original paw glyph, rendered locally for the application bundle.
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let unit = CGFloat(pixels) / 1024
        NSGraphicsContext.current!.imageInterpolation = .high
        NSColor(calibratedRed: 0.04, green: 0.48, blue: 0.48, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 55 * unit, y: 55 * unit, width: 914 * unit, height: 914 * unit),
                     xRadius: 210 * unit, yRadius: 210 * unit).fill()
        NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.85, alpha: 1).setFill()
        for (x, y, w, h) in [(319.0, 245.0, 386.0, 310.0), (205, 510, 150, 195),
                             (367, 629, 138, 190), (533, 629, 138, 190), (689, 510, 140, 195)] {
            NSBezierPath(ovalIn: NSRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
