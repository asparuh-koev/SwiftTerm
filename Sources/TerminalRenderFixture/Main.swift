import Foundation

@main
enum TerminalRenderFixtureMain {
    static func main() {
        let payload = "\u{1b}[?2026h\u{1b}[2J\u{1b}[Hterminal-render-fixture\u{1b}[?2026l"
        FileHandle.standardOutput.write(Data(payload.utf8))
    }
}
