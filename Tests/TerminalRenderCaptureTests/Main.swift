import AppKit
import Foundation

enum CaptureTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message):
            return message
        }
    }
}

func captureRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CaptureTestFailure.assertion(message)
    }
}

@main
enum TerminalRenderCaptureTestsMain {
    static func main() {
        _ = NSApplication.shared
        do {
            try runSyncBoundaryTests()
            try runDrawObservationTests()
            try runArtifactTests()
            try runScenarioTests()
            try runAssertionTests()
            try runBaselineTests()
            try runLimitTests()
            try runLifecycleTests()
            print("terminal render capture tests passed")
        } catch {
            FileHandle.standardError.write(Data("test failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
