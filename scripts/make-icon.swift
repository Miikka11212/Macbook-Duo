import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 218, yRadius: 218)
    NSGradient(colors: [NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.15, alpha: 1), NSColor(calibratedRed: 0.23, green: 0.29, blue: 0.46, alpha: 1)])!.draw(in: base, angle: 75)
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.4); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -20); shadow.set()
    let panel = NSBezierPath(); panel.move(to: NSPoint(x: 230, y: 340)); panel.line(to: NSPoint(x: 195, y: 749)); panel.curve(to: NSPoint(x: 242, y: 804), controlPoint1: NSPoint(x: 190, y: 788), controlPoint2: NSPoint(x: 208, y: 804)); panel.line(to: NSPoint(x: 780, y: 804)); panel.curve(to: NSPoint(x: 828, y: 749), controlPoint1: NSPoint(x: 818, y: 804), controlPoint2: NSPoint(x: 832, y: 788)); panel.line(to: NSPoint(x: 793, y: 340)); panel.close()
    NSGradient(colors: [NSColor(calibratedRed: 0.48, green: 0.59, blue: 0.90, alpha: 1), NSColor(calibratedRed: 0.80, green: 0.88, blue: 1, alpha: 1)])!.draw(in: panel, angle: 70)
    NSShadow().set(); NSColor.white.withAlphaComponent(0.8).setStroke(); panel.lineWidth = 5; panel.stroke()
    let bottom = NSBezierPath(); bottom.move(to: NSPoint(x: 230, y: 323)); bottom.line(to: NSPoint(x: 793, y: 323)); bottom.line(to: NSPoint(x: 893, y: 230)); bottom.curve(to: NSPoint(x: 850, y: 202), controlPoint1: NSPoint(x: 901, y: 210), controlPoint2: NSPoint(x: 868, y: 202)); bottom.line(to: NSPoint(x: 174, y: 202)); bottom.curve(to: NSPoint(x: 131, y: 230), controlPoint1: NSPoint(x: 156, y: 202), controlPoint2: NSPoint(x: 123, y: 210)); bottom.close()
    NSColor(calibratedRed: 0.65, green: 0.74, blue: 0.93, alpha: 0.72).setFill(); bottom.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
}
