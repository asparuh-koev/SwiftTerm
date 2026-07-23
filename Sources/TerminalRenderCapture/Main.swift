import AppKit
import Foundation

@main
enum TerminalRenderCaptureMain {
    static func main() {
        _ = NSApplication.shared
        do {
            let command = try CLI.parse(Array(CommandLine.arguments.dropFirst()))
            exit(try run(command).rawValue)
        } catch CLIError.usage {
            FileHandle.standardError.write(Data((CLI.usage + "\n").utf8))
            exit(CaptureExit.usage.rawValue)
        } catch {
            FileHandle.standardError.write(Data("terminal-render-capture failed\n".utf8))
            exit(CaptureExit.operationalFailure.rawValue)
        }
    }

    private static func run(_ command: CaptureCommand) throws -> CaptureExit {
        switch command {
        case let .capture(options):
            return try capture(options)
        case let .compare(artifactURL, scenarioURL, baselineRoot):
            return try compare(
                artifactURL: artifactURL,
                scenarioURL: scenarioURL,
                baselineRoot: baselineRoot
            )
        case let .baselineUpdate(artifactURL, baselineRoot, replace):
            let artifact = try CanonicalJSON.read(CaptureArtifact.self, from: artifactURL)
            do {
                let url = try BaselineStore.update(
                    artifact: artifact,
                    root: baselineRoot,
                    replace: replace
                )
                print(url.path)
                return .success
            } catch {
                return .usage
            }
        case let .compatibility(terminal, scenario, manifest, screenshot, sshArguments):
            return CompatibilityRunner.run(
                terminal: terminal,
                scenario: scenario,
                manifest: manifest,
                screenshot: screenshot,
                sshArguments: sshArguments
            )
        case .selfTest:
            guard NSFont(name: "Menlo-Regular", size: 18)?.fontName == "Menlo-Regular" else {
                return .operationalFailure
            }
            let probe = ["schema": "self-test", "value": "שלום سلام"]
            let encoded = try CanonicalJSON.encode(probe)
            let decoded = try CanonicalJSON.decode([String: String].self, from: encoded)
            guard decoded == probe else {
                return .operationalFailure
            }
            print("terminal-render-capture self-test passed")
            return .success
        case .version:
            print(TerminalRenderCaptureBuildInfo.forkCommit)
            return .success
        }
    }

    private static func capture(_ options: CaptureOptions) throws -> CaptureExit {
        let scenario = try options.scenario.map(ScenarioLoader.load)
        let manifestResult: (CheckpointManifest, [UInt32: [String]])?
        if let scenario, let manifestURL = options.manifest {
            manifestResult = try ScenarioLoader.loadManifest(manifestURL, scenario: scenario)
        } else {
            manifestResult = nil
        }
        let viewport = scenario?.document.viewport ?? options.viewport!
        let limits = scenario.map { ActiveLimits($0.document.limits) } ?? .direct
        let coordinator = CaptureCoordinator(
            scenario: scenario,
            manifest: manifestResult?.0,
            checkpointNames: manifestResult?.1 ?? [:],
            limits: limits,
            retainComplete: options.retainComplete
        )
        let transport = try OpenSSHProcess(
            coordinator: coordinator,
            viewport: viewport,
            arguments: options.sshArguments,
            timeoutMilliseconds: options.timeoutSeconds * 1_000,
            rawWireURL: options.rawWire,
            rawWireLimit: limits.rawWireBytes
        )
        transport.run()

        if let png = options.png, let pixels = coordinator.lastAuthoritativePixels {
            try? writePNG(pixels: pixels, to: png)
        }

        var status: EvidenceStatus
        if let limit = coordinator.truncation {
            status = EvidenceStatus(
                kind: .truncated,
                reason: FailureReason(
                    code: "limit_exceeded",
                    detail: "capture resource ceiling reached",
                    limit: limit.rawValue
                ),
                lastAuthoritativeOrdinal: coordinator.observedFrameCount == 0
                    ? nil
                    : coordinator.observedFrameCount - 1
            )
        } else if let failure = coordinator.failure {
            status = EvidenceStatus(
                kind: .incomplete,
                reason: failure,
                lastAuthoritativeOrdinal: coordinator.observedFrameCount == 0
                    ? nil
                    : coordinator.observedFrameCount - 1
            )
        } else {
            status = EvidenceStatus(
                kind: .complete,
                reason: nil,
                lastAuthoritativeOrdinal: coordinator.observedFrameCount - 1
            )
        }

        let glyphs = coordinator.frames.flatMap(\.drawCalls).compactMap { draw -> RenderedGlyph? in
            guard case let .glyph(_, value) = draw else { return nil }
            return value
        }
        let environment: ArtifactEnvironment
        do {
            guard let frameInfo = coordinator.lastFrameInfo else {
                throw CaptureEnvironmentError.fontUnavailable
            }
            environment = try CaptureEnvironment.make(
                frame: frameInfo,
                glyphs: glyphs,
                scenario: scenario
            )
        } catch {
            status = EvidenceStatus(
                kind: .incomplete,
                reason: FailureReason(
                    code: "font_unavailable",
                    detail: "font environment could not be resolved",
                    limit: nil
                ),
                lastAuthoritativeOrdinal: status.lastAuthoritativeOrdinal
            )
            environment = ArtifactEnvironment(
                fingerprint: String(repeating: "0", count: 64),
                components: [:]
            )
        }

        let portable = status.kind == .complete && scenario != nil
            ? PortableAssertions.evaluate(
                scenario: scenario!,
                frames: coordinator.frames,
                glyphAtlas: coordinator.glyphAtlas()
            )
            : []
        let portableFailed = portable.filter { !$0.passed }.map(\.name)
        var exact = ExactAssertionResult(kind: "not_run", firstDifference: nil)
        var outcome = outcomeFor(
            status: status,
            portableFailed: portableFailed,
            exact: exact
        )
        var artifact = makeArtifact(
            status: status,
            scenario: scenario,
            environment: environment,
            transportKind: scenario == nil ? "observational-direct" : "managed-loopback",
            coordinator: coordinator,
            limits: limits,
            retainComplete: options.retainComplete,
            portable: portable,
            exact: exact,
            outcome: outcome,
            canonicalBytes: 0
        )
        if
            status.kind == .complete,
            portableFailed.isEmpty,
            let baselineRoot = options.baselineRoot
        {
            exact = BaselineStore.compare(artifact: artifact, root: baselineRoot)
            outcome = outcomeFor(status: status, portableFailed: [], exact: exact)
            artifact = replacingAssertions(
                artifact,
                portable: portable,
                exact: exact,
                outcome: outcome
            )
        }

        artifact = try stabilizeCanonicalBytes(artifact)
        if artifact.summary.canonicalBytes > limits.canonicalJsonBytes {
            status = EvidenceStatus(
                kind: .truncated,
                reason: FailureReason(
                    code: "limit_exceeded",
                    detail: "capture resource ceiling reached",
                    limit: CaptureLimit.canonicalJsonBytes.rawValue
                ),
                lastAuthoritativeOrdinal: status.lastAuthoritativeOrdinal
            )
            outcome = outcomeFor(status: status, portableFailed: portableFailed, exact: exact)
            artifact = try stabilizeCanonicalBytes(
                replacingStatus(artifact, status: status, outcome: outcome)
            )
        }
        _ = try CanonicalJSON.writeAtomic(artifact, to: options.artifact)
        return exitFor(artifact.summary.outcome)
    }

    private static func compare(
        artifactURL: URL,
        scenarioURL: URL,
        baselineRoot: URL
    ) throws -> CaptureExit {
        let scenario = try ScenarioLoader.load(scenarioURL)
        var artifact = try CanonicalJSON.read(CaptureArtifact.self, from: artifactURL)
        guard
            artifact.scenario.id == scenario.document.id,
            artifact.scenario.sha256 == scenario.sha256
        else {
            return .usage
        }
        let portable = artifact.status.kind == .complete
            ? PortableAssertions.evaluate(
                scenario: scenario,
                frames: artifact.frames,
                glyphAtlas: artifact.glyphAtlas
            )
            : []
        let failed = portable.filter { !$0.passed }.map(\.name)
        let exact = failed.isEmpty && artifact.status.kind == .complete
            ? BaselineStore.compare(artifact: artifact, root: baselineRoot)
            : ExactAssertionResult(kind: "not_run", firstDifference: nil)
        let outcome = outcomeFor(status: artifact.status, portableFailed: failed, exact: exact)
        artifact = try stabilizeCanonicalBytes(
            replacingAssertions(
                artifact,
                portable: portable,
                exact: exact,
                outcome: outcome
            )
        )
        _ = try CanonicalJSON.writeAtomic(artifact, to: artifactURL)
        return exitFor(outcome)
    }

    private static func outcomeFor(
        status: EvidenceStatus,
        portableFailed: [String],
        exact: ExactAssertionResult
    ) -> CaptureOutcome {
        if status.kind == .truncated {
            return CaptureOutcome(
                kind: "truncated",
                failedAssertions: [],
                firstDifference: nil,
                reasonCode: nil,
                limit: status.reason?.limit
            )
        }
        if status.kind == .incomplete {
            return CaptureOutcome(
                kind: "incomplete",
                failedAssertions: [],
                firstDifference: nil,
                reasonCode: status.reason?.code,
                limit: nil
            )
        }
        if !portableFailed.isEmpty {
            return CaptureOutcome(
                kind: "portable_assertion_failed",
                failedAssertions: portableFailed,
                firstDifference: nil,
                reasonCode: nil,
                limit: nil
            )
        }
        if exact.kind == "mismatch" {
            return CaptureOutcome(
                kind: "exact_mismatch",
                failedAssertions: [],
                firstDifference: exact.firstDifference,
                reasonCode: nil,
                limit: nil
            )
        }
        return CaptureOutcome(
            kind: exact.kind == "unbaselined" ? "unbaselined" : "passed",
            failedAssertions: [],
            firstDifference: nil,
            reasonCode: nil,
            limit: nil
        )
    }

    private static func makeArtifact(
        status: EvidenceStatus,
        scenario: ValidatedScenario?,
        environment: ArtifactEnvironment,
        transportKind: String,
        coordinator: CaptureCoordinator,
        limits: ActiveLimits,
        retainComplete: Bool,
        portable: [PortableAssertionResult],
        exact: ExactAssertionResult,
        outcome: CaptureOutcome,
        canonicalBytes: UInt64
    ) -> CaptureArtifact {
        let glyphCalls = coordinator.frames.flatMap(\.drawCalls).filter {
            if case .glyph = $0 { return true }
            return false
        }.count
        let primitiveCalls = coordinator.frames.flatMap(\.drawCalls).count - glyphCalls
        return CaptureArtifact(
            schema: "ai-survivors.terminal-render-capture/v1",
            status: status,
            scenario: ArtifactScenario(
                id: scenario?.document.id ?? "direct-observational",
                sha256: scenario?.sha256 ?? String(repeating: "0", count: 64)
            ),
            provenance: ArtifactProvenance(
                toolCommit: TerminalRenderCaptureBuildInfo.forkCommit,
                swifttermForkCommit: TerminalRenderCaptureBuildInfo.forkCommit,
                swifttermUpstreamBase: "58915b1010d7dbc86d0e79dc2c40f0c183ccaf5b"
            ),
            environment: environment,
            transport: ArtifactTransport(
                kind: transportKind,
                authoritativeBoundary: "dec-2026-explicit-reset",
                observedFrameCount: coordinator.observedFrameCount
            ),
            retention: ArtifactRetention(
                mode: retainComplete ? "complete" : "checkpoints",
                limits: limits.serialized,
                retainedOrdinals: coordinator.frames.map(\.streamOrdinal)
            ),
            frames: coordinator.frames,
            glyphAtlas: coordinator.glyphAtlas(),
            cellTileAtlas: coordinator.cellTileAtlas(),
            assertions: ArtifactAssertions(portable: portable, exact: exact),
            summary: ArtifactSummary(
                outcome: outcome,
                observedFrames: coordinator.observedFrameCount,
                retainedFrames: UInt32(coordinator.frames.count),
                glyphCalls: UInt32(glyphCalls),
                primitiveCalls: UInt32(primitiveCalls),
                uniqueGlyphs: UInt32(coordinator.glyphAtlas().count),
                uniqueTiles: UInt32(coordinator.cellTileAtlas().count),
                canonicalBytes: canonicalBytes,
                utilization: [
                    "observed_frames": UInt64(coordinator.observedFrameCount),
                    "retained_frames": UInt64(coordinator.frames.count),
                    "glyph_atlas_entries": UInt64(coordinator.glyphAtlas().count),
                    "cell_tile_atlas_entries": UInt64(coordinator.cellTileAtlas().count),
                ]
            )
        )
    }

    private static func replacingAssertions(
        _ artifact: CaptureArtifact,
        portable: [PortableAssertionResult],
        exact: ExactAssertionResult,
        outcome: CaptureOutcome
    ) -> CaptureArtifact {
        CaptureArtifact(
            schema: artifact.schema,
            status: artifact.status,
            scenario: artifact.scenario,
            provenance: artifact.provenance,
            environment: artifact.environment,
            transport: artifact.transport,
            retention: artifact.retention,
            frames: artifact.frames,
            glyphAtlas: artifact.glyphAtlas,
            cellTileAtlas: artifact.cellTileAtlas,
            assertions: ArtifactAssertions(portable: portable, exact: exact),
            summary: ArtifactSummary(
                outcome: outcome,
                observedFrames: artifact.summary.observedFrames,
                retainedFrames: artifact.summary.retainedFrames,
                glyphCalls: artifact.summary.glyphCalls,
                primitiveCalls: artifact.summary.primitiveCalls,
                uniqueGlyphs: artifact.summary.uniqueGlyphs,
                uniqueTiles: artifact.summary.uniqueTiles,
                canonicalBytes: artifact.summary.canonicalBytes,
                utilization: artifact.summary.utilization
            )
        )
    }

    private static func replacingStatus(
        _ artifact: CaptureArtifact,
        status: EvidenceStatus,
        outcome: CaptureOutcome
    ) -> CaptureArtifact {
        let replaced = replacingAssertions(
            artifact,
            portable: artifact.assertions.portable,
            exact: artifact.assertions.exact,
            outcome: outcome
        )
        return CaptureArtifact(
            schema: replaced.schema,
            status: status,
            scenario: replaced.scenario,
            provenance: replaced.provenance,
            environment: replaced.environment,
            transport: replaced.transport,
            retention: replaced.retention,
            frames: replaced.frames,
            glyphAtlas: replaced.glyphAtlas,
            cellTileAtlas: replaced.cellTileAtlas,
            assertions: replaced.assertions,
            summary: replaced.summary
        )
    }

    private static func stabilizeCanonicalBytes(
        _ artifact: CaptureArtifact
    ) throws -> CaptureArtifact {
        var value = artifact
        for _ in 0..<4 {
            let count = UInt64(try CanonicalJSON.encode(value).count)
            if count == value.summary.canonicalBytes {
                return value
            }
            value = replacingCanonicalBytes(value, count: count)
        }
        return value
    }

    private static func replacingCanonicalBytes(
        _ artifact: CaptureArtifact,
        count: UInt64
    ) -> CaptureArtifact {
        CaptureArtifact(
            schema: artifact.schema,
            status: artifact.status,
            scenario: artifact.scenario,
            provenance: artifact.provenance,
            environment: artifact.environment,
            transport: artifact.transport,
            retention: artifact.retention,
            frames: artifact.frames,
            glyphAtlas: artifact.glyphAtlas,
            cellTileAtlas: artifact.cellTileAtlas,
            assertions: artifact.assertions,
            summary: ArtifactSummary(
                outcome: artifact.summary.outcome,
                observedFrames: artifact.summary.observedFrames,
                retainedFrames: artifact.summary.retainedFrames,
                glyphCalls: artifact.summary.glyphCalls,
                primitiveCalls: artifact.summary.primitiveCalls,
                uniqueGlyphs: artifact.summary.uniqueGlyphs,
                uniqueTiles: artifact.summary.uniqueTiles,
                canonicalBytes: count,
                utilization: artifact.summary.utilization
            )
        )
    }

    private static func exitFor(_ outcome: CaptureOutcome) -> CaptureExit {
        switch outcome.kind {
        case "passed", "unbaselined":
            return .success
        case "portable_assertion_failed", "exact_mismatch":
            return .comparisonFailed
        case "truncated":
            return .truncated
        default:
            return .operationalFailure
        }
    }

    private static func writePNG(pixels: OffscreenFramePixels, to url: URL) throws {
        guard
            let provider = CGDataProvider(data: pixels.rgba as CFData),
            let image = CGImage(
                width: pixels.width,
                height: pixels.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: pixels.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw ArtifactError.write
        }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ArtifactError.write
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
