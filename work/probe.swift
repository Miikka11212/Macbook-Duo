import Foundation
import IOKit.hid
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, ["VendorID": 0x05AC, "DeviceUsagePage": 0x20, "DeviceUsage": 0x8A] as CFDictionary)
print("manager", IOHIDManagerOpen(manager, 0))
if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
 for device in devices {
  print("open", IOHIDDeviceOpen(device, 0))
  for kind in [kIOHIDReportTypeFeature, kIOHIDReportTypeInput] {
   for id in [1, 7] {
    var data = [UInt8](repeating: 0, count: 16); var length = data.count
    let result = IOHIDDeviceGetReport(device, kind, CFIndex(id), &data, &length)
    print("report", kind.rawValue, id, result, length, data.prefix(length))
   }
  }
  IOHIDDeviceClose(device, 0)
 }
}
IOHIDManagerClose(manager, 0)
