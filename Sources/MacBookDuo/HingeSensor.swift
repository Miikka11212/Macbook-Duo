import Foundation
import IOKit.hid

final class HingeSensor {
    private let queue = DispatchQueue(label: "duo.hinge", qos: .userInteractive)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var ticks = 0
    private var suspended = false
    var onAngle: ((Double?) -> Void)?

    func start() {
        queue.async { [self] in
            connect()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }
    func setSuspended(_ value: Bool) {
        queue.async { [self] in
            suspended = value
            if value {
                if let device { IOHIDDeviceClose(device, 0) }
                self.device = nil
            } else { connect() }
        }
    }
    private func connect() {
        if let device { IOHIDDeviceClose(device, 0) }
        if let manager { IOHIDManagerClose(manager, 0) }
        device = nil
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, ["VendorID": 0x05AC, "DeviceUsagePage": 0x20, "DeviceUsage": 0x8A] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
            if read(candidate) != nil { device = candidate; break }
            IOHIDDeviceClose(candidate, 0)
        }
    }
    private func read(_ device: IOHIDDevice) -> Double? {
        var bytes = [UInt8](repeating: 0, count: 8)
        var count = bytes.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count) == kIOReturnSuccess else { return nil }
        return EffectMath.decode(Array(bytes.prefix(count)))
    }
    private func poll() {
        guard !suspended else { return }
        ticks += 1
        if device == nil && ticks % 90 == 0 { connect() }
        let angle = device.flatMap(read)
        if angle == nil, let device { IOHIDDeviceClose(device, 0); self.device = nil }
        DispatchQueue.main.async { [weak self] in self?.onAngle?(angle) }
    }
}
