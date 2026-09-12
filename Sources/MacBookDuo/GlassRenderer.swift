import AppKit
import SwiftUI
import MetalKit
import CoreImage

/// One compositor is shared by the preview and the desktop overlay.
final class GlassRenderer: NSObject, MTKViewDelegate {
    let context: CIContext
    let queue: MTLCommandQueue
    var source: CIImage?
    var progress = 1.0
    var frost = 0.7
    var depth = 0.65
    var edgeSoftness = 0.6
    var dispersion = 0.35
    private var smoothProgress = 1.0
    private var previousTime = CACurrentMediaTime()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(device: MTLDevice) {
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        queue = device.makeCommandQueue()!
        super.init()
    }
    func resetProgress(_ value: Double) {
        progress = value
        smoothProgress = value
        previousTime = CACurrentMediaTime()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let source, let drawable = view.currentDrawable, let command = queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - previousTime)
        previousTime = now
        smoothProgress += (progress - smoothProgress) * (1 - exp(-dt * 22))
        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }
        let output = compose(source, size: size, progress: smoothProgress)
        context.render(output, to: drawable.texture, commandBuffer: command,
                       bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        command.present(drawable)
        command.commit()
        if abs(smoothProgress - progress) < 0.0005 { view.isPaused = true }
    }
    func compose(_ source: CIImage, size: CGSize, progress: Double) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let w = size.width, h = size.height
        let scale = max(w / source.extent.width, h / source.extent.height)
        let scaled = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let base = scaled.transformed(by: CGAffineTransform(translationX: (w - scaled.extent.width) / 2, y: (h - scaled.extent.height) / 2)).cropped(to: rect)
        let p = EffectMath.eased(min(1, max(0, progress)))
        let closure = 1 - p
        if closure < 0.0001 { return base }
        let radius = closure * frost * 48 * w / 1500
        let blurred = base.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: rect)
        // A travelling clear-to-frost gradient makes the lower edge resolve first.
        let mask = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: h * (p - 0.35)),
            "inputPoint1": CIVector(x: 0, y: h * (p + 0.45)),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1)
        ])!.outputImage!.cropped(to: rect)
        let softBase = base.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: closure * closure * frost * 18 * w / 1500]).cropped(to: rect)
        let glass = blurred.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: softBase, kCIInputMaskImageKey: mask])
        let wash = CIImage(color: CIColor(red: 0.83, green: 0.91, blue: 1, alpha: closure * frost * 0.24)).cropped(to: rect)
        let content = wash.composited(over: glass)
        let inset = w * 0.09 * closure * depth
        let bottom = h * 0.035 * closure * depth
        let top = h * (1 - 0.52 * closure * depth)
        let background = CIImage(color: .black).cropped(to: rect)
        // Feather the desktop into black inside the glass plane, so its silhouette
        // stays soft even while perspective changes. All edge effects vanish at open.
        let feather = closure * (18 * w / 1500 + min(w, h) * 0.045) * edgeSoftness / 0.6
        let insetMask = rect.insetBy(dx: feather * 1.5, dy: feather * 1.5)
        let edgeMask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: insetMask),
            "inputRadius": closure * 28 * w / 1500 + feather * 0.5,
            "inputColor": CIColor.white
        ])!.outputImage!
            .composited(over: background)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather * 0.5])
            .cropped(to: rect)
        let feathered = content.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: edgeMask
        ])
        // Slightly different optical magnification per RGB channel creates a
        // restrained red/cyan fringe near the perimeter, with no offset at center.
        let channelShift = closure * (1.5 + frost * 3.5) * w / 1500 * dispersion / 0.35
        func colorPlane(_ index: Int, magnification: CGFloat) -> CIImage {
            let shifted = feathered.clampedToExtent().transformed(by:
                CGAffineTransform(translationX: w * 0.5, y: h * 0.5)
                    .scaledBy(x: magnification, y: magnification)
                    .translatedBy(x: -w * 0.5, y: -h * 0.5)
            ).cropped(to: rect)
            let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
            return shifted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": index == 0 ? CIVector(x: 1, y: 0, z: 0, w: 0) : zero,
                "inputGVector": index == 1 ? CIVector(x: 0, y: 1, z: 0, w: 0) : zero,
                "inputBVector": index == 2 ? CIVector(x: 0, y: 0, z: 1, w: 0) : zero
            ])
        }
        let red = colorPlane(0, magnification: 1 + channelShift * 2 / w)
        let green = colorPlane(1, magnification: 1)
        let blue = colorPlane(2, magnification: 1 - channelShift * 2 / w)
        let panel = red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
        let transformed = panel.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: inset, y: top),
            "inputTopRight": CIVector(x: w - inset, y: top),
            "inputBottomLeft": CIVector(x: inset * 0.18, y: bottom),
            "inputBottomRight": CIVector(x: w - inset * 0.18, y: bottom)
        ])
        return transformed.composited(over: background).cropped(to: rect)
    }
}

struct GlassPreview: NSViewRepresentable {
    @ObservedObject var model: DuoModel
    func makeNSView(context: Context) -> MTKView { model.makeView(overlay: false) }
    func updateNSView(_ view: MTKView, context: Context) { model.updateRenderers() }
}
