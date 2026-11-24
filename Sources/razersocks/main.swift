import Darwin
import Foundation
import IOKit.hid
import RazerSocksCore

func finish(_ outcome: CLI.Outcome) -> Never {
    for frame in outcome.frames {
        fputs(frame, stdout)
        fflush(stdout)
        usleep(20_000)
        // Back to the first line, so the next drawing lands on top.
        fputs("\u{1B}[\(frame.filter { $0 == "\n" }.count)A", stdout)
    }
    fputs(outcome.stdout, stdout)
    fputs(outcome.stderr, stderr)
    exit(outcome.exitCode)
}

switch CLI.parse(Array(CommandLine.arguments.dropFirst())) {
case .help:
    finish(.init(stdout: CLI.help, exitCode: 0))
case .version:
    finish(.init(stdout: "razersocks \(CLI.version)\n", exitCode: 0))
case .usageError(let message):
    finish(.init(stderr: "razersocks: \(message)\n\n\(CLI.help)", exitCode: CLI.usageExitCode))
case .run(let options):
    let reader = BatteryReader(pause: { usleep(45_000) })
    let environment = ProcessInfo.processInfo.environment
    let isTerminal = isatty(STDOUT_FILENO) == 1 && environment["TERM", default: "dumb"] != "dumb"
    let noColor = !(environment["NO_COLOR"] ?? "").isEmpty
    let outcome = CLI.run(options, devices: HIDDiscovery.connectedDevices(), reader: reader,
                          color: isTerminal && !noColor, animate: isTerminal)
    if outcome.exitCode == 3 {
        // Lists the calling app under Input Monitoring. Prompts only if the user was never asked.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
    finish(outcome)
}
