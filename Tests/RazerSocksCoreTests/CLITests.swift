import XCTest
@testable import RazerSocksCore

final class CLITests: XCTestCase {
    private let discharging = BatteryStatus(device: .wireless, percentage: 84, charging: false)
    private let charging = BatteryStatus(device: .wired, percentage: 100, charging: true)

    // MARK: Arguments

    private func options(_ format: CLI.Format, all: Bool = false) -> CLI.Options {
        var o = CLI.Options(); o.format = format; o.all = all; return o
    }

    func testNoArgumentsMeansHumanOutput() { XCTAssertEqual(CLI.parse([]), .run(options(.human))) }

    func testRawSpellings() {
        for flag in ["-q", "--quiet", "--raw"] { XCTAssertEqual(CLI.parse([flag]), .run(options(.raw)), flag) }
    }

    func testJSONSpellings() {
        for flag in ["-j", "--json"] { XCTAssertEqual(CLI.parse([flag]), .run(options(.json)), flag) }
    }

    func testAllCombinesWithFormat() {
        XCTAssertEqual(CLI.parse(["--all", "--json"]), .run(options(.json, all: true)))
        XCTAssertEqual(CLI.parse(["-aj"]), .run(options(.json, all: true)))
    }

    func testHelpAndVersion() {
        for flag in ["-h", "--help"] { XCTAssertEqual(CLI.parse([flag]), .help, flag) }
        for flag in ["-v", "--version"] { XCTAssertEqual(CLI.parse([flag]), .version, flag) }
    }

    func testUnknownArgumentsAreUsageErrors() {
        XCTAssertEqual(CLI.parse(["--nope"]), .usageError("unknown option: --nope"))
        XCTAssertEqual(CLI.parse(["-ax"]), .usageError("unknown option: -x"))
        XCTAssertEqual(CLI.parse(["mouse"]), .usageError("unexpected argument: mouse"))
    }

    func testRawAndJSONConflict() {
        XCTAssertEqual(CLI.parse(["-q", "-j"]), .usageError("--raw and --json cannot be combined"))
    }

    // MARK: Formatting

    func testHumanOutput() {
        XCTAssertEqual(CLI.render([discharging], options: options(.human)), "Viper V3 Pro: 84% (discharging)")
        XCTAssertEqual(CLI.render([charging], options: options(.human)), "Viper V3 Pro: 100% (charging)")
    }

    func testRawOutput() { XCTAssertEqual(CLI.render([discharging], options: options(.raw)), "84") }

    func testJSONOutput() {
        XCTAssertEqual(CLI.render([discharging], options: options(.json)),
            #"{"device":"Razer Viper V3 Pro","pid":"0x00c1","battery":84,"charging":false,"connection":"wireless"}"#)
    }

    func testJSONEscapesDeviceName() {
        let odd = DeviceInfo(productID: 0xABCD, name: #"A "B" \C"#, connection: .wired, transactionID: 0)
        XCTAssertEqual(CLI.render([BatteryStatus(device: odd, percentage: 1, charging: true)], options: options(.json)),
            #"{"device":"A \"B\" \\C","pid":"0xabcd","battery":1,"charging":true,"connection":"wired"}"#)
    }

    func testAllPrintsOneLinePerDevice() {
        XCTAssertEqual(CLI.render([charging, discharging], options: options(.raw, all: true)), "100\n84")
    }

    func testAllJSONIsAlwaysAnArray() {
        let one = CLI.render([discharging], options: options(.json, all: true))
        XCTAssertEqual(one, "[" + CLI.render([discharging], options: options(.json)) + "]")
    }

    // MARK: Running

    private func run(_ o: CLI.Options, _ devices: [ConnectedDevice]) -> CLI.Outcome {
        CLI.run(o, devices: devices, reader: BatteryReader(pause: {}))
    }
    private func working(_ info: DeviceInfo, _ raw: UInt8) -> ConnectedDevice {
        ConnectedDevice(info: info, interfaces: [FakeMouse(battery: raw)])
    }
    private let asleep = ConnectedDevice(info: .wireless, interfaces: [FakeMouse { _, _ in (0x04, 0) }])
    private let locked = ConnectedDevice(info: .wireless, interfaces: [FakeMouse { _, _ in throw TransportError.notPermitted }])

    func testSuccessExitsZero() {
        XCTAssertEqual(run(options(.raw), [working(.wireless, 214)]), CLI.Outcome(stdout: "84\n", stderr: "", exitCode: 0))
    }

    func testDefaultShowsOnlyFirstReachableDevice() {
        XCTAssertEqual(run(options(.raw), [asleep, working(.wired, 255), working(.wireless, 214)]),
                       CLI.Outcome(stdout: "100\n", stderr: "", exitCode: 0))
    }

    func testAllShowsEveryReachableDeviceAndReportsTheRest() {
        let outcome = run(options(.raw, all: true), [working(.wired, 255), asleep])
        XCTAssertEqual(outcome.stdout, "100\n")
        XCTAssertTrue(outcome.stderr.contains("Viper V3 Pro (wireless)"), outcome.stderr)
        XCTAssertEqual(outcome.exitCode, 0)
    }

    func testNoDeviceExitsOne() {
        let outcome = run(options(.json), [])
        XCTAssertEqual(outcome.exitCode, 1)
        XCTAssertEqual(outcome.stdout, "")
        XCTAssertTrue(outcome.stderr.contains("no supported Razer device"), outcome.stderr)
    }

    func testUnreachableExitsTwo() {
        let outcome = run(options(.human), [asleep])
        XCTAssertEqual(outcome.exitCode, 2)
        XCTAssertEqual(outcome.stdout, "")
        XCTAssertTrue(outcome.stderr.contains("asleep"), outcome.stderr)
    }

    func testPermissionDeniedExitsThreeWithInstructions() {
        let outcome = run(options(.human), [asleep, locked])
        XCTAssertEqual(outcome.exitCode, 3)
        XCTAssertEqual(outcome.stdout, "")
        XCTAssertTrue(outcome.stderr.contains("System Settings > Privacy & Security > Input Monitoring"), outcome.stderr)
    }
}
