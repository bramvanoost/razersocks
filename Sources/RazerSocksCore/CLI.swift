/// Argument parsing, output formatting and exit codes. No I/O.
public enum CLI {
    public static let version = "0.1.0"

    public static let help = """
        Usage: razersocks [options]

        Print the battery level of a connected Razer wireless mouse.

        Options:
          -q, --quiet, --raw   Print only the percentage, e.g. 84
          -j, --json           Print JSON (an array with --all)
          -a, --all            Print every connected supported device
          -v, --version        Print the version
          -h, --help           Print this help

        Exit codes:
          0   Success
          1   No supported Razer device found
          2   Device found, but asleep, unreachable or busy
          3   Input Monitoring permission denied
          64  Invalid usage

        """

    public enum Format: Equatable { case human, raw, json }

    public struct Options: Equatable {
        public var format = Format.human
        public var all = false
    }

    public enum Invocation: Equatable {
        case run(Options)
        case help
        case version
        case usageError(String)
    }

    public struct Outcome: Equatable {
        public var stdout: String
        public var stderr: String
        public var exitCode: Int32
        /// Drawings to show in place, one after the other, before `stdout`.
        public var frames: [String] = []

        public init(stdout: String = "", stderr: String = "", exitCode: Int32) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }
    }

    public static let usageExitCode: Int32 = 64 // EX_USAGE

    // MARK: Arguments

    public static func parse(_ arguments: [String]) -> Invocation {
        var all = false, raw = false, json = false

        for flag in arguments.flatMap(splitShortFlags) {
            switch flag {
            case "-h", "--help": return .help
            case "-v", "--version": return .version
            case "-q", "--quiet", "--raw": raw = true
            case "-j", "--json": json = true
            case "-a", "--all": all = true
            default:
                return .usageError((flag.hasPrefix("-") ? "unknown option: " : "unexpected argument: ") + flag)
            }
        }
        if raw && json { return .usageError("--raw and --json cannot be combined") }
        return .run(Options(format: raw ? .raw : json ? .json : .human, all: all))
    }

    /// "-aj" becomes "-a", "-j".
    private static func splitShortFlags(_ argument: String) -> [String] {
        guard argument.hasPrefix("-"), !argument.hasPrefix("--"), argument.count > 2 else { return [argument] }
        return argument.dropFirst().map { "-\($0)" }
    }

    // MARK: Formatting

    public static func render(_ statuses: [BatteryStatus], options: Options, color: Bool = false) -> String {
        let items = statuses.map { status -> String in
            switch options.format {
            case .human: return battery(status, color: color)
            case .raw: return String(status.percentage)
            case .json: return json(status)
            }
        }
        if options.format == .json && options.all { return "[" + items.joined(separator: ",") + "]" }
        return items.joined(separator: options.format == .human ? "\n\n" : "\n")
    }

    private static func battery(_ status: BatteryStatus, color: Bool) -> String {
        let width = 20
        // Rounds down so only 100% looks full, but never draws a live battery empty.
        let filled = status.percentage == 0 ? 0 : max(1, status.percentage * width / 100)
        let line = String(repeating: "─", count: width)
        let cells = String(repeating: "█", count: filled) + String(repeating: " ", count: width - filled)
        let code = status.percentage > 30 ? 32 : status.percentage > 10 ? 33 : 31 // green, yellow, red
        func paint(_ text: String) -> String { color ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
        return """
            \(paint("╭\(line)╮"))
            \(paint("│\(cells)├▌")) \(status.percentage)%
            \(paint("╰\(line)╯"))
            \(status.device.shortName) (\(status.charging ? "charging" : "discharging"))
            """
    }

    /// The same drawing, filling up from empty.
    private static func frames(_ statuses: [BatteryStatus], options: Options, color: Bool) -> [String] {
        let count = 20
        return (0..<count).map { step in
            let partial = statuses.map {
                BatteryStatus(device: $0.device, percentage: $0.percentage * step / count, charging: $0.charging)
            }
            return render(partial, options: options, color: color) + "\n"
        }
    }

    /// Written by hand to keep the key order stable.
    private static func json(_ status: BatteryStatus) -> String {
        let hex = String(status.device.productID, radix: 16)
        let pid = "0x" + String(repeating: "0", count: 4 - hex.count) + hex
        return #"{"device":"\#(escape(status.device.name))","pid":"\#(pid)","battery":\#(status.percentage),"#
            + #""charging":\#(status.charging),"connection":"\#(status.device.connection.rawValue)"}"#
    }

    private static func escape(_ string: String) -> String {
        string.reduce(into: "") { result, character in
            if character == "\"" || character == "\\" { result.append("\\") }
            result.append(character)
        }
    }

    // MARK: Running

    public static func run(_ options: Options, devices: [ConnectedDevice], reader: BatteryReader,
                           color: Bool = false, animate: Bool = false) -> Outcome {
        guard !devices.isEmpty else {
            return Outcome(stderr: "razersocks: no supported Razer device found\n", exitCode: 1)
        }

        var statuses: [BatteryStatus] = []
        var problems: [(device: DeviceInfo, silent: Bool, message: String)] = []
        var permissionDenied = false

        for device in devices {
            let label = "\(device.info.shortName) (\(device.info.connection.rawValue))"
            switch reader.read(device) {
            case .success(let status):
                statuses.append(status)
            case .permissionDenied:
                permissionDenied = true
                problems.append((device.info, false, "razersocks: \(label): Input Monitoring permission denied\n"))
            case .unreachable:
                problems.append((device.info, true, "razersocks: \(label): asleep, unreachable or busy (move the mouse and try again)\n"))
            }
            if !options.all && !statuses.isEmpty { break }
        }

        guard !statuses.isEmpty else {
            return Outcome(stderr: problems.map(\.message).joined() + (permissionDenied ? permissionHelp : ""),
                           exitCode: permissionDenied ? 3 : 2)
        }

        // A mouse on its cable leaves its dongle without anything to talk to.
        let cabled = statuses.map(\.device).filter { $0.connection == .wired }.map(\.name)
        let reported = problems.filter { !($0.silent && $0.device.connection == .wireless && cabled.contains($0.device.name)) }
        var outcome = Outcome(stdout: render(statuses, options: options, color: color) + "\n",
                              stderr: options.all ? reported.map(\.message).joined() : "",
                              exitCode: 0)
        if animate && options.format == .human {
            outcome.frames = frames(statuses, options: options, color: color)
        }
        return outcome
    }

    private static let permissionHelp = """
        Allow the app that runs razersocks (your terminal or status bar) in
        System Settings > Privacy & Security > Input Monitoring, then restart that app.

        """
}
