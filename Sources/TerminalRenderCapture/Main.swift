import AppKit
import Foundation

@main
enum TerminalRenderCaptureMain {
    static func main() {
        do {
            switch try CLI.parse(Array(CommandLine.arguments.dropFirst())) {
            case .selfTest:
                guard NSFont(name: "Menlo-Regular", size: 18)?.fontName == "Menlo-Regular" else {
                    FileHandle.standardError.write(Data("Menlo-Regular 18pt unavailable\n".utf8))
                    exit(CaptureExit.operationalFailure.rawValue)
                }
                print("terminal-render-capture self-test passed")
            case .version:
                print(TerminalRenderCaptureBuildInfo.forkCommit)
            }
        } catch {
            FileHandle.standardError.write(Data((CLI.usage + "\n").utf8))
            exit(CaptureExit.usage.rawValue)
        }
    }
}
