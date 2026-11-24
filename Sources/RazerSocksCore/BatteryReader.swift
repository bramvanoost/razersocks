public enum TransportError: Error, Equatable {
    /// macOS refused access (Input Monitoring).
    case notPermitted
    /// Any other IOKit failure, with its IOReturn code.
    case io(Int32)
}

/// One HID interface that can exchange Razer feature reports.
public protocol FeatureReportTransport {
    func send(_ report: [UInt8]) throws
    func receive() throws -> [UInt8]
}

/// A supported mouse or dongle. It exposes several HID interfaces and
/// usually only one of them answers control requests.
public struct ConnectedDevice {
    public let info: DeviceInfo
    public let interfaces: [FeatureReportTransport]
}

public struct BatteryStatus: Equatable {
    public let device: DeviceInfo
    public let percentage: Int
    public let charging: Bool
}

public enum QueryResult: Equatable {
    case success(BatteryStatus)
    case permissionDenied
    case unreachable
}

/// Asks a device for its battery state, handling retries, transaction ID
/// fallback and interface probing.
public struct BatteryReader {
    private static let attempts = 3
    private static let fallbackTransactionIDs: [UInt8] = [0x3F, 0xFF]

    private let pause: () -> Void

    /// `pause` runs between sending a request and reading the reply, and before each retry.
    public init(pause: @escaping () -> Void) {
        self.pause = pause
    }

    public func read(_ device: ConnectedDevice) -> QueryResult {
        var permissionDenied = false
        for interface in device.interfaces {
            do {
                if let status = try read(device.info, over: interface) { return .success(status) }
            } catch TransportError.notPermitted {
                permissionDenied = true
            } catch {
                continue
            }
        }
        return permissionDenied ? .permissionDenied : .unreachable
    }

    private func read(_ info: DeviceInfo, over interface: FeatureReportTransport) throws -> BatteryStatus? {
        let candidates = [info.transactionID] + Self.fallbackTransactionIDs.filter { $0 != info.transactionID }
        for transactionID in candidates {
            switch try query(.batteryLevel, transactionID, interface) {
            case .rejected:
                continue
            case .retry:
                return nil
            case .value(let raw):
                guard case .value(let charging) = try query(.chargingStatus, transactionID, interface) else { return nil }
                return BatteryStatus(device: info,
                                     percentage: RazerProtocol.percentage(fromRaw: raw),
                                     charging: charging == 0x01)
            }
        }
        return nil
    }

    /// Returns `.retry` when the device is still busy after the last attempt.
    private func query(_ command: RazerProtocol.Command, _ transactionID: UInt8,
                       _ interface: FeatureReportTransport) throws -> RazerProtocol.Reply {
        let request = RazerProtocol.request(command, transactionID: transactionID)
        for attempt in 0..<Self.attempts {
            if attempt > 0 { pause() }
            do {
                try interface.send(request)
                pause()
                let reply = RazerProtocol.parse(try interface.receive(), command: command, transactionID: transactionID)
                if reply != .retry { return reply }
            } catch TransportError.io {
                continue // a waking mouse can fail the transfer itself
            }
        }
        return .retry
    }
}
