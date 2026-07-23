import AppKit
import CoreText
import CryptoKit
import Darwin
import Foundation

enum CaptureEnvironmentError: Error {
    case fontUnavailable
    case fontFileUnavailable
}

enum CaptureEnvironment {
    static func make(
        frame: RenderFrameInfo,
        glyphs: [RenderedGlyph],
        scenario: ValidatedScenario?
    ) throws -> ArtifactEnvironment {
        guard
            let baseFont = NSFont(name: "Menlo-Regular", size: 18),
            baseFont.fontName == "Menlo-Regular"
        else {
            throw CaptureEnvironmentError.fontUnavailable
        }
        let ctFont = baseFont as CTFont
        guard
            let baseURL = CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL,
            let baseData = try? Data(contentsOf: baseURL, options: .mappedIfSafe)
        else {
            throw CaptureEnvironmentError.fontFileUnavailable
        }

        let operating = ProcessInfo.processInfo.operatingSystemVersion
        var buildBuffer = [CChar](repeating: 0, count: 256)
        var buildSize = buildBuffer.count
        let build = sysctlbyname("kern.osversion", &buildBuffer, &buildSize, nil, 0) == 0
            ? String(cString: buildBuffer)
            : "unknown"
        let fallbacks = Set(
            glyphs
                .filter { $0.fontFileSHA256 != baseData.sha256Hex }
                .map {
                    "\($0.fontPostScriptName)|\($0.fontVersion)|\($0.fontFileSHA256)"
                }
        ).sorted().joined(separator: ",")

        let components: [String: String] = [
            "architecture": "arm64",
            "artifact_schema": "ai-survivors.terminal-render-capture/v1",
            "backing_scale": canonicalDecimal(frame.backingScale),
            "base_font": "Menlo-Regular|\(CTFontCopyFullName(ctFont))|\(baseData.sha256Hex)|18",
            "cell_size": "\(canonicalDecimal(frame.cellSizePoints.width))x\(canonicalDecimal(frame.cellSizePoints.height))",
            "deployment_target": "arm64-apple-macosx13.0",
            "fallback_fonts": fallbacks,
            "font_smoothing": "true",
            "fork_commit": TerminalRenderCaptureBuildInfo.forkCommit,
            "locale": "en_US.UTF-8",
            "macos": "\(operating.majorVersion).\(operating.minorVersion).\(operating.patchVersion)|\(build)",
            "renderer_backend": "swiftterm-appkit-cpu",
            "scenario_sha256": scenario?.sha256 ?? "observational",
            "sdk": "15.4|/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk",
            "swift": "Apple Swift version 6.3.2|swiftlang-6.3.2.1.108",
            "upstream_base": "58915b1010d7dbc86d0e79dc2c40f0c183ccaf5b",
            "viewport": "\(frame.columns)x\(frame.rows)",
        ]
        let data = try CanonicalJSON.encode(components)
        return ArtifactEnvironment(fingerprint: data.sha256Hex, components: components)
    }

    private static func canonicalDecimal(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
