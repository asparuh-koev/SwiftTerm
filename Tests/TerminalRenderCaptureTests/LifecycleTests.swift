import Foundation

func runLifecycleTests() throws {
    do {
        _ = try CLI.parse([
            "capture", "--artifact", "a.json", "--direct",
            "--cols", "100", "--rows", "20",
            "--", "/bin/sh", "-c", "secret",
        ])
        throw CaptureTestFailure.assertion("shell command string bypassed absolute OpenSSH")
    } catch CLIError.usage {
    }

    let root = URL(fileURLWithPath: ".build/test-lifecycle", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let screenshot = root.appendingPathComponent("ghostty.png")
    let result = CompatibilityRunner.run(
        terminal: .ghostty,
        scenario: root.appendingPathComponent("scenario.json"),
        manifest: root.appendingPathComponent("manifest.json"),
        screenshot: screenshot,
        sshArguments: ["token=not-serialized"]
    )
    try captureRequire(result == .operationalFailure, "unavailable compatibility must fail operationally")
    let sidecar = screenshot.appendingPathExtension("unavailable.json")
    let content = try String(contentsOf: sidecar, encoding: .utf8)
    try captureRequire(!content.contains("token=not-serialized"), "argv secret leaked into sidecar")
    try captureRequire(
        content.contains("launch_or_validation_failed"),
        "unavailable sidecar must retain a stable reason"
    )

    let viewport = Viewport(cols: 100, rows: 20)
    let ghostty = CompatibilityRunner.makePlan(
        terminal: .ghostty,
        title: "owned-window",
        viewport: viewport,
        sshArguments: ["-p", "2222", "user name@127.0.0.1"]
    )
    try captureRequire(
        ghostty.arguments.contains("--font-family=Menlo")
            && ghostty.arguments.contains("--font-size=18")
            && ghostty.arguments.contains("--window-width=100")
            && ghostty.arguments.contains("--window-height=20"),
        "Ghostty plan lost the fixed visual contract"
    )
    try captureRequire(
        ghostty.shellCommand.contains("'user name@127.0.0.1'"),
        "Ghostty SSH argv was not shell quoted"
    )

    let terminal = CompatibilityRunner.makePlan(
        terminal: .terminalApp,
        title: "owned-window",
        viewport: viewport,
        sshArguments: ["value'with-quote"]
    )
    try captureRequire(
        terminal.arguments.joined(separator: "\n").contains("custom title"),
        "Terminal.app plan does not own a uniquely titled tab"
    )
    try captureRequire(
        terminal.shellCommand.contains("'value'\\''with-quote'"),
        "Terminal.app SSH argv did not escape a quote"
    )
}
