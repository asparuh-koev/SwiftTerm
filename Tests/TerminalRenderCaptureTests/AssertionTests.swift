import Foundation

private func assertion(
    kind: String,
    name: String,
    checkpoint: String? = nil,
    from: String? = nil,
    to: String? = nil,
    cell: CellPoint? = nil,
    expected: PortableAssertion.JSONScalar? = nil,
    source: String? = nil
) -> PortableAssertion {
    PortableAssertion(
        kind: kind,
        name: name,
        checkpoint: checkpoint,
        fromCheckpoint: from,
        toCheckpoint: to,
        checkpoints: nil,
        cell: cell,
        region: nil,
        expected: expected,
        minimumOccupiedCells: nil,
        source: source,
        sources: nil,
        expectedSources: nil,
        visualColumns: nil,
        minimumDraws: nil,
        primitiveKind: nil,
        minimumCount: nil
    )
}

func runAssertionTests() throws {
    let assertions = [
        assertion(
            kind: "cell_source_equals",
            name: "source",
            checkpoint: "first",
            cell: CellPoint(col: 0, row: 0),
            expected: .string("A")
        ),
        assertion(
            kind: "same_source_glyph_unchanged",
            name: "unchanged",
            from: "first",
            to: "second",
            cell: CellPoint(col: 0, row: 0),
            source: "A"
        ),
    ]
    let document = ScenarioV1(
        schema: "ai-survivors.terminal-render-scenario/v1",
        id: "test-scenario",
        fixture: FixtureV1(
            kind: "ai-survivors-special-characters",
            version: 1,
            stages: []
        ),
        seed: 1,
        viewport: Viewport(cols: 1, rows: 1),
        simHz: 60,
        flushEvery: 2,
        ticks: 2,
        inputs: [],
        checkpoints: [
            Checkpoint(name: "first", tick: 1),
            Checkpoint(name: "second", tick: 2),
        ],
        portableAssertions: assertions,
        limits: ScenarioLimits(
            observedFrames: 2,
            retainedFrames: 2,
            completeFrames: 2,
            failureContextBefore: 0,
            failureContextAfter: 0,
            glyphAtlasEntries: 1,
            cellTileAtlasEntries: 1,
            canonicalJsonBytes: 1_000_000,
            rawWireBytes: 1_000_000,
            childTimeoutMs: 1_000
        )
    )
    let scenario = ValidatedScenario(
        document: document,
        sourceBytes: Data(),
        sha256: String(repeating: "b", count: 64),
        checkpointsByOrdinal: [:]
    )
    let first = sampleArtifact().frames[0]
    let second = Frame(
        streamOrdinal: 1,
        checkpoints: ["second"],
        dimensions: Dimensions(cols: 1, rows: 1),
        baseRows: nil,
        changes: [],
        drawCalls: [],
        framebufferRgbaSha256: String(repeating: "e", count: 64)
    )
    let results = PortableAssertions.evaluate(
        scenario: scenario,
        frames: [first, second],
        glyphAtlas: []
    )
    try captureRequire(results.map(\.passed) == [true, true], "portable assertions must pass")

    let failingDocument = ScenarioV1(
        schema: document.schema,
        id: document.id,
        fixture: document.fixture,
        seed: document.seed,
        viewport: document.viewport,
        simHz: document.simHz,
        flushEvery: document.flushEvery,
        ticks: document.ticks,
        inputs: document.inputs,
        checkpoints: document.checkpoints,
        portableAssertions: [
            assertion(
                kind: "cell_source_equals",
                name: "fails",
                checkpoint: "first",
                cell: CellPoint(col: 0, row: 0),
                expected: .string("wrong")
            ),
        ],
        limits: document.limits
    )
    let failing = PortableAssertions.evaluate(
        scenario: ValidatedScenario(
            document: failingDocument,
            sourceBytes: Data(),
            sha256: scenario.sha256,
            checkpointsByOrdinal: [:]
        ),
        frames: [first],
        glyphAtlas: []
    )
    try captureRequire(
        failing.count == 1 && !failing[0].passed && failing[0].name == "fails",
        "portable failures must retain named evidence without short-circuiting"
    )
}
