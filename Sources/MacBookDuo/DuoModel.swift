import AppKit
import SwiftUI
import MetalKit
import UniformTypeIdentifiers
import ScreenCaptureKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DuoModel: ObservableObject {
    @Published var sensorAngle: Double?
    @Published var manualAngle = 75.0 { didSet { updateRenderers() } }
    @Published var manual = true { didSet { updateRenderers() } }
    @Published var endpoint: Double { didSet { UserDefaults.standard.set(endpoint, forKey: "endpoint"); updateRenderers() } }
    @Published var frost: Double { didSet { UserDefaults.standard.set(frost, forKey: "frost"); updateRenderers() } }
    @Published var depth: Double { didSet { UserDefaults.standard.set(depth, forKey: "depth"); updateRenderers() } }
    @Published var edgeSoftness: Double { didSet { UserDefaults.standard.set(edgeSoftness, forKey: "edgeSoftness"); updateRenderers() } }
    @Published var dispersion: Double { didSet { UserDefaults.standard.set(dispersion, forKey: "dispersion"); updateRenderers() } }
    @Published private(set) var liveSession = LiveSessionState()
    @Published var autoResume: Bool {
        didSet {
            UserDefaults.standard.set(autoResume, forKey: "autoResume")
            liveSession.automaticResume = autoResume
            if !autoResume && !live && !starting { stop() }
            else if autoResume { scheduleRecovery(resetAttempts: true) }
        }
    }
    @Published private var wakeReveal = 1.0
    var liveEnabled: Bool { liveSession.enabled }
    @Published var imageName = "示例桌面"
    @Published var mode = "待机"
    @Published var live = false
    @Published var previewing = false
    @Published var starting = false
    @Published var message: String?
    @Published var controlsHidden = false
    @Published var needsCapturePermission = false
    @Published var capturePermissionReady = false
    private var requestedPermissionThisRun = false
    var restartApp: (() -> Void)?
    var showSettings: (() -> Void)?
    var hideSettings: (() -> Void)?
    var previewChanged: ((Bool) -> Void)?
    private let sensor = HingeSensor()
    private var capture: DesktopCapture?
    private var generation = 0
    private var renderers: [(MTKView, GlassRenderer, Bool)] = []
    private var overlay: OverlayWindow?
    private var screenshot: CIImage
    private var liveImage: CIImage?
    private var demoTimer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempts = 0
    private let recoveryDelays: [Double] = [0.15, 0.35, 0.75, 1.5, 2, 3, 5, 8]
    private var wakeTimer: Timer?
    private var revealOnResume = false
    let device = MTLCreateSystemDefaultDevice()!
    var angle: Double { manual ? manualAngle : (sensorAngle ?? endpoint) }
    var progress: Double { EffectMath.progress(angle: angle, endpoint: endpoint) * (live ? wakeReveal : 1) }
    var targetScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }
    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["endpoint": 120.0, "frost": 0.72, "depth": 0.7, "edgeSoftness": 0.6, "dispersion": 0.35, "autoResume": true])
        endpoint = min(180, max(20, defaults.double(forKey: "endpoint")))
        frost = min(1, max(0, defaults.double(forKey: "frost")))
        depth = min(1, max(0, defaults.double(forKey: "depth")))
        edgeSoftness = min(1, max(0, defaults.double(forKey: "edgeSoftness")))
        dispersion = min(1, max(0, defaults.double(forKey: "dispersion")))
        autoResume = defaults.bool(forKey: "autoResume")
        liveSession = LiveSessionState(enabled: defaults.bool(forKey: "liveEnabled") && defaults.bool(forKey: "autoResume"), automaticResume: defaults.bool(forKey: "autoResume"))
        screenshot = Self.sampleDesktop()
        if let url = try? Self.savedImageURL(), let image = CIImage(contentsOf: url) {
            screenshot = image
            imageName = defaults.string(forKey: "imageName") ?? "已导入截图"
        }
        sensor.onAngle = { [weak self] angle in
            guard let self else { return }
            let wasUnavailable = self.sensorAngle == nil
            if self.sensorAngle != angle { self.sensorAngle = angle }
            if self.live && angle == nil {
                self.captureInterrupted("等待铰链重新连接…")
            } else if wasUnavailable && angle != nil {
                self.scheduleRecovery(resetAttempts: true)
            }
            self.updateRenderers()
        }
        sensor.start()
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.liveEnabled {
                self.captureInterrupted("等待内置屏幕就绪…", resetAttempts: true)
            } else if self.previewing { self.stop() }
        }
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, LiveSessionState.Suspension, Bool)] = [
            (NSWorkspace.willSleepNotification, .system, true),
            (NSWorkspace.didWakeNotification, .system, false),
            (NSWorkspace.screensDidSleepNotification, .display, true),
            (NSWorkspace.screensDidWakeNotification, .display, false),
            (NSWorkspace.sessionDidResignActiveNotification, .session, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .session, false)
        ]
        workspaceObservers = events.map { name, reason, sleeping in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if sleeping { self?.suspendForSystem(reason) }
                else { self?.resumeFromSystem(reason) }
            }
        }

    }
    func makeView(overlay: Bool) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        let renderer = GlassRenderer(device: device)
        renderer.resetProgress(progress)
        view.delegate = renderer
        renderers.append((view, renderer, overlay))
        updateRenderers()
        return view
    }
    func updateRenderers() {
        for (view, renderer, isOverlay) in renderers {
            let nextSource = live ? (liveImage ?? screenshot) : screenshot
            let changed = renderer.source !== nextSource || abs(renderer.progress - progress) > 0.00001 || renderer.frost != frost || renderer.depth != depth || renderer.edgeSoftness != edgeSoftness || renderer.dispersion != dispersion
            renderer.source = nextSource
            renderer.progress = progress
            renderer.frost = frost
            renderer.depth = depth
            renderer.edgeSoftness = edgeSoftness
            renderer.dispersion = dispersion
            let hidden = isOverlay ? !(live || previewing) : (controlsHidden || (view.window?.isVisible == false))
            if hidden || (isOverlay && live && progress >= 1) { view.isPaused = true }
            else if changed { view.isPaused = false }
        }
        if live {
            // Clear the overlay at the endpoint: original desktop pixels remain untouched.
            overlay?.alphaValue = progress >= 1 ? 0 : 1
        } else { overlay?.alphaValue = 1 }
    }
    func resumePreview() {
        for (view, _, isOverlay) in renderers where !isOverlay { view.isPaused = false }
    }
    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url), let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        stop()
        screenshot = CIImage(cgImage: cg)
        imageName = url.lastPathComponent
        do {
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try png.write(to: Self.savedImageURL(), options: .atomic)
            UserDefaults.standard.set(imageName, forKey: "imageName")
        } catch { message = "图片已载入，但无法保存供下次使用：\(error.localizedDescription)" }
        manual = true
        updateRenderers()
    }
    func saveEndpoint() {
        let value = manual ? manualAngle : sensorAngle
        guard let value, value >= 20, value <= 180 else { message = "请将屏幕展开至 20°–180° 后保存。"; return }
        endpoint = value
        message = "已保存展开终点 \(Int(value))°。动画范围为 0°–\(Int(value))°。"
    }
    func saveHardwareEndpoint() {
        guard let value = sensorAngle, value >= 20 else { message = "当前没有可保存的铰链读数。"; return }
        endpoint = value
        message = "已将当前铰链角度 \(Int(value))° 保存为展开终点。"
    }
    func demo() {
        demoTimer?.invalidate()
        manual = true
        let start = Date()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = Date().timeIntervalSince(start) / 4.5
            if t >= 1 { self.manualAngle = self.endpoint; timer.invalidate(); self.demoTimer = nil; return }
            self.manualAngle = self.endpoint * (1 + cos(t * 2 * .pi)) / 2
        }
    }
    func preview() {
        stop()
        previewing = true
        mode = "截图调试"
        createOverlay(screen: targetScreen ?? NSScreen.main)
        previewChanged?(true)
        showSettings?()
        updateRenderers()
    }
    func toggleControls() {
        guard previewing else { return }
        controlsHidden.toggle()
        if controlsHidden { hideSettings?() } else { showSettings?() }
        updateRenderers()
    }
    func refreshCapturePermission() {
        let previouslyReady = capturePermissionReady
        capturePermissionReady = CGPreflightScreenCaptureAccess()
        if capturePermissionReady && !previouslyReady && liveEnabled {
            needsCapturePermission = false
            liveSession.interrupted()
            scheduleRecovery(resetAttempts: true)
        }
    }
    func openCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    private func saveLiveIntent() { UserDefaults.standard.set(liveEnabled, forKey: "liveEnabled") }
    func restoreLiveSession() {
        guard liveEnabled else { return }
        mode = "等待自动恢复…"
        scheduleRecovery(resetAttempts: true)
    }
    private func suspendForSystem(_ reason: LiveSessionState.Suspension) {
        if liveEnabled { revealOnResume = true }
        liveSession.suspend(reason)
        saveLiveIntent()
        cancelRecovery()
        sensor.setSuspended(true)
        tearDownCapture()
        if liveEnabled { mode = "休眠 · 等待开盖" }
    }
    private func resumeFromSystem(_ reason: LiveSessionState.Suspension) {
        liveSession.resume(reason)
        guard !liveSession.suspended else { return }
        sensor.setSuspended(false)
        if liveSession.canRecover {
            mode = "开盖 · 正在恢复…"
            scheduleRecovery(resetAttempts: true)
        }
    }
    private func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }
    private func scheduleRecovery(resetAttempts: Bool = false) {
        if resetAttempts { recoveryAttempts = 0 }
        guard liveSession.canRecover, !live, !starting, recoveryTask == nil else { return }
        guard recoveryAttempts < recoveryDelays.count else {
            mode = "等待设备就绪"
            return
        }
        let delay = recoveryDelays[recoveryAttempts]
        recoveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self else { return }
            self.recoveryTask = nil
            guard self.liveSession.canRecover, !self.live, !self.starting else { return }
            self.recoveryAttempts += 1
            self.startLive(userInitiated: false)
        }
    }
    private func captureInterrupted(_ status: String, resetAttempts: Bool = false) {
        guard liveEnabled else { return }
        tearDownCapture()
        liveSession.interrupted()
        mode = liveSession.suspended ? "休眠 · 等待开盖" : status
        if autoResume { scheduleRecovery(resetAttempts: resetAttempts) }
        else { stop() }
    }
    func toggleLive() {
        if liveEnabled { stop(); return }
        liveSession.enable()
        saveLiveIntent()
        recoveryAttempts = 0
        startLive(userInitiated: true)
    }
    func retryLive() {
        liveSession.enable()
        saveLiveIntent()
        recoveryAttempts = 0
        startLive(userInitiated: true)
    }
    private func startLive(userInitiated: Bool) {
        guard liveEnabled, !liveSession.suspended, !live, !starting else { return }
        cancelRecovery()
        guard let currentAngle = sensorAngle, currentAngle > 3 else {
            mode = "等待铰链就绪…"
            scheduleRecovery()
            return
        }
        guard let screen = targetScreen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
              CGDisplayIsActive(id) != 0 else {
            mode = "等待内置屏幕就绪…"
            scheduleRecovery()
            return
        }
        tearDownCapture()
        capturePermissionReady = CGPreflightScreenCaptureAccess()
        guard capturePermissionReady else {
            needsCapturePermission = true
            mode = "等待屏幕授权"
            // Wake/reconnect paths never create a privacy prompt or steal focus.
            if userInitiated {
                if !requestedPermissionThisRun {
                    requestedPermissionThisRun = true
                    _ = CGRequestScreenCaptureAccess()
                    refreshCapturePermission()
                }
                showSettings?()
            }
            return
        }
        needsCapturePermission = false
        manual = false
        starting = true
        mode = userInitiated ? "正在连接桌面…" : "自动恢复中…"
        generation += 1
        let token = generation
        let capture = DesktopCapture()
        self.capture = capture
        capture.onFrame = { [weak self] image in
            guard let self, self.generation == token, self.liveEnabled, !self.liveSession.suspended else { return }
            self.liveImage = image
            if self.starting {
                self.starting = false
                self.live = true
                self.liveSession.streaming()
                self.recoveryAttempts = 0
                self.mode = "实时桌面"
                let reveal = self.revealOnResume
                self.revealOnResume = false
                self.wakeReveal = reveal ? 0 : 1
                self.createOverlay(screen: screen)
                self.hideSettings?(); self.controlsHidden = true
                if reveal { self.beginWakeReveal() }
            }
            self.updateRenderers()
        }
        capture.onError = { [weak self] error in
            guard let self, self.generation == token else { return }
            self.handleCaptureError(error, userInitiated: false)
        }
        Task { @MainActor in
            guard generation == token else { await capture.stop(); return }
            do {
                try await capture.start(displayID: id)
                guard generation == token else { await capture.stop(); return }
                // Only a fresh complete frame can begin the wake animation.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if generation == token && starting {
                    captureInterrupted("等待桌面画面恢复…")
                }
            } catch {
                guard generation == token else { await capture.stop(); return }
                handleCaptureError(error, userInitiated: userInitiated)
            }
        }
    }
    private func handleCaptureError(_ error: Error, userInitiated: Bool) {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == -3801 {
            tearDownCapture()
            liveSession.interrupted()
            needsCapturePermission = true
            capturePermissionReady = false
            mode = "等待屏幕授权"
            if userInitiated { showSettings?() }
        } else {
            captureInterrupted("等待桌面捕获恢复…")
        }
    }
    private func beginWakeReveal() {
        wakeTimer?.invalidate()
        let began = ProcessInfo.processInfo.systemUptime
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.live else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.65)
            self.wakeReveal = EffectMath.eased(t)
            self.updateRenderers()
            if t >= 1 { timer.invalidate(); self.wakeTimer = nil }
        }
    }
    /// Explicit stop cancels user intent, including every pending wake/retry.
    func stop() {
        liveSession.disable()
        saveLiveIntent()
        revealOnResume = false
        cancelRecovery()
        tearDownCapture()
    }
    /// App relaunch remembers intent; stopping the effect itself does not.
    func prepareForTermination() {
        if !autoResume { liveSession.disable() }
        saveLiveIntent()
        cancelRecovery()
        tearDownCapture()
    }
    private func tearDownCapture() {
        generation += 1
        demoTimer?.invalidate(); demoTimer = nil
        wakeTimer?.invalidate(); wakeTimer = nil
        wakeReveal = 1
        live = false; starting = false; previewing = false; mode = "待机"
        overlay?.orderOut(nil); overlay = nil
        renderers.removeAll { $0.2 }
        if let capture { Task { await capture.stop() } }
        self.capture = nil; liveImage = nil
        previewChanged?(false)
        controlsHidden = false
        updateRenderers()
    }
    func stopAndShow() { stop(); showSettings?() }
    private func createOverlay(screen: NSScreen?) {
        guard let screen else { return }
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = makeView(overlay: true)
        overlay = window
        window.orderFrontRegardless()
    }
    private static func savedImageURL() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("MacBook Duo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("desktop.png")
    }
    static func sampleDesktop() -> CIImage {
        let size = NSSize(width: 1600, height: 1000)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.10, green: 0.17, blue: 0.38, alpha: 1), NSColor(red: 0.35, green: 0.31, blue: 0.61, alpha: 1), NSColor(red: 0.84, green: 0.56, blue: 0.46, alpha: 1)])!.draw(in: rect, angle: -35)
            for i in 0..<5 {
                let path = NSBezierPath()
                let y = CGFloat(i) * 95
                path.move(to: NSPoint(x: -100, y: y))
                path.curve(to: NSPoint(x: 1700, y: y + 200), controlPoint1: NSPoint(x: 400, y: y + 600), controlPoint2: NSPoint(x: 1000, y: y - 300))
                path.line(to: NSPoint(x: 1700, y: -10)); path.line(to: NSPoint(x: -100, y: -10)); path.close()
                NSColor(calibratedRed: 0.08 + Double(i) * 0.05, green: 0.12 + Double(i) * 0.035, blue: 0.25 + Double(i) * 0.07, alpha: 0.65).setFill(); path.fill()
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            ("Make room for possibility." as NSString).draw(in: NSRect(x: 200, y: 470, width: 1200, height: 90), withAttributes: [.font: NSFont.systemFont(ofSize: 52, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.9), .paragraphStyle: paragraph])
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: 505, y: 28, width: 590, height: 76), xRadius: 22, yRadius: 22).fill()
            for (i, symbol) in ["safari", "folder", "envelope", "calendar", "photo", "gearshape"].enumerated() {
                let box = NSRect(x: 527 + i * 94, y: 41, width: 50, height: 50)
                NSColor.white.withAlphaComponent(0.2).setFill(); NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.draw(in: box.insetBy(dx: 10, dy: 10))
            }
            return true
        }
        return CIImage(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }
}
