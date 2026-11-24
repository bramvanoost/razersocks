import XCTest
@testable import RazerSocksCore

final class BatteryReaderTests: XCTestCase {
    private func read(_ interfaces: FeatureReportTransport...) -> QueryResult {
        BatteryReader(pause: {}).read(ConnectedDevice(info: .wireless, interfaces: interfaces))
    }

    private func status(_ percentage: Int, charging: Bool = false) -> QueryResult {
        .success(BatteryStatus(device: .wireless, percentage: percentage, charging: charging))
    }

    func testReadsDischargingBattery() { XCTAssertEqual(read(FakeMouse(battery: 214)), status(84)) }

    func testReadsChargingBattery() {
        XCTAssertEqual(read(FakeMouse(battery: 255, charging: 1)), status(100, charging: true))
    }

    func testRetriesWhileBusyThenSucceeds() {
        let mouse = FakeMouse { request, n in n < 3 ? (0x01, 0) : (0x02, request.command == 0x80 ? 214 : 0) }
        XCTAssertEqual(read(mouse), status(84))
    }

    func testGivesUpAfterThreeBusyReplies() {
        let mouse = FakeMouse { _, _ in (0x04, 0) }
        XCTAssertEqual(read(mouse), .unreachable)
        XCTAssertEqual(mouse.requests.count, 3)
    }

    func testRetriesTransientIOErrors() {
        let mouse = FakeMouse { request, n in
            if n == 1 { throw TransportError.io(-1) }
            return (0x02, request.command == 0x80 ? 214 : 0)
        }
        XCTAssertEqual(read(mouse), status(84))
    }

    func testPausesBetweenSendAndReceive() {
        var pauses = 0
        let device = ConnectedDevice(info: .wireless, interfaces: [FakeMouse(battery: 214)])
        _ = BatteryReader(pause: { pauses += 1 }).read(device)
        XCTAssertEqual(pauses, 2) // battery + charging, one reply each
    }

    func testFallsBackToOtherTransactionIDsWhenRejected() {
        let mouse = FakeMouse { request, _ in
            request.transactionID == 0xFF ? (0x02, request.command == 0x80 ? 214 : 0) : (0x05, 0)
        }
        XCTAssertEqual(read(mouse), status(84))
        XCTAssertEqual(mouse.requests.map(\.transactionID), [0x1F, 0x3F, 0xFF, 0xFF])
    }

    func testSkipsInterfaceThatRejectsFeatureReports() {
        let pointer = FakeMouse { _, _ in throw TransportError.io(-1) }
        XCTAssertEqual(read(pointer, FakeMouse(battery: 214)), status(84))
    }

    func testPermissionDeniedOnEveryInterface() {
        let locked = FakeMouse { _, _ in throw TransportError.notPermitted }
        XCTAssertEqual(read(locked, locked), .permissionDenied)
        XCTAssertEqual(locked.requests.count, 2, "permission errors are not worth retrying")
    }

    func testPermissionDeniedOnOneInterfaceDoesNotHideAWorkingOne() {
        let locked = FakeMouse { _, _ in throw TransportError.notPermitted }
        XCTAssertEqual(read(locked, FakeMouse(battery: 214)), status(84))
    }

    func testNoUsableInterfaceIsUnreachable() { XCTAssertEqual(read(), .unreachable) }
}
