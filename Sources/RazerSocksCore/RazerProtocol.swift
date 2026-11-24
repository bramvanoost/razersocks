/// Razer's 90-byte feature report: packet construction, checksum and reply parsing.
/// Pure functions only, no I/O.
public enum RazerProtocol {
    public static let payloadLength = 90

    private static let dataSize: UInt8 = 0x02
    private static let powerClass: UInt8 = 0x07

    /// Commands in the power class (0x07). Both are read-only queries.
    public enum Command: UInt8, Equatable {
        case batteryLevel = 0x80
        case chargingStatus = 0x84
    }

    public enum Reply: Equatable {
        /// First argument byte of a successful reply.
        case value(UInt8)
        /// Busy, still processing, or an answer to some other request. Ask again.
        case retry
        /// The device understood the request and refused it, or the report is malformed.
        case rejected
    }

    /// XOR of payload bytes 2 through 87 inclusive.
    public static func crc(_ payload: [UInt8]) -> UInt8 {
        payload[2...87].reduce(0, ^)
    }

    public static func request(_ command: Command, transactionID: UInt8) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: payloadLength)
        payload[1] = transactionID
        payload[5] = dataSize
        payload[6] = powerClass
        payload[7] = command.rawValue
        payload[88] = crc(payload)
        return payload
    }

    /// Accepts the bare 90-byte payload, or 91 bytes with a leading 0x00 report ID.
    public static func parse(_ report: [UInt8], command: Command, transactionID: UInt8) -> Reply {
        let payload: [UInt8]
        switch report.count {
        case payloadLength: payload = report
        case payloadLength + 1 where report[0] == 0: payload = Array(report.dropFirst())
        default: return .rejected
        }

        // The device keeps its last reply in the buffer, and other software (Synapse,
        // OpenRGB) shares it, so a reply only counts if it echoes this exact request.
        guard payload[1] == transactionID,
              payload[6] == powerClass,
              payload[7] == command.rawValue
        else { return .retry }

        switch payload[0] {
        case 0x02: return .value(payload[9])
        case 0x00, 0x01, 0x04: return .retry
        default: return .rejected
        }
    }

    public static func percentage(fromRaw raw: UInt8) -> Int {
        Int((Double(raw) / 255.0 * 100.0).rounded())
    }
}
