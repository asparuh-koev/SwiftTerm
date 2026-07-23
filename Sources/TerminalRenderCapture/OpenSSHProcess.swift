import AppKit
import Darwin
import Foundation

enum OpenSSHError: Error {
    case fontUnavailable
    case launchFailed
}

final class OpenSSHProcess: NSObject, LocalProcessDelegate, TerminalViewDelegate {
    let view: TerminalView
    private let coordinator: CaptureCoordinator
    private let viewport: Viewport
    private let arguments: [String]
    private let timeoutMilliseconds: UInt64
    private let rawWireURL: URL?
    private let rawWireLimit: UInt64
    private var process: LocalProcess!
    private var rawWire = Data()
    private var terminated = false
    private var exitStatus: Int32?

    init(
        coordinator: CaptureCoordinator,
        viewport: Viewport,
        arguments: [String],
        timeoutMilliseconds: UInt64,
        rawWireURL: URL?,
        rawWireLimit: UInt64
    ) throws {
        guard let font = NSFont(name: "Menlo-Regular", size: 18), font.fontName == "Menlo-Regular" else {
            throw OpenSSHError.fontUnavailable
        }
        self.coordinator = coordinator
        self.viewport = viewport
        self.arguments = arguments
        self.timeoutMilliseconds = timeoutMilliseconds
        self.rawWireURL = rawWireURL
        self.rawWireLimit = rawWireLimit
        view = TerminalView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            font: font
        )
        super.init()
        view.renderObservationScaleOverride = 2
        view.getTerminal().resize(cols: Int(viewport.cols), rows: Int(viewport.rows))
        view.frame = view.getOptimalFrameSize()
        view.renderObserver = coordinator
        view.terminalDelegate = self
        process = LocalProcess(delegate: self, dispatchQueue: .main)
    }

    func run() {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        let env = environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }

        process.startProcess(
            executable: "/usr/bin/ssh",
            args: arguments,
            environment: env
        )
        guard process.running else {
            coordinator.operationalFailure(code: "ssh_failed", detail: "OpenSSH failed to start")
            return
        }

        let deadline = Date(
            timeIntervalSinceNow: Double(timeoutMilliseconds) / 1_000
        )
        while !terminated && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        if !terminated {
            coordinator.operationalFailure(code: "ssh_timeout", detail: "OpenSSH exceeded capture timeout")
            process.terminate()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        } else {
            // The process-exit source can run before LocalProcess has delivered
            // every PTY slice already queued for the main thread. Require five
            // genuinely idle queue turns before declaring EOF authoritative.
            var idleTurns = 0
            while idleTurns < 5 && Date() < deadline {
                let bytesBefore = rawWire.count
                _ = RunLoop.main.run(
                    mode: .default,
                    before: Date(timeIntervalSinceNow: 0.05)
                )
                idleTurns = rawWire.count == bytesBefore ? idleTurns + 1 : 0
            }
            if exitStatus != 0 {
                coordinator.operationalFailure(
                    code: "ssh_failed",
                    detail: "OpenSSH exited with status \(exitStatus ?? -1)"
                )
            }
        }

        coordinator.finish(terminal: view.getTerminal())
        if let rawWireURL, rawWire.count <= rawWireLimit {
            try? FileManager.default.createDirectory(
                at: rawWireURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? rawWire.write(to: rawWireURL, options: .atomic)
        }
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        terminated = true
        guard let raw = exitCode else {
            exitStatus = nil
            return
        }
        if (raw & 0x7f) == 0 {
            exitStatus = (raw >> 8) & 0xff
        } else {
            exitStatus = 128 + (raw & 0x7f)
        }
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        if rawWire.count + slice.count <= rawWireLimit {
            rawWire.append(contentsOf: slice)
        } else {
            coordinator.resourceLimit(.rawWireBytes)
        }
        view.feed(byteArray: slice)
    }

    func getWindowSize() -> winsize {
        let width = UInt16(
            clamping: Int(
                (view.cellDimension.width * CGFloat(viewport.cols) * 2).rounded()
            )
        )
        let height = UInt16(
            clamping: Int(
                (view.cellDimension.height * CGFloat(viewport.rows) * 2).rounded()
            )
        )
        return winsize(
            ws_row: viewport.rows,
            ws_col: viewport.cols,
            ws_xpixel: width,
            ws_ypixel: height
        )
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }
}
