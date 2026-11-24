public enum Connection: String {
    case wired, wireless
}

public struct DeviceInfo: Equatable {
    public let productID: UInt16
    public let name: String
    public let connection: Connection
    public let transactionID: UInt8

    /// Name without the vendor, for human-readable output.
    public var shortName: String {
        name.hasPrefix("Razer ") ? String(name.dropFirst("Razer ".count)) : name
    }
}

/// Supported hardware. To add a mouse, append one row per product ID
/// (most models use one ID on the cable and another on the dongle).
/// Order is priority: the first reachable device is the default one shown.
public enum DeviceTable {
    public static let vendorID: UInt16 = 0x1532

    public static let devices: [DeviceInfo] = [
        DeviceInfo(productID: 0x00C0, name: "Razer Viper V3 Pro", connection: .wired, transactionID: 0x1F),
        DeviceInfo(productID: 0x00C1, name: "Razer Viper V3 Pro", connection: .wireless, transactionID: 0x1F),
    ]

    public static func device(forProductID productID: UInt16) -> DeviceInfo? {
        devices.first { $0.productID == productID }
    }
}
