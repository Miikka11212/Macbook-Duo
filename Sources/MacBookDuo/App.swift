import AppKit
import SwiftUI
import Carbon

@main
struct MacBookDuoApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var model: DuoModel!
    private var settings: NSWindow!
    private var status: NSStatusItem!
    private let hotkeys = HotKeys()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--capture-check"), CommandLine.arguments.count > index + 1 {
            Task { @MainActor in await CaptureCheck.run(to: CommandLine.arguments[index + 1]) }
            return
        }
        model = DuoModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 755), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "MacBook Duo"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model).padding(.top, 24).background(Color(red: 0.085, green: 0.092, blue: 0.11)))
        window.minSize = NSSize(width: 960, height: 754)
        window.center()
        settings = window
        model.restartApp = { [weak self] in self?.restartApplication() }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.hideSettings = { [weak self] in self?.settings.orderOut(nil) }
        model.previewChanged = { [weak self] enabled in
            self?.hotkeys.preview(enabled)
            self?.settings.level = enabled ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2) : .normal
        }
        hotkeys.onKey = { [weak self] id in
            guard let self else { return }
            switch id {
            case 1: self.model.toggleLive()
            case 2: self.model.stopAndShow()
            case 3: self.model.saveHardwareEndpoint()
            case 4: self.model.toggleControls()
            default: break
            }
        }
        registerHotKeys()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "macbook.gen2", accessibilityDescription: "MacBook Duo")
        status.menu = makeMenu()
        installMainMenu()
        openSettings()
        model.restoreLiveSession()
        // Rendering diagnostics produce files only when explicitly launched with this flag.
        if let index = CommandLine.arguments.firstIndex(of: "--render-check"), CommandLine.arguments.count > index + 1 {
            renderCheck(to: CommandLine.arguments[index + 1])
        }
    }
    private func registerHotKeys() {
        let mods = UInt32(cmdKey | shiftKey)
        let registrations = [hotkeys.register(1, code: UInt32(kVK_ANSI_G), modifiers: mods), hotkeys.register(2, code: UInt32(kVK_Escape), modifiers: mods), hotkeys.register(3, code: UInt32(kVK_ANSI_K), modifiers: mods)]
        if registrations.contains(false) { model.message = "部分全局快捷键被其他应用占用，仍可通过菜单栏控制效果。" }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshCapturePermission() }
    private func restartApplication() {
        model.prepareForTermination()
        hotkeys.unregisterAll()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.registerHotKeys()
                    self?.model.message = "无法自动重启，请退出后重新打开：\(error.localizedDescription)"
                } else { NSApp.terminate(nil) }
            }
        }
    }
    @objc func openSettings() {
        settings.level = (model.live || model.previewing) ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2) : .normal
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.controlsHidden = false
        model.updateRenderers()
        model.resumePreview()
    }
    @objc private func toggleLive() { model.toggleLive() }
    @objc private func stopEffect() { model.stopAndShow() }
    @objc private func saveEndpoint() { model.saveHardwareEndpoint() }
    @objc private func quit() { model.prepareForTermination(); NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { makeMenu() }
    func windowWillClose(_ notification: Notification) {
        if model.previewing { model.stop() }
        model.controlsHidden = true
        model.updateRenderers()
    }
    func applicationWillTerminate(_ notification: Notification) { model?.prepareForTermination() }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for (title, action) in [("打开设置…", #selector(openSettings)), ("开关实时效果", #selector(toggleLive)), ("停止效果并返回设置", #selector(stopEffect)), ("保存当前铰链终点", #selector(saveEndpoint))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 MacBook Duo", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self; menu.addItem(quitItem)
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleLive) }?.state = model.liveEnabled ? .on : .off
    }
    private func installMainMenu() {
        let main = NSMenu()
        let root = NSMenuItem(); main.addItem(root)
        root.submenu = makeMenu()
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("拷贝", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu; main.addItem(edit)
        NSApp.mainMenu = main
    }
    private func renderCheck(to directory: String) {
        let renderer = GlassRenderer(device: model.device)
        let source = DuoModel.sampleDesktop()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for angle in [0.0, 60.0, 120.0] {
            let image = renderer.compose(source, size: CGSize(width: 1280, height: 800), progress: angle / 120)
            try? renderer.context.writePNGRepresentation(of: image, to: URL(fileURLWithPath: directory).appendingPathComponent("angle-\(Int(angle)).png"), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
    }
}
