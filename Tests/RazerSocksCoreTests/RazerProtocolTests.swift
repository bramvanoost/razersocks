import XCTest
@testable import RazerSocksCore

final class RazerProtocolTests: XCTestCase {
    /// A successful reply as the mouse would send it, independent of the request builder.
    private func reply(status: UInt8 = 0x02, tid: UInt8 = 0x1F, commandClass: UInt8 = 0x07,
                       command: UInt8 = 0x80, value: UInt8 = 0) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 90)
        p[0] = status; p[1] = tid; p[5] = 0x02; p[6] = commandClass; p[7] = command; p[9] = value
        return p
    }

    private func parse(_ report: [UInt8]) -> RazerProtocol.Reply {
        RazerProtocol.parse(report, command: .batteryLevel, transactionID: 0x1F)
    }

    func testCRCXorsBytes2Through87Only() {
        var p = [UInt8](repeating: 0, count: 90)
        p[0] = 0xFF; p[1] = 0xFF; p[88] = 0xFF; p[89] = 0xFF // all outside the range
        p[2] = 0x01; p[50] = 0x10; p[87] = 0x80
        XCTAssertEqual(RazerProtocol.crc(p), 0x91)
    }

    func testBatteryRequestLayout() {
        var expected = [UInt8](repeating: 0, count: 90)
        expected[1] = 0x1F; expected[5] = 0x02; expected[6] = 0x07; expected[7] = 0x80
        expected[88] = 0x85 // 02 ^ 07 ^ 80
        XCTAssertEqual(RazerProtocol.request(.batteryLevel, transactionID: 0x1F), expected)
    }

    func testChargingRequestLayout() {
        var expected = [UInt8](repeating: 0, count: 90)
        expected[1] = 0x3F; expected[5] = 0x02; expected[6] = 0x07; expected[7] = 0x84
        expected[88] = 0x81 // 02 ^ 07 ^ 84
        XCTAssertEqual(RazerProtocol.request(.chargingStatus, transactionID: 0x3F), expected)
    }

    func testParsesValueFrom90ByteReport() {
        XCTAssertEqual(parse(reply(value: 214)), .value(214))
    }

    func testParsesValueFrom91ByteReportWithReportIDPrefix() {
        XCTAssertEqual(parse([0x00] + reply(value: 214)), .value(214))
    }

    func testBusyStatusesAskForRetry() {
        XCTAssertEqual(parse(reply(status: 0x01)), .retry)
        XCTAssertEqual(parse(reply(status: 0x04)), .retry)
    }

    func testUnprocessedCommandAsksForRetry() {
        XCTAssertEqual(parse(reply(status: 0x00)), .retry)
    }

    func testFailureAndNotSupportedAreRejected() {
        XCTAssertEqual(parse(reply(status: 0x03)), .rejected)
        XCTAssertEqual(parse(reply(status: 0x05)), .rejected)
    }

    func testStaleReplyToAnotherCommandAsksForRetry() {
        XCTAssertEqual(parse(reply(command: 0x84, value: 1)), .retry)
        XCTAssertEqual(parse(reply(commandClass: 0x04, value: 1)), .retry)
    }

    func testReplyForAnotherTransactionAsksForRetry() {
        XCTAssertEqual(parse(reply(tid: 0x3F, value: 1)), .retry)
    }

    func testWrongLengthIsRejected() {
        XCTAssertEqual(parse([]), .rejected)
        XCTAssertEqual(parse([UInt8](repeating: 2, count: 89)), .rejected)
    }

    func testPercentageScalingAndRounding() {
        XCTAssertEqual(RazerProtocol.percentage(fromRaw: 0), 0)
        XCTAssertEqual(RazerProtocol.percentage(fromRaw: 255), 100)
        XCTAssertEqual(RazerProtocol.percentage(fromRaw: 214), 84) // 83.92
        XCTAssertEqual(RazerProtocol.percentage(fromRaw: 1), 0)    // 0.39
        XCTAssertEqual(RazerProtocol.percentage(fromRaw: 2), 1)    // 0.78
    }
}
