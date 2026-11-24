import Darwin
import IOKit.hid
import RazerSocksCore

func finish(_ outcome: CLI.Outcome) -> Never {
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
    let outcome = CLI.run(options, devices: HIDDiscovery.connectedDevices(), reader: reader)
    if outcome.exitCode == 3 {
        // Lists the calling app under Input Monitoring. Prompts only if the user was never asked.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
    finish(outcome)
}
