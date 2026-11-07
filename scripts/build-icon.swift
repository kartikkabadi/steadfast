import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let artwork = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("usage: build-icon.swift artwork.png output.iconset")
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("cannot render icon at \(pixels) pixels")
        }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let edge = CGFloat(pixels)
        let plate = NSRect(x: edge * 100 / 1024, y: edge * 100 / 1024,
            width: edge * 824 / 1024, height: edge * 824 / 1024)
        NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.2237,
            yRadius: plate.height * 0.2237).addClip()
        artwork.draw(in: plate)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("cannot encode icon")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
