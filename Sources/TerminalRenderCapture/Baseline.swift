import Foundation

private struct UnsignedBaselinePayload: Codable {
    let schema: String
    let scenario: ArtifactScenario
    let provenance: ArtifactProvenance
    let environment: ArtifactEnvironment
    let frames: [Frame]
    let glyphAtlas: [GlyphAtlasEntry]
    let cellTileAtlas: [CellTileAtlasEntry]
}

enum BaselineError: Error {
    case ineligible
    case exists
    case invalid
}

enum BaselineStore {
    static func compare(
        artifact: CaptureArtifact,
        root: URL
    ) -> ExactAssertionResult {
        let url = path(for: artifact, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ExactAssertionResult(kind: "unbaselined", firstDifference: nil)
        }
        guard
            let baseline = try? CanonicalJSON.read(BaselinePayload.self, from: url),
            let current = try? payload(from: artifact)
        else {
            return ExactAssertionResult(kind: "mismatch", firstDifference: "baseline.invalid")
        }
        guard baseline == current else {
            return ExactAssertionResult(
                kind: "mismatch",
                firstDifference: firstDifference(baseline, current)
            )
        }
        return ExactAssertionResult(kind: "passed", firstDifference: nil)
    }

    static func update(
        artifact: CaptureArtifact,
        root: URL,
        replace: Bool
    ) throws -> URL {
        guard
            artifact.status.kind == .complete,
            artifact.transport.kind == "managed-loopback",
            artifact.assertions.portable.allSatisfy(\.passed),
            artifact.summary.outcome.kind != "truncated",
            artifact.provenance.swifttermForkCommit == TerminalRenderCaptureBuildInfo.forkCommit
        else {
            throw BaselineError.ineligible
        }
        let url = path(for: artifact, root: root)
        if FileManager.default.fileExists(atPath: url.path) && !replace {
            throw BaselineError.exists
        }
        let value = try payload(from: artifact)
        _ = try CanonicalJSON.writeAtomic(value, to: url)
        return url
    }

    static func payload(from artifact: CaptureArtifact) throws -> BaselinePayload {
        let unsigned = UnsignedBaselinePayload(
            schema: artifact.schema,
            scenario: artifact.scenario,
            provenance: artifact.provenance,
            environment: artifact.environment,
            frames: artifact.frames,
            glyphAtlas: artifact.glyphAtlas,
            cellTileAtlas: artifact.cellTileAtlas
        )
        let digest = try CanonicalJSON.encode(unsigned).sha256Hex
        return BaselinePayload(
            schema: unsigned.schema,
            scenario: unsigned.scenario,
            provenance: unsigned.provenance,
            environment: unsigned.environment,
            frames: unsigned.frames,
            glyphAtlas: unsigned.glyphAtlas,
            cellTileAtlas: unsigned.cellTileAtlas,
            payloadSha256: digest
        )
    }

    private static func path(for artifact: CaptureArtifact, root: URL) -> URL {
        root
            .appendingPathComponent(artifact.scenario.id, isDirectory: true)
            .appendingPathComponent("\(artifact.environment.fingerprint).json")
    }

    private static func firstDifference(
        _ lhs: BaselinePayload,
        _ rhs: BaselinePayload
    ) -> String {
        if lhs.schema != rhs.schema { return "schema" }
        if lhs.scenario != rhs.scenario { return "scenario" }
        if lhs.provenance != rhs.provenance { return "provenance" }
        if lhs.environment != rhs.environment { return "environment" }
        if lhs.frames != rhs.frames { return "frames" }
        if lhs.glyphAtlas != rhs.glyphAtlas { return "glyph_atlas" }
        if lhs.cellTileAtlas != rhs.cellTileAtlas { return "cell_tile_atlas" }
        return "payload_sha256"
    }
}
