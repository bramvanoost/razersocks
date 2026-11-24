import Foundation
import IOKit
import IOKit.hid

/// Feature reports over one IOKit HID interface. Opens on first use.
public final class HIDTransport: FeatureReportTransport {
    private let device: IOHIDDevice
    private var isOpen = false
    /// Whether this interface wants the 0x00 report ID in front of the payload.
    private var prefixesReportID = false

    init(_ device: IOHIDDevice) {
        self.device = device
    }

    deinit {
        if isOpen { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }

    public func send(_ report: [UInt8]) throws {
        try open()
        do {
            try setReport(prefixesReportID ? [0] + report : report)
        } catch TransportError.io {
            // Try the other framing once. Keep it only if it works.
            try setReport(prefixesReportID ? report : [0] + report)
            prefixesReportID.toggle()
        }
    }

    public func receive() throws -> [UInt8] {
        try open()
        var buffer = [UInt8](repeating: 0, count: RazerProtocol.payloadLength + (prefixesReportID ? 1 : 0))
        var length = CFIndex(buffer.count)
        try check(IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &buffer, &length))
        return Array(buffer.prefix(length))
    }

    private func setReport(_ bytes: [UInt8]) throws {
        try check(IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, bytes, bytes.count))
    }

    private func open() throws {
        guard !isOpen else { return }
        try check(IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)))
        isOpen = true
    }

    private func check(_ result: IOReturn) throws {
        switch result {
        case kIOReturnSuccess: return
        case kIOReturnNotPermitted: throw TransportError.notPermitted
        default: throw TransportError.io(result)
        }
    }
}

public enum HIDDiscovery {
    /// Connected supported devices, in `DeviceTable` order.
    public static func connectedDevices() -> [ConnectedDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Int(DeviceTable.vendorID)] as CFDictionary)
        let found = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []

        return DeviceTable.devices.flatMap { info -> [ConnectedDevice] in
            let interfaces = found.filter { number($0, kIOHIDProductIDKey) == Int(info.productID) }
            // Interfaces of one physical device share a USB location.
            let byLocation = Dictionary(grouping: interfaces) { number($0, kIOHIDLocationIDKey) }
            return byLocation.sorted { $0.key < $1.key }.map { _, interfaces in
                ConnectedDevice(info: info, interfaces: controlInterfaces(interfaces).map(HIDTransport.init))
            }
        }
    }

    /// Interfaces that declare a feature report large enough for the Razer payload.
    /// Falls back to all of them, in case a model under-reports its size.
    private static func controlInterfaces(_ interfaces: [IOHIDDevice]) -> [IOHIDDevice] {
        let large = interfaces.filter { number($0, kIOHIDMaxFeatureReportSizeKey) >= RazerProtocol.payloadLength }
        return large.isEmpty ? interfaces : large
    }

    private static func number(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
}
