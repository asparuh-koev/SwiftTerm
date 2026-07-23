import Foundation

enum CaptureExit: Int32 {
    case success = 0
    case usage = 2
    case comparisonFailed = 3
    case operationalFailure = 4
    case truncated = 5
}

enum CaptureCommand: Equatable {
    case selfTest
    case version
}

enum CLI {
    static let usage = """
    usage:
      terminal-render-capture self-test
      terminal-render-capture --version
    """

    static func parse(_ arguments: [String]) throws -> CaptureCommand {
        switch arguments {
        case ["self-test"]:
            return .selfTest
        case ["--version"]:
            return .version
        default:
            throw CLIError.usage
        }
    }
}

enum CLIError: Error {
    case usage
}
