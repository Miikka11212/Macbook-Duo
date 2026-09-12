import AppKit
import ScreenCaptureKit
import CoreImage

/// Opt-in integration check, run inside the signed app with --capture-check PATH.
/// Only pass/fail metrics are written; desktop pixels remain in memory.
enum CaptureCheck {
    @MainActor static func run(to path: String) async {
        var report: [String: Any] = [:]
        var windows: [NSWindow] = []
        defer {
            windows.forEach { $0.orderOut(nil) }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            NSApp.terminate(nil)
        }
        do {
            guard CGPreflightScreenCaptureAccess() else {
                throw NSError(domain: "CaptureCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Screen recording permission required"])
            }
            guard let screen = NSScreen.screens.first(where: {
                guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
                return CGDisplayIsBuiltin(id) != 0
            }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return }
            let settings = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            settings.isReleasedWhenClosed = false
            windows.append(settings)
            settings.orderFrontRegardless()
            try await Task.sleep(nanoseconds: 150_000_000)
            settings.orderOut(nil)
            let context = CIContext()
            let config = SCStreamConfiguration()
            config.width = 320; config.height = 200; config.showsCursor = false
            var rounds: [[String: Any]] = []
            for round in 0..<3 {
                try await Task.sleep(nanoseconds: 200_000_000)
                let oldContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let oldHasSelf = oldContent.applications.contains { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let (filter, display) = try await DesktopCapture.contentFilter(displayID: id)
                // This window deliberately does not exist when the filter is built.
                let overlay = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                overlay.isReleasedWhenClosed = false
                overlay.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
                overlay.isOpaque = true; overlay.hasShadow = false; overlay.ignoresMouseEvents = true
                overlay.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
                windows.append(overlay)
                overlay.orderFrontRegardless()
                try await Task.sleep(nanoseconds: 200_000_000)
                func markerFraction(_ image: CGImage) -> Double {
                    let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
                    var bytes = [UInt8](repeating: 0, count: 320 * 200 * 4)
                    context.render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: 320 * 4, bounds: bounds, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                    var matches = 0
                    for y in 30..<170 { for x in 30..<290 {
                        let i = (y * 320 + x) * 4
                        if bytes[i] > 240 && bytes[i + 1] < 20 && bytes[i + 2] > 240 { matches += 1 }
                    } }
                    return Double(matches) / Double(260 * 140)
                }
                let unfiltered = SCContentFilter(display: display, excludingWindows: [])
                let visible = markerFraction(try await SCScreenshotManager.captureImage(contentFilter: unfiltered, configuration: config))
                let excluded = markerFraction(try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
                overlay.orderOut(nil)
                let passed = visible > 0.95 && excluded < 0.05
                rounds.append(["round": round + 1, "onscreenQueryFoundSelf": oldHasSelf, "unfilteredMarkerFraction": visible, "excludedMarkerFraction": excluded, "passed": passed])
                report["rounds"] = rounds
                guard passed else { throw NSError(domain: "CaptureCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Effect window leaked into capture, or control window was not visible"] ) }
            }
            report["passed"] = true
        } catch {
            report["passed"] = false
            report["error"] = error.localizedDescription
        }
    }
}
