import Foundation
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

    func testHumanOutputDrawsABattery() {
        XCTAssertEqual(CLI.render([discharging], options: options(.human)), """
            ╭────────────────────╮
            │████████████████    ├▌ 84%
            ╰────────────────────╯
            Viper V3 Pro (discharging)
            """)
    }

    func testChargingIsNamed() {
        XCTAssertTrue(CLI.render([charging], options: options(.human)).hasSuffix("Viper V3 Pro (charging)"))
    }

    private func drawing(_ percentage: Int, color: Bool = false) -> String {
        CLI.render([BatteryStatus(device: .wireless, percentage: percentage, charging: false)],
                   options: options(.human), color: color)
    }

    func testBatteryFill() {
        func cells(_ percentage: Int) -> Int { drawing(percentage).filter { $0 == "█" }.count }
        XCTAssertEqual(cells(0), 0)
        XCTAssertEqual(cells(1), 1, "a nearly empty battery is not drawn empty")
        XCTAssertEqual(cells(50), 10)
        XCTAssertEqual(cells(99), 19, "only 100% is drawn full")
        XCTAssertEqual(cells(100), 20)
    }

    func testColorFollowsTheLevel() {
        let green = "\u{1B}[32m", yellow = "\u{1B}[33m", red = "\u{1B}[31m"
        for (percentage, code) in [(100, green), (31, green), (30, yellow), (11, yellow), (10, red), (0, red)] {
            XCTAssertTrue(drawing(percentage, color: true).contains(code), "\(percentage)%")
        }
    }

    func testColorIsResetAndOtherwiseChangesNothing() {
        let colored = drawing(84, color: true)
        XCTAssertEqual(colored.components(separatedBy: "\u{1B}[32m").count, colored.components(separatedBy: "\u{1B}[0m").count)
        XCTAssertEqual(colored.replacingOccurrences(of: "\u{1B}[32m", with: "").replacingOccurrences(of: "\u{1B}[0m", with: ""),
                       drawing(84))
    }

    func testRawAndJSONAreNeverColored() {
        for format in [CLI.Format.raw, .json] {
            XCTAssertFalse(CLI.render([discharging], options: options(format), color: true).contains("\u{1B}"))
        }
    }

    func testAllSeparatesBatteriesWithABlankLine() {
        let both = CLI.render([charging, discharging], options: options(.human, all: true))
        XCTAssertEqual(both, CLI.render([charging], options: options(.human)) + "\n\n"
            + CLI.render([discharging], options: options(.human)))
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
        let other = DeviceInfo(productID: 0xABCD, name: "Razer Other", connection: .wired, transactionID: 0x1F)
        let outcome = run(options(.raw, all: true), [working(other, 255), asleep])
        XCTAssertEqual(outcome.stdout, "100\n")
        XCTAssertTrue(outcome.stderr.contains("Viper V3 Pro (wireless)"), outcome.stderr)
        XCTAssertEqual(outcome.exitCode, 0)
    }

    func testAllIgnoresSilentDongleWhenSameModelAnswersOverCable() {
        let expected = CLI.Outcome(stdout: "100\n", stderr: "", exitCode: 0)
        XCTAssertEqual(run(options(.raw, all: true), [working(.wired, 255), asleep]), expected)
        XCTAssertEqual(run(options(.raw, all: true), [asleep, working(.wired, 255)]), expected)
    }

    func testAllStillReportsSilentDongleWhenSameModelAnswersOverAnotherDongle() {
        let outcome = run(options(.raw, all: true), [working(.wireless, 255), asleep])
        XCTAssertTrue(outcome.stderr.contains("Viper V3 Pro (wireless)"), outcome.stderr)
    }

    func testAllStillReportsPermissionDeniedDongleWhenSameModelAnswersOverCable() {
        let outcome = run(options(.raw, all: true), [working(.wired, 255), locked])
        XCTAssertTrue(outcome.stderr.contains("permission denied"), outcome.stderr)
    }

    private func animated(_ format: CLI.Format, _ devices: [ConnectedDevice]) -> CLI.Outcome {
        CLI.run(options(format), devices: devices, reader: BatteryReader(pause: {}), animate: true)
    }

    func testAnimationFillsUpToTheRealLevel() {
        let outcome = animated(.human, [working(.wireless, 214)])
        let fills = outcome.frames.map { $0.filter { $0 == "█" }.count }
        XCTAssertEqual(fills.first, 0)
        XCTAssertEqual(fills, fills.sorted())
        XCTAssertEqual(fills.count, 20)
        XCTAssertLessThanOrEqual(fills.last ?? 99, 16)
        XCTAssertTrue(outcome.stdout.contains("84%"), outcome.stdout)
    }

    func testFramesHaveAsManyLinesAsTheFinalDrawing() {
        let outcome = animated(.human, [working(.wireless, 214)])
        XCTAssertFalse(outcome.frames.isEmpty)
        for frame in outcome.frames {
            XCTAssertEqual(frame.filter { $0 == "\n" }.count, outcome.stdout.filter { $0 == "\n" }.count)
        }
    }

    func testOnlyTheDrawingIsAnimated() {
        XCTAssertEqual(animated(.raw, [working(.wireless, 214)]).frames, [])
        XCTAssertEqual(animated(.json, [working(.wireless, 214)]).frames, [])
        XCTAssertEqual(animated(.human, [asleep]).frames, [])
        XCTAssertEqual(run(options(.human), [working(.wireless, 214)]).frames, [])
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
