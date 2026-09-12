import AppKit

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: make-icon.swift <destination> <source-logo.png>")
}
let destination = CommandLine.arguments[1]
guard let logo = NSImage(contentsOfFile: CommandLine.arguments[2]), logo.isValid else {
    fatalError("Cannot load source logo: \(CommandLine.arguments[2])")
}
let directory = URL(fileURLWithPath: destination).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.interpolationQuality = .high
        let unit = CGFloat(pixels) / 1024
        context.scaleBy(x: unit, y: unit)
        let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
        NSBezierPath(roundedRect: rect, xRadius: 198, yRadius: 198).addClip()
        logo.draw(in: rect, from: .zero, operation: .copy, fraction: 1,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", URL(fileURLWithPath: destination).appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: directory)
