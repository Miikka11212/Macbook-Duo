import AppKit
import CoreImage
import MetalKit

@main struct RenderTests {
    static func main() throws {
        _ = NSApplication.shared
        let renderer = GlassRenderer(device: MTLCreateSystemDefaultDevice()!)
        let source = DuoModel.sampleDesktop()
        let size = CGSize(width: 1280, height: 800)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = [0.0, 0.5, 1.0].map { renderer.compose(source, size: size, progress: $0) }
        for (i, image) in images.enumerated() {
            precondition(image.extent == CGRect(origin: .zero, size: size))
            try renderer.context.writePNGRepresentation(of: image, to: output.appendingPathComponent("angle-\(i * 60).png"), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        func pixels(_ image: CIImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: 1280 * 800 * 4)
            renderer.context.render(image, toBitmap: &data, rowBytes: 1280 * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return data
        }
        let opened = pixels(images[2])
        let sourceScale = 1280 / source.extent.width
        let expected = pixels(source.transformed(by: CGAffineTransform(scaleX: sourceScale, y: sourceScale)))
        precondition(opened == expected, "Fully open must reproduce source pixels exactly")
        let middle = pixels(images[1]); let closed = pixels(images[0])
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
        }
        precondition(difference(middle, opened) > 2, "Midpoint must visibly differ")
        precondition(difference(closed, middle) > 2, "Closed must visibly differ")
        precondition(stride(from: 3, to: opened.count, by: 4).allSatisfy { middle[$0] == 255 && closed[$0] == 255 }, "Compositor must fill the desktop without transparency holes")
        print("PASS: GPU rendering, image bounds, opaque composition, distinct transition states, pixel-exact open endpoint.")
    }
}
