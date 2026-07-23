import Foundation

@main
enum TerminalRenderFixtureMain {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--compat") {
            let frame = """
            \u{1b}[?2026h\u{1b}[2J\u{1b}[Hcompatibility smoke
            Hebrew: שלום אאב
            Arabic: سلام بب ب
            Fallback: Ϟ א ب ⣿
            Primitives: █ ░ ▄ ─
            \u{1b}[?2026l
            """
            FileHandle.standardOutput.write(Data(frame.utf8))
            Thread.sleep(forTimeInterval: 5)
            return
        }
        if CommandLine.arguments.dropFirst().contains("--throughput") {
            for ordinal in 0..<30 {
                let frame = "\u{1b}[?2026h\u{1b}[2J\u{1b}[Hthroughput \(ordinal) שלום سلام █ ─\u{1b}[?2026l"
                FileHandle.standardOutput.write(Data(frame.utf8))
                Thread.sleep(forTimeInterval: 1.0 / 30.0)
            }
            return
        }
        let payload = """
        \u{1b}[?2026h\u{1b}[2J\u{1b}[Hterminal-render-fixture
        Hebrew: שלום אאב
        Arabic: سلام بب ب
        Fallback: Ϟ א ب ⠿
        Primitives: █ ░ ▄ ─
        \u{1b}[?2026l
        """
        FileHandle.standardOutput.write(Data(payload.utf8))
    }
}
