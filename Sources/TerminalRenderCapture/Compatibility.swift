import AppKit
import Foundation

struct CompatibilityLaunchPlan: Equatable {
    let applicationURL: URL
    let ownerName: String
    let title: String
    let executableURL: URL
    let arguments: [String]
    let shellCommand: String
}

struct CompatibilityGeometry: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct CompatibilityEvidence: Codable {
    let schema: String
    let kind: String
    let terminal: String
    let applicationVersion: String
    let requestedFontFamily: String
    let requestedFontSizePoints: Double
    let requestedViewport: Viewport
    let windowGeometry: CompatibilityGeometry
    let backingScale: Double
    let scenarioSha256: String
    let finalCheckpoint: String
    let displaySettleMilliseconds: UInt32
    let screenshotSha256: String
}

enum CompatibilityRunner {
    private static let settleMilliseconds: UInt32 = 250

    static func makePlan(
        terminal: CompatibilityTerminal,
        title: String,
        viewport: Viewport,
        sshArguments: [String]
    ) -> CompatibilityLaunchPlan {
        let ssh = shellJoin(["/usr/bin/ssh"] + sshArguments)
        let command = "/usr/bin/printf '\\033]0;\(title)\\007'; exec \(ssh)"
        switch terminal {
        case .ghostty:
            let app = URL(fileURLWithPath: "/Applications/Ghostty.app")
            return CompatibilityLaunchPlan(
                applicationURL: app,
                ownerName: "Ghostty",
                title: title,
                executableURL: app.appendingPathComponent("Contents/MacOS/ghostty"),
                arguments: [
                    "--font-family=Menlo",
                    "--font-size=18",
                    "--window-width=\(viewport.cols)",
                    "--window-height=\(viewport.rows)",
                    "--quit-after-last-window-closed=true",
                    "--confirm-close-surface=false",
                    "-e", "/bin/zsh", "-lc", command,
                ],
                shellCommand: command
            )
        case .terminalApp:
            let app = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            let script = """
            on run argv
              set commandText to item 1 of argv
              set captureTitle to item 2 of argv
              tell application "Terminal"
                activate
                set createdTab to do script commandText
                set custom title of createdTab to captureTitle
                set createdWindow to front window
                return (id of createdWindow as string) & "|" & (tty of createdTab)
              end tell
            end run
            """
            return CompatibilityLaunchPlan(
                applicationURL: app,
                ownerName: "Terminal",
                title: title,
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script, command, title],
                shellCommand: command
            )
        }
    }

    static func run(
        terminal: CompatibilityTerminal,
        scenario: URL,
        manifest: URL,
        screenshot: URL,
        sshArguments: [String]
    ) -> CaptureExit {
        let unavailable = screenshot.appendingPathExtension("unavailable.json")
        do {
            let checkedScenario = try ScenarioLoader.load(scenario)
            let (checkedManifest, _) = try ScenarioLoader.loadManifest(
                manifest,
                scenario: checkedScenario
            )
            guard
                let final = checkedManifest.frames.last,
                final.streamOrdinal == checkedManifest.expectedFinalOrdinal
            else {
                return unavailableResult(
                    terminal: terminal,
                    sidecar: unavailable,
                    reason: "manifest_final_frame"
                )
            }
            let title = "ai-survivors-capture-\(UUID().uuidString.lowercased())"
            let plan = makePlan(
                terminal: terminal,
                title: title,
                viewport: checkedScenario.document.viewport,
                sshArguments: sshArguments
            )
            guard FileManager.default.isExecutableFile(atPath: plan.executableURL.path) else {
                return unavailableResult(
                    terminal: terminal,
                    sidecar: unavailable,
                    reason: "application_missing"
                )
            }
            let existingWindowIDs = Set(
                windows()
                    .filter { $0.owner.caseInsensitiveCompare(plan.ownerName) == .orderedSame }
                    .map(\.id)
            )

            let process = Process()
            process.executableURL = plan.executableURL
            process.arguments = plan.arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()

            var terminalWindowID: Int?
            var terminalTTY: String?
            defer {
                cleanup(
                    terminal: terminal,
                    process: process,
                    windowID: terminalWindowID,
                    tty: terminalTTY,
                    title: plan.title
                )
            }
            if terminal == .terminalApp {
                process.waitUntilExit()
                guard
                    process.terminationStatus == 0,
                    let pipe = process.standardOutput as? Pipe,
                    let value = String(
                        data: pipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ),
                    case let fields = value
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "|", maxSplits: 1)
                        .map(String.init),
                    fields.count == 2,
                    let parsed = Int(fields[0]),
                    fields[1].hasPrefix("/dev/tty")
                else {
                    return unavailableResult(
                        terminal: terminal,
                        sidecar: unavailable,
                        reason: "automation_unavailable"
                    )
                }
                terminalWindowID = parsed
                terminalTTY = fields[1]
            }

            guard
                let window = waitForOwnedWindow(
                    plan: plan,
                    excluding: existingWindowIDs
                )
            else {
                return unavailableResult(
                    terminal: terminal,
                    sidecar: unavailable,
                    reason: "unique_window_unavailable"
                )
            }
            Thread.sleep(forTimeInterval: Double(settleMilliseconds) / 1_000)
            try FileManager.default.createDirectory(
                at: screenshot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let screenshotProcess = Process()
            screenshotProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            screenshotProcess.arguments = ["-x", "-l", String(window.id), screenshot.path]
            screenshotProcess.standardOutput = Pipe()
            screenshotProcess.standardError = Pipe()
            try screenshotProcess.run()
            screenshotProcess.waitUntilExit()
            guard
                screenshotProcess.terminationStatus == 0,
                let screenshotData = try? Data(contentsOf: screenshot),
                !screenshotData.isEmpty
            else {
                return unavailableResult(
                    terminal: terminal,
                    sidecar: unavailable,
                    reason: "screen_capture_unavailable"
                )
            }

            let version = (
                Bundle(url: plan.applicationURL)?
                    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ) ?? "unknown"
            let evidence = CompatibilityEvidence(
                schema: "swiftterm.render-compatibility/v1",
                kind: "observational_screenshot",
                terminal: terminal.rawValue,
                applicationVersion: version,
                requestedFontFamily: "Menlo",
                requestedFontSizePoints: 18,
                requestedViewport: checkedScenario.document.viewport,
                windowGeometry: window.geometry,
                backingScale: Double(NSScreen.main?.backingScaleFactor ?? 1),
                scenarioSha256: checkedScenario.sha256,
                finalCheckpoint: final.checkpointNames.joined(separator: ","),
                displaySettleMilliseconds: settleMilliseconds,
                screenshotSha256: screenshotData.sha256Hex
            )
            _ = try CanonicalJSON.writeAtomic(
                evidence,
                to: screenshot.appendingPathExtension("json")
            )
            return .success
        } catch {
            return unavailableResult(
                terminal: terminal,
                sidecar: unavailable,
                reason: "launch_or_validation_failed"
            )
        }
    }

    private static func unavailableResult(
        terminal: CompatibilityTerminal,
        sidecar: URL,
        reason: String
    ) -> CaptureExit {
        let value = [
            "kind": "compatibility_unavailable",
            "reason": reason,
            "terminal": terminal.rawValue,
        ]
        _ = try? CanonicalJSON.writeAtomic(value, to: sidecar)
        return .operationalFailure
    }

    private static func shellJoin(_ values: [String]) -> String {
        values.map(shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func waitForOwnedWindow(
        plan: CompatibilityLaunchPlan,
        excluding existingWindowIDs: Set<Int>
    ) -> (id: Int, geometry: CompatibilityGeometry)? {
        let deadline = Date(timeIntervalSinceNow: 5)
        repeat {
            let matches = windows().filter {
                $0.owner.caseInsensitiveCompare(plan.ownerName) == .orderedSame
                    && !existingWindowIDs.contains($0.id)
            }
            if matches.count == 1, let only = matches.first {
                return (only.id, only.geometry)
            }
            _ = RunLoop.main.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.05)
            )
        } while Date() < deadline
        return nil
    }

    private static func windows() -> [
        (id: Int, owner: String, title: String, geometry: CompatibilityGeometry)
    ] {
        guard
            let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }
        return raw.compactMap { value in
            guard
                let id = value[kCGWindowNumber as String] as? Int,
                let owner = value[kCGWindowOwnerName as String] as? String,
                let bounds = value[kCGWindowBounds as String] as? [String: Double]
            else {
                return nil
            }
            return (
                id,
                owner,
                value[kCGWindowName as String] as? String ?? "",
                CompatibilityGeometry(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0
                )
            )
        }
    }

    private static func cleanup(
        terminal: CompatibilityTerminal,
        process: Process,
        windowID: Int?,
        tty: String?,
        title: String
    ) {
        if terminal == .terminalApp, windowID != nil, let tty {
            let terminator = Process()
            terminator.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            terminator.arguments = [
                "-TERM", "-x", "-t",
                String(tty.dropFirst("/dev/".count)),
                "ssh",
            ]
            terminator.standardOutput = Pipe()
            terminator.standardError = Pipe()
            try? terminator.run()
            terminator.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.1)

            let closer = Process()
            closer.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            closer.arguments = [
                "-e",
                """
                tell application "Terminal"
                  repeat 100 times
                    try
                      set ownedWindows to every window whose custom title is "\(title)"
                      if (count of ownedWindows) is not 1 then return
                      set ownedWindow to item 1 of ownedWindows
                      if not busy of selected tab of ownedWindow then
                        close ownedWindow
                        return
                      end if
                    on error
                      return
                    end try
                    delay 0.05
                  end repeat
                end tell
                """,
            ]
            closer.standardOutput = Pipe()
            closer.standardError = Pipe()
            try? closer.run()
            closer.waitUntilExit()
        } else {
            if process.isRunning {
                process.terminate()
            }
            let closer = Process()
            closer.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            closer.arguments = [
                "-e",
                """
                tell application "Ghostty"
                  set matches to every window whose name contains "\(title)"
                  if (count of matches) is 1 then close window (item 1 of matches)
                end tell
                """,
            ]
            closer.standardOutput = Pipe()
            closer.standardError = Pipe()
            try? closer.run()
            closer.waitUntilExit()
        }
    }
}
