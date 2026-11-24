@testable import RazerSocksCore

/// Simulates the control interface of a mouse: answers each request with whatever the script says.
final class FakeMouse: FeatureReportTransport {
    struct Request { let transactionID: UInt8; let command: UInt8 }

    private let respond: (Request, Int) throws -> (status: UInt8, value: UInt8)
    private(set) var requests: [Request] = []

    init(_ respond: @escaping (Request, Int) throws -> (status: UInt8, value: UInt8)) {
        self.respond = respond
    }

    convenience init(battery: UInt8, charging: UInt8 = 0) {
        self.init { request, _ in (0x02, request.command == 0x80 ? battery : charging) }
    }

    func send(_ report: [UInt8]) throws {
        requests.append(Request(transactionID: report[1], command: report[7]))
    }

    func receive() throws -> [UInt8] {
        let request = requests[requests.count - 1]
        let (status, value) = try respond(request, requests.count)
        var p = [UInt8](repeating: 0, count: 90)
        p[0] = status; p[1] = request.transactionID; p[5] = 2; p[6] = 7; p[7] = request.command; p[9] = value
        return p
    }
}

extension DeviceInfo {
    static let wired = DeviceInfo(productID: 0x00C0, name: "Razer Viper V3 Pro", connection: .wired, transactionID: 0x1F)
    static let wireless = DeviceInfo(productID: 0x00C1, name: "Razer Viper V3 Pro", connection: .wireless, transactionID: 0x1F)
}
