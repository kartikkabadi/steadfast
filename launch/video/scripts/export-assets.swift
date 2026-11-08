// Exports real SF Symbols (as template PNGs) and installed app icons for the film.
import AppKit

let out = CommandLine.arguments[1]
func savePNG(_ image: NSImage, _ size: NSSize, _ path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let symbols: [(String, NSFont.Weight)] = [
    ("lock.fill", .medium), ("hourglass", .medium), ("xmark", .regular), ("chevron.right", .medium),
    ("magnifyingglass", .regular), ("checkmark.circle.fill", .semibold), ("gearshape", .medium), ("play.rectangle", .regular),
    ("camera", .regular), ("bubble", .regular), ("text.bubble", .regular), ("music.note", .regular), ("tv", .regular),
    ("plus", .regular), ("arrow.right", .regular), ("calendar.badge.clock", .regular), ("star", .medium), ("ellipsis", .medium),
    ("xmark.circle.fill", .regular), ("minus.circle", .semibold), ("person.crop.circle.badge.xmark", .regular),
    ("chart.bar.xaxis", .regular), ("icloud.slash", .regular),
    ("arrow.clockwise", .medium), ("chevron.left", .medium), ("square.and.arrow.up", .regular),
    ("sidebar.left", .regular), ("exclamationmark.triangle.fill", .regular),
    ("macwindow", .regular), ("power", .medium)
]
for (name, weight) in symbols {
    let config = NSImage.SymbolConfiguration(pointSize: 96, weight: weight)
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        print("missing \(name)"); continue
    }
    let s = img.size
    let scale: CGFloat = 2
    savePNG(img, NSSize(width: s.width * scale, height: s.height * scale), "\(out)/sym/\(name).png")
    print("sym \(name) \(Int(s.width))x\(Int(s.height))")
}
let apps = ["/Applications/Spotify.app", "/Applications/WhatsApp.app", "/Applications/Google Chrome.app",
            "/System/Applications/Messages.app", "/System/Applications/Music.app", "/Applications/Xcode.app"]
for path in apps where FileManager.default.fileExists(atPath: path) {
    let icon = NSWorkspace.shared.icon(forFile: path)
    let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "").lowercased().replacingOccurrences(of: " ", with: "-")
    savePNG(icon, NSSize(width: 512, height: 512), "\(out)/apps/\(name).png")
    print("app \(name)")
}
