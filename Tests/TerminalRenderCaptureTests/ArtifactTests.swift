import Foundation

func sampleCell(
    text: String = "A",
    tile: UInt32 = 0,
    glyphs: [UInt32] = []
) -> CellRef {
    CellRef(
        sourceText: text,
        width: 1,
        continuationOf: nil,
        glyphDrawIds: glyphs,
        primitiveDrawIds: [],
        tileId: tile,
        foregroundRgba: RenderRGBA(red: 1, green: 1, blue: 1, alpha: 1),
        backgroundRgba: RenderRGBA(red: 0, green: 0, blue: 0, alpha: 1)
    )
}

func sampleArtifact(
    status: EvidenceKind = .complete,
    transport: String = "managed-loopback",
    portable: [PortableAssertionResult] = []
) -> CaptureArtifact {
    let frame = Frame(
        streamOrdinal: 0,
        checkpoints: ["first"],
        dimensions: Dimensions(cols: 1, rows: 1),
        baseRows: [[sampleCell()]],
        changes: [],
        drawCalls: [],
        framebufferRgbaSha256: String(repeating: "a", count: 64)
    )
    return CaptureArtifact(
        schema: "ai-survivors.terminal-render-capture/v1",
        status: EvidenceStatus(
            kind: status,
            reason: status == .complete
                ? nil
                : FailureReason(code: "draw_failed", detail: "test", limit: nil),
            lastAuthoritativeOrdinal: 0
        ),
        scenario: ArtifactScenario(
            id: "test-scenario",
            sha256: String(repeating: "b", count: 64)
        ),
        provenance: ArtifactProvenance(
            toolCommit: TerminalRenderCaptureBuildInfo.forkCommit,
            swifttermForkCommit: TerminalRenderCaptureBuildInfo.forkCommit,
            swifttermUpstreamBase: "58915b1010d7dbc86d0e79dc2c40f0c183ccaf5b"
        ),
        environment: ArtifactEnvironment(
            fingerprint: String(repeating: "c", count: 64),
            components: ["renderer": "test"]
        ),
        transport: ArtifactTransport(
            kind: transport,
            authoritativeBoundary: "dec-2026-explicit-reset",
            observedFrameCount: 1
        ),
        retention: ArtifactRetention(
            mode: "checkpoints",
            limits: ["observed_frames": 1],
            retainedOrdinals: [0]
        ),
        frames: [frame],
        glyphAtlas: [],
        cellTileAtlas: [],
        assertions: ArtifactAssertions(
            portable: portable,
            exact: ExactAssertionResult(kind: "unbaselined", firstDifference: nil)
        ),
        summary: ArtifactSummary(
            outcome: CaptureOutcome(
                kind: "unbaselined",
                failedAssertions: [],
                firstDifference: nil,
                reasonCode: nil,
                limit: nil
            ),
            observedFrames: 1,
            retainedFrames: 1,
            glyphCalls: 0,
            primitiveCalls: 0,
            uniqueGlyphs: 0,
            uniqueTiles: 0,
            canonicalBytes: 0,
            utilization: [:]
        )
    )
}

func runArtifactTests() throws {
    let artifact = sampleArtifact()
    let first = try CanonicalJSON.encode(artifact)
    let second = try CanonicalJSON.encode(artifact)
    try captureRequire(first == second, "canonical serialization must be byte-identical")
    try captureRequire(first.last == 0x0a, "canonical JSON must have one trailing newline")
    try captureRequire(
        String(decoding: first, as: UTF8.self).hasPrefix("{\n  \"assertions\""),
        "canonical JSON keys must be sorted with two-space indentation"
    )
    let decoded = try CanonicalJSON.decode(CaptureArtifact.self, from: first)
    try captureRequire(decoded == artifact, "artifact schema must round-trip exactly")

    let glyph = RenderedGlyph(
        row: 0,
        segmentColumn: 0,
        slotColumn: 0,
        slotWidth: 1,
        sourceUTF16Location: 2,
        sourceUTF16Length: 1,
        sourceScalars: [0x05d0],
        runStatusRaw: 1,
        rightToLeft: true,
        fontPostScriptName: "Fallback",
        fontFullName: "Fallback Regular",
        fontVersion: "1",
        fontFileSHA256: String(repeating: "e", count: 64),
        pointSize: 18,
        affineMatrix: RenderAffine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0),
        glyphID: 42,
        glyphNameIfAvailable: "alef",
        positionPoints: RenderPoint(x: 0, y: 0),
        advancePoints: RenderSize(width: 11, height: 0),
        foregroundRGBA: RenderRGBA(red: 1, green: 1, blue: 1, alpha: 1)
    )
    let glyphBytes = try CanonicalJSON.encode(glyph)
    let decodedGlyph = try CanonicalJSON.decode(RenderedGlyph.self, from: glyphBytes)
    try captureRequire(
        decodedGlyph == glyph,
        "rendered glyph acronym fields must round-trip through canonical snake-case JSON"
    )

    let root = URL(fileURLWithPath: ".build/test-artifact", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    let url = root.appendingPathComponent("capture.json")
    _ = try CanonicalJSON.writeAtomic(artifact, to: url)
    try captureRequire(FileManager.default.fileExists(atPath: url.path), "atomic artifact missing")
    try captureRequire(
        !FileManager.default.fileExists(atPath: url.appendingPathExtension("partial").path),
        "successful atomic write must not leave a partial"
    )

    let next = sampleCell(text: "B", tile: 1)
    let delta = Frame(
        streamOrdinal: 1,
        checkpoints: ["second"],
        dimensions: Dimensions(cols: 1, rows: 1),
        baseRows: nil,
        changes: [CellChange(col: 0, row: 0, cell: next)],
        drawCalls: [],
        framebufferRgbaSha256: String(repeating: "d", count: 64)
    )
    var rows = artifact.frames[0].baseRows!
    for change in delta.changes {
        rows[Int(change.row)][Int(change.col)] = change.cell
    }
    try captureRequire(rows == [[next]], "applying a delta must reconstruct the full frame")
}
