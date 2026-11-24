import XCTest
@testable import RazerSocksCore

final class DeviceTableTests: XCTestCase {
    func testVendorID() { XCTAssertEqual(DeviceTable.vendorID, 0x1532) }

    func testViperV3ProWired() {
        XCTAssertEqual(DeviceTable.device(forProductID: 0x00C0),
                       DeviceInfo(productID: 0x00C0, name: "Razer Viper V3 Pro", connection: .wired, transactionID: 0x1F))
    }

    func testViperV3ProWireless() {
        XCTAssertEqual(DeviceTable.device(forProductID: 0x00C1),
                       DeviceInfo(productID: 0x00C1, name: "Razer Viper V3 Pro", connection: .wireless, transactionID: 0x1F))
    }

    func testUnknownProductIsUnsupported() { XCTAssertNil(DeviceTable.device(forProductID: 0xFFFF)) }

    func testShortNameDropsVendor() {
        XCTAssertEqual(DeviceTable.device(forProductID: 0x00C1)?.shortName, "Viper V3 Pro")
    }
}
