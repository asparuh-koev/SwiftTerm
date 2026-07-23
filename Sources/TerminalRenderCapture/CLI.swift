import Foundation

enum CaptureExit: Int32 {
    case success = 0
    case usage = 2
    case comparisonFailed = 3
    case operationalFailure = 4
    case truncated = 5
}

struct CaptureOptions {
    let artifact: URL
    let scenario: URL?
    let manifest: URL?
    let baselineRoot: URL?
    let direct: Bool
    let viewport: Viewport?
    let timeoutSeconds: UInt64
    let retainComplete: Bool
    let rawWire: URL?
    let png: URL?
    let sshArguments: [String]
}

enum CompatibilityTerminal: String {
    case ghostty
    case terminalApp = "terminal-app"
}

enum CaptureCommand {
    case capture(CaptureOptions)
    case compare(artifact: URL, scenario: URL, baselineRoot: URL)
    case baselineUpdate(artifact: URL, baselineRoot: URL, replace: Bool)
    case compatibility(
        terminal: CompatibilityTerminal,
        scenario: URL,
        manifest: URL,
        screenshot: URL,
        sshArguments: [String]
    )
    case selfTest
    case version
}

enum CLI {
    static let usage = """
    usage:
      terminal-render-capture capture --artifact <capture.json> [--scenario <scenario.json> --manifest <manifest.json> --baseline-root <dir>] [--direct --cols <n> --rows <n> [--timeout-seconds <n>]] [--retain complete] [--raw-wire <wire.bin>] [--png <swiftterm.png>] -- /usr/bin/ssh <args...>
      terminal-render-capture compare --artifact <capture.json> --scenario <scenario.json> --baseline-root <dir>
      terminal-render-capture baseline update --artifact <capture.json> --baseline-root <dir> [--replace]
      terminal-render-capture compat --terminal ghostty|terminal-app --scenario <scenario.json> --manifest <manifest.json> --screenshot <output.png> -- /usr/bin/ssh <args...>
      terminal-render-capture self-test
    """

    static func parse(_ arguments: [String]) throws -> CaptureCommand {
        guard let first = arguments.first else {
            throw CLIError.usage
        }
        switch first {
        case "capture":
            return .capture(try parseCapture(Array(arguments.dropFirst())))
        case "compare":
            let values = try parseFlags(Array(arguments.dropFirst()), allowed: [
                "--artifact", "--scenario", "--baseline-root",
            ])
            return .compare(
                artifact: try requiredURL("--artifact", values),
                scenario: try requiredURL("--scenario", values),
                baselineRoot: try requiredURL("--baseline-root", values)
            )
        case "baseline":
            guard arguments.dropFirst().first == "update" else {
                throw CLIError.usage
            }
            let values = try parseFlags(
                Array(arguments.dropFirst(2)),
                allowed: ["--artifact", "--baseline-root"],
                switches: ["--replace"]
            )
            return .baselineUpdate(
                artifact: try requiredURL("--artifact", values),
                baselineRoot: try requiredURL("--baseline-root", values),
                replace: values["--replace"] != nil
            )
        case "compat":
            return try parseCompatibility(Array(arguments.dropFirst()))
        case "self-test":
            guard arguments.count == 1 else { throw CLIError.usage }
            return .selfTest
        case "--version":
            guard arguments.count == 1 else { throw CLIError.usage }
            return .version
        default:
            throw CLIError.usage
        }
    }

    private static func parseCapture(_ arguments: [String]) throws -> CaptureOptions {
        guard
            let separator = arguments.firstIndex(of: "--"),
            separator + 1 < arguments.count
        else {
            throw CLIError.usage
        }
        let ssh = Array(arguments[(separator + 1)...])
        guard ssh.first == "/usr/bin/ssh" else {
            throw CLIError.usage
        }
        let values = try parseFlags(
            Array(arguments[..<separator]),
            allowed: [
                "--artifact", "--scenario", "--manifest", "--baseline-root",
                "--cols", "--rows", "--timeout-seconds", "--retain",
                "--raw-wire", "--png",
            ],
            switches: ["--direct"]
        )
        let direct = values["--direct"] != nil
        let reproducibility = [
            values["--scenario"], values["--manifest"], values["--baseline-root"],
        ]
        let reproducibleCount = reproducibility.compactMap { $0 }.count
        guard reproducibleCount == 0 || reproducibleCount == 3 else {
            throw CLIError.usage
        }
        if !direct && reproducibleCount != 3 {
            throw CLIError.usage
        }
        let columns = values["--cols"].flatMap(UInt16.init)
        let rows = values["--rows"].flatMap(UInt16.init)
        let viewport: Viewport?
        if direct && reproducibleCount == 0 {
            guard
                let columns,
                let rows,
                (1...500).contains(columns),
                (1...200).contains(rows)
            else {
                throw CLIError.usage
            }
            viewport = Viewport(cols: columns, rows: rows)
        } else {
            guard columns == nil && rows == nil else {
                throw CLIError.usage
            }
            viewport = nil
        }
        let timeout = values["--timeout-seconds"].flatMap(UInt64.init)
            ?? (direct && reproducibleCount == 0 ? 120 : 30)
        guard (1...600).contains(timeout) else {
            throw CLIError.usage
        }
        if let retain = values["--retain"], retain != "complete" {
            throw CLIError.usage
        }
        return CaptureOptions(
            artifact: try requiredURL("--artifact", values),
            scenario: values["--scenario"].map(fileURL),
            manifest: values["--manifest"].map(fileURL),
            baselineRoot: values["--baseline-root"].map(fileURL),
            direct: direct,
            viewport: viewport,
            timeoutSeconds: timeout,
            retainComplete: values["--retain"] == "complete",
            rawWire: values["--raw-wire"].map(fileURL),
            png: values["--png"].map(fileURL),
            sshArguments: Array(ssh.dropFirst())
        )
    }

    private static func parseCompatibility(_ arguments: [String]) throws -> CaptureCommand {
        guard
            let separator = arguments.firstIndex(of: "--"),
            separator + 1 < arguments.count
        else {
            throw CLIError.usage
        }
        let ssh = Array(arguments[(separator + 1)...])
        guard ssh.first == "/usr/bin/ssh" else {
            throw CLIError.usage
        }
        let values = try parseFlags(
            Array(arguments[..<separator]),
            allowed: ["--terminal", "--scenario", "--manifest", "--screenshot"]
        )
        guard
            let terminalValue = values["--terminal"],
            let terminal = CompatibilityTerminal(rawValue: terminalValue)
        else {
            throw CLIError.usage
        }
        return .compatibility(
            terminal: terminal,
            scenario: try requiredURL("--scenario", values),
            manifest: try requiredURL("--manifest", values),
            screenshot: try requiredURL("--screenshot", values),
            sshArguments: Array(ssh.dropFirst())
        )
    }

    private static func parseFlags(
        _ arguments: [String],
        allowed: Set<String>,
        switches: Set<String> = []
    ) throws -> [String: String] {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard (allowed.contains(flag) || switches.contains(flag)), values[flag] == nil else {
                throw CLIError.usage
            }
            if switches.contains(flag) {
                values[flag] = "true"
                index += 1
            } else {
                guard index + 1 < arguments.count else {
                    throw CLIError.usage
                }
                values[flag] = arguments[index + 1]
                index += 2
            }
        }
        return values
    }

    private static func requiredURL(
        _ flag: String,
        _ values: [String: String]
    ) throws -> URL {
        guard let value = values[flag], !value.isEmpty else {
            throw CLIError.usage
        }
        return fileURL(value)
    }

    private static func fileURL(_ value: String) -> URL {
        URL(fileURLWithPath: value)
    }
}

enum CLIError: Error {
    case usage
}
