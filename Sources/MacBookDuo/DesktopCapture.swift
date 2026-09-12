import AppKit
import ScreenCaptureKit
import CoreImage
import OSLog

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var cancelled = false
    private let queue = DispatchQueue(label: "duo.capture", qos: .userInteractive)
    var onFrame: ((CIImage) -> Void)?
    var onError: ((Error) -> Void)?

    private static let logger = Logger(subsystem: "studio.macbookduo.app", category: "capture")

    @MainActor static func contentFilter(displayID: CGDirectDisplayID) async throws -> (SCContentFilter, SCDisplay) {
        // Settings and the old overlay are hidden during wake recovery. Querying
        // only onscreen windows can omit our process and leave capture unfiltered.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "MacBookDuo", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到目标屏幕，请重新开启实时效果。"])
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier
        let candidates = content.applications + content.windows.compactMap(\.owningApplication)
        var seen = Set<pid_t>()
        let ownApps = candidates.filter {
            ($0.processID == pid || (bundleID != nil && $0.bundleIdentifier == bundleID)) && seen.insert($0.processID).inserted
        }
        guard ownApps.contains(where: { $0.processID == pid }) else {
            Self.logger.error("Capture deferred: the current process cannot be excluded")
            // Never display an effect backed by an unfiltered capture stream.
            throw NSError(domain: "MacBookDuo", code: 2, userInfo: [NSLocalizedDescriptionKey: "正在等待效果窗口排除就绪…"])
        }
        Self.logger.info("Capture filter ready; excluded application count: \(ownApps.count)")
        return (SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []), display)
    }

    @MainActor func start(displayID: CGDirectDisplayID) async throws {
        cancelled = false
        let (filter, display) = try await Self.contentFilter(displayID: displayID)
        let config = SCStreamConfiguration()
        // Cap resolution to keep two GPU blur passes inexpensive on a Retina display.
        let ratio = min(1.0, 1920.0 / Double(display.width))
        config.width = Int(Double(display.width) * ratio)
        config.height = Int(Double(display.height) * ratio)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        guard !cancelled else { throw CancellationError() }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        do {
            try await stream.startCapture()
            if cancelled { try? await stream.stopCapture() }
        }
        catch { self.stream = nil; throw error }
    }
    @MainActor func stop() async {
        cancelled = true
        let previous = stream
        stream = nil
        try? await previous?.stopCapture()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.cancelled, self.stream === stream else { return }
            self.onFrame?(image)
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.cancelled, self.stream === stream else { return }
            self.onError?(error)
        }
    }
}
