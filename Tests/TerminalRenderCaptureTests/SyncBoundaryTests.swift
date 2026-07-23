import Foundation

private final class SyncReasonDelegate: TerminalDelegate {
    var reasons: [SynchronizedOutputEndReason] = []

    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    func synchronizedOutputEnded(source: Terminal, reason: SynchronizedOutputEndReason) {
        reasons.append(reason)
    }
}

func runSyncBoundaryTests() throws {
    let delegate = SyncReasonDelegate()
    let terminal = Terminal(
        delegate: delegate,
        options: TerminalOptions(cols: 40, rows: 10)
    )

    let twoFrames = Array(
        ("\u{1b}[?2026hone\u{1b}[?2026l"
            + "\u{1b}[?2026htwo\u{1b}[?2026l").utf8
    )
    terminal.feed(buffer: twoFrames[...])
    try captureRequire(
        delegate.reasons == [.explicitReset, .explicitReset],
        "two explicit synchronized frames in one feed must close independently"
    )

    terminal.feed(buffer: Array("\u{1b}[?2026hreset".utf8)[...])
    terminal.resetToInitialState()
    try captureRequire(
        delegate.reasons.last == .terminalReset,
        "terminal reset must not masquerade as an explicit frame"
    )

    terminal.feed(buffer: Array("\u{1b}[?2026hresize".utf8)[...])
    terminal.resize(cols: 41, rows: 10)
    try captureRequire(
        delegate.reasons.last == .terminalReset,
        "resize while synchronized must report terminalReset"
    )

    terminal.feed(buffer: Array("\u{1b}[?2026htimeout".utf8)[...])
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
    try captureRequire(
        delegate.reasons.last == .timeout,
        "the safety timer must report timeout"
    )
}
