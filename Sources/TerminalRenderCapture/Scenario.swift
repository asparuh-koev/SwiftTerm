import CryptoKit
import Foundation

struct Viewport: Codable, Equatable {
    let cols: UInt16
    let rows: UInt16
}

struct FixtureCellV1: Codable, Equatable {
    let col: UInt16
    let row: UInt16
    let symbol: String
    let fg: [UInt8]
    let bg: [UInt8]
}

struct FixtureStageV1: Codable, Equatable {
    let name: String
    let cells: [FixtureCellV1]
}

struct FixtureV1: Codable, Equatable {
    let kind: String
    let version: Int
    let stages: [FixtureStageV1]
}

struct InputEvent: Codable, Equatable {
    let tick: UInt32
    let keys: [String]
}

struct Checkpoint: Codable, Equatable {
    let name: String
    let tick: UInt32
}

struct ScenarioLimits: Codable, Equatable {
    let observedFrames: UInt32
    let retainedFrames: UInt32
    let completeFrames: UInt32
    let failureContextBefore: UInt8
    let failureContextAfter: UInt8
    let glyphAtlasEntries: UInt32
    let cellTileAtlasEntries: UInt32
    let canonicalJsonBytes: UInt64
    let rawWireBytes: UInt64
    let childTimeoutMs: UInt64
}

struct CellPoint: Codable, Equatable, Hashable {
    let col: UInt16
    let row: UInt16
}

struct CellRegion: Codable, Equatable {
    let col: UInt16
    let row: UInt16
    let cols: UInt16
    let rows: UInt16
}

struct PortableAssertion: Codable, Equatable {
    let kind: String
    let name: String
    let checkpoint: String?
    let fromCheckpoint: String?
    let toCheckpoint: String?
    let checkpoints: [String]?
    let cell: CellPoint?
    let region: CellRegion?
    let expected: JSONScalar?
    let minimumOccupiedCells: UInt32?
    let source: String?
    let sources: [String]?
    let expectedSources: [String]?
    let visualColumns: String?
    let minimumDraws: UInt32?
    let primitiveKind: String?
    let minimumCount: UInt32?

    enum JSONScalar: Codable, Equatable {
        case string(String)
        case integer(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                self = .integer(try container.decode(Int.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value):
                try container.encode(value)
            case let .integer(value):
                try container.encode(value)
            }
        }
    }
}

struct ScenarioV1: Codable, Equatable {
    let schema: String
    let id: String
    let fixture: FixtureV1
    let seed: UInt64
    let viewport: Viewport
    let simHz: UInt32
    let flushEvery: UInt32
    let ticks: UInt32
    let inputs: [InputEvent]
    let checkpoints: [Checkpoint]
    let portableAssertions: [PortableAssertion]
    let limits: ScenarioLimits
}

struct ManifestFrame: Codable, Equatable {
    let streamOrdinal: UInt32
    let tick: UInt32
    let checkpointNames: [String]
}

struct CheckpointManifest: Codable, Equatable {
    let schema: String
    let scenarioId: String
    let scenarioSha256: String
    let viewport: Viewport
    let frames: [ManifestFrame]
    let expectedFinalOrdinal: UInt32
}

enum ScenarioError: Error, CustomStringConvertible {
    case read
    case decode
    case invalid(String)

    var description: String {
        switch self {
        case .read:
            return "scenario_read"
        case .decode:
            return "scenario_decode"
        case let .invalid(field):
            return "scenario_invalid:\(field)"
        }
    }
}

struct ValidatedScenario {
    let document: ScenarioV1
    let sourceBytes: Data
    let sha256: String
    let checkpointsByOrdinal: [UInt32: [String]]
}

enum ScenarioLoader {
    static func load(_ url: URL) throws -> ValidatedScenario {
        guard let data = try? Data(contentsOf: url) else {
            throw ScenarioError.read
        }
        try validateClosedScenarioShape(data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let document = try? decoder.decode(ScenarioV1.self, from: data) else {
            throw ScenarioError.decode
        }
        try validate(document)
        return ValidatedScenario(
            document: document,
            sourceBytes: data,
            sha256: SHA256.hash(data: data).hex,
            checkpointsByOrdinal: [:]
        )
    }

    static func loadManifest(
        _ url: URL,
        scenario: ValidatedScenario
    ) throws -> (CheckpointManifest, [UInt32: [String]]) {
        guard let data = try? Data(contentsOf: url) else {
            throw ScenarioError.invalid("manifest-read")
        }
        try validateClosedManifestShape(data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let manifest = try? decoder.decode(CheckpointManifest.self, from: data) else {
            throw ScenarioError.invalid("manifest-decode")
        }
        guard
            manifest.schema == "ai-survivors.terminal-render-checkpoints/v1",
            manifest.scenarioId == scenario.document.id,
            manifest.scenarioSha256 == scenario.sha256,
            manifest.viewport == scenario.document.viewport,
            !manifest.frames.isEmpty,
            manifest.expectedFinalOrdinal == UInt32(manifest.frames.count - 1)
        else {
            throw ScenarioError.invalid("manifest-header")
        }
        var names: [String] = []
        var mapping: [UInt32: [String]] = [:]
        var previousTick: UInt32 = 0
        for (index, frame) in manifest.frames.enumerated() {
            guard
                frame.streamOrdinal == UInt32(index),
                index == 0 || frame.tick > previousTick
            else {
                throw ScenarioError.invalid("manifest-frames")
            }
            previousTick = frame.tick
            names.append(contentsOf: frame.checkpointNames)
            mapping[frame.streamOrdinal] = frame.checkpointNames
        }
        guard names.sorted() == scenario.document.checkpoints.map(\.name).sorted() else {
            throw ScenarioError.invalid("manifest-checkpoints")
        }
        return (manifest, mapping)
    }

    private static func validate(_ value: ScenarioV1) throws {
        guard value.schema == "ai-survivors.terminal-render-scenario/v1" else {
            throw ScenarioError.invalid("schema")
        }
        guard isAsciiId(value.id) else {
            throw ScenarioError.invalid("id")
        }
        guard
            value.fixture.kind == "ai-survivors-special-characters",
            value.fixture.version == 1,
            (1...32).contains(value.fixture.stages.count)
        else {
            throw ScenarioError.invalid("fixture")
        }
        guard
            value.viewport == Viewport(cols: 100, rows: 20),
            value.simHz == 60,
            value.flushEvery == 2,
            (1...36_000).contains(value.ticks)
        else {
            throw ScenarioError.invalid("cadence")
        }
        guard
            (1...32).contains(value.checkpoints.count),
            (1...512).contains(value.portableAssertions.count),
            value.inputs.count <= 1_024
        else {
            throw ScenarioError.invalid("counts")
        }

        var stageNames = Set<String>()
        var previousCells: [FixtureCellV1]?
        for stage in value.fixture.stages {
            guard
                isAsciiId(stage.name),
                stageNames.insert(stage.name).inserted,
                !stage.cells.isEmpty,
                stage.cells.count <= 4_096,
                stage.cells != previousCells
            else {
                throw ScenarioError.invalid("stage")
            }
            previousCells = stage.cells
            var coordinates = Set<CellPoint>()
            for cell in stage.cells {
                let point = CellPoint(col: cell.col, row: cell.row)
                let visibleWidth = cell.symbol.unicodeScalars.reduce(0) {
                    $0 + max(0, UnicodeUtil.columnWidth(rune: $1))
                }
                guard
                    cell.col < value.viewport.cols,
                    cell.row < value.viewport.rows,
                    coordinates.insert(point).inserted,
                    !cell.symbol.isEmpty,
                    cell.symbol.utf8.count <= 64,
                    !cell.symbol.unicodeScalars.contains(where: {
                        $0.value == 0 || $0.value == 0x1b || $0.value == 0x0d || $0.value == 0x0a
                    }),
                    visibleWidth == 1,
                    cell.fg.count == 3,
                    cell.bg.count == 3
                else {
                    throw ScenarioError.invalid("cell")
                }
            }
        }

        var inputTick: UInt32?
        for input in value.inputs {
            guard
                input.tick < value.ticks,
                inputTick.map({ input.tick > $0 }) ?? true,
                input.keys.count == 1,
                input.keys[0] == "left" || input.keys[0] == "right"
            else {
                throw ScenarioError.invalid("input")
            }
            inputTick = input.tick
        }

        var checkpointNames = Set<String>()
        var checkpointTick: UInt32?
        for checkpoint in value.checkpoints {
            guard
                isAsciiId(checkpoint.name),
                checkpointNames.insert(checkpoint.name).inserted,
                (1...value.ticks).contains(checkpoint.tick),
                checkpointTick.map({ checkpoint.tick >= $0 }) ?? true
            else {
                throw ScenarioError.invalid("checkpoint")
            }
            checkpointTick = checkpoint.tick
        }

        var assertionNames = Set<String>()
        var corpusAssertionCount = 0
        let supported = Set([
            "cell_source_equals", "cell_width_equals", "region_nonblank",
            "glyph_count_equals", "glyph_resolved", "run_direction_equals",
            "source_order", "same_source_glyph_changed", "same_source_glyph_unchanged",
            "fallback_present", "font_differs_from_base", "primitive_kind_present",
            "tile_changed", "corpus_covered",
        ])
        for assertion in value.portableAssertions {
            if assertion.kind == "corpus_covered" {
                corpusAssertionCount += 1
            }
            guard
                supported.contains(assertion.kind),
                isAsciiId(assertion.name),
                assertionNames.insert(assertion.name).inserted,
                validateAssertion(
                    assertion,
                    checkpoints: checkpointNames,
                    viewport: value.viewport
                )
            else {
                throw ScenarioError.invalid("assertion")
            }
        }
        guard corpusAssertionCount == 1 else {
            throw ScenarioError.invalid("corpus-assertion")
        }

        let limits = value.limits
        let minimumRetained = value.checkpoints.count + 1
            + Int(limits.failureContextBefore) + Int(limits.failureContextAfter)
        guard
            (1...18_000).contains(limits.observedFrames),
            (UInt32(minimumRetained)...39).contains(limits.retainedFrames),
            (1...3_600).contains(limits.completeFrames),
            limits.failureContextBefore <= 3,
            limits.failureContextAfter <= 3,
            (1...4_096).contains(limits.glyphAtlasEntries),
            (1...4_096).contains(limits.cellTileAtlasEntries),
            (1...33_554_432).contains(limits.canonicalJsonBytes),
            (1...67_108_864).contains(limits.rawWireBytes),
            (1...30_000).contains(limits.childTimeoutMs)
        else {
            throw ScenarioError.invalid("limits")
        }
    }

    private static func validateAssertion(
        _ assertion: PortableAssertion,
        checkpoints: Set<String>,
        viewport: Viewport
    ) -> Bool {
        let checkpoint = assertion.checkpoint.map(checkpoints.contains) ?? false
        let cell = assertion.cell.map { $0.col < viewport.cols && $0.row < viewport.rows } ?? false
        let region = assertion.region.map {
            $0.cols > 0 && $0.rows > 0
                && UInt32($0.col) + UInt32($0.cols) <= UInt32(viewport.cols)
                && UInt32($0.row) + UInt32($0.rows) <= UInt32(viewport.rows)
        } ?? false
        let area = assertion.region.map { UInt32($0.cols) * UInt32($0.rows) } ?? 0
        let distinctCheckpoints = assertion.fromCheckpoint != assertion.toCheckpoint
            && (assertion.fromCheckpoint.map(checkpoints.contains) ?? false)
            && (assertion.toCheckpoint.map(checkpoints.contains) ?? false)
        switch assertion.kind {
        case "cell_source_equals":
            guard case let .string(expected)? = assertion.expected else { return false }
            return checkpoint && cell && !expected.isEmpty
        case "cell_width_equals":
            guard case let .integer(expected)? = assertion.expected else { return false }
            return checkpoint && cell && (expected == 1 || expected == 2)
        case "region_nonblank":
            return checkpoint && region
                && (assertion.minimumOccupiedCells ?? 0) > 0
                && (assertion.minimumOccupiedCells ?? 0) <= area
        case "glyph_count_equals":
            guard case let .integer(expected)? = assertion.expected else { return false }
            return checkpoint && region && expected > 0 && UInt32(expected) <= area
        case "glyph_resolved":
            return checkpoint && region
        case "run_direction_equals":
            guard case let .string(expected)? = assertion.expected else { return false }
            return checkpoint && region && !(assertion.source ?? "").isEmpty
                && (expected == "left_to_right" || expected == "right_to_left")
        case "source_order":
            let sources = assertion.sources ?? []
            return checkpoint && region && !sources.isEmpty
                && Set(sources).count == sources.count
                && sources.allSatisfy { !$0.isEmpty }
                && (
                    assertion.visualColumns == "strictly_increasing"
                        || assertion.visualColumns == "strictly_decreasing"
                )
        case "same_source_glyph_changed", "same_source_glyph_unchanged":
            return distinctCheckpoints && cell && !(assertion.source ?? "").isEmpty
        case "fallback_present":
            let count = assertion.minimumDraws ?? 0
            return checkpoint && region && count > 0 && count <= area
        case "font_differs_from_base":
            return checkpoint && region && !(assertion.source ?? "").isEmpty
        case "primitive_kind_present":
            let count = assertion.minimumCount ?? 0
            return checkpoint && region
                && (assertion.primitiveKind == "block" || assertion.primitiveKind == "box")
                && count > 0 && count <= area
        case "tile_changed":
            return distinctCheckpoints && cell
        case "corpus_covered":
            let named = assertion.checkpoints ?? []
            let sources = assertion.expectedSources ?? []
            return !named.isEmpty && Set(named).count == named.count
                && named.allSatisfy(checkpoints.contains)
                && !sources.isEmpty && sources.count <= 256
                && Set(sources).count == sources.count
                && sources.allSatisfy { !$0.isEmpty }
        default:
            return false
        }
    }

    static func isAsciiId(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count) else {
            return false
        }
        return value.range(
            of: "^[a-z][a-z0-9-]{0,63}$",
            options: .regularExpression
        ) != nil
    }

    private static func validateClosedScenarioShape(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScenarioError.decode
        }
        try exactKeys(
            root,
            [
                "schema", "id", "fixture", "seed", "viewport", "sim_hz",
                "flush_every", "ticks", "inputs", "checkpoints",
                "portable_assertions", "limits",
            ],
            "root"
        )
        guard
            let fixture = root["fixture"] as? [String: Any],
            let stages = fixture["stages"] as? [[String: Any]],
            let viewport = root["viewport"] as? [String: Any],
            let inputs = root["inputs"] as? [[String: Any]],
            let checkpoints = root["checkpoints"] as? [[String: Any]],
            let assertions = root["portable_assertions"] as? [[String: Any]],
            let limits = root["limits"] as? [String: Any]
        else {
            throw ScenarioError.decode
        }
        try exactKeys(fixture, ["kind", "version", "stages"], "fixture")
        try exactKeys(viewport, ["cols", "rows"], "viewport")
        try exactKeys(
            limits,
            [
                "observed_frames", "retained_frames", "complete_frames",
                "failure_context_before", "failure_context_after",
                "glyph_atlas_entries", "cell_tile_atlas_entries",
                "canonical_json_bytes", "raw_wire_bytes", "child_timeout_ms",
            ],
            "limits"
        )
        for stage in stages {
            try exactKeys(stage, ["name", "cells"], "stage")
            guard let cells = stage["cells"] as? [[String: Any]] else {
                throw ScenarioError.decode
            }
            for cell in cells {
                try exactKeys(cell, ["col", "row", "symbol", "fg", "bg"], "cell")
            }
        }
        for input in inputs {
            try exactKeys(input, ["tick", "keys"], "input")
        }
        for checkpoint in checkpoints {
            try exactKeys(checkpoint, ["name", "tick"], "checkpoint")
        }
        for assertion in assertions {
            guard let kind = assertion["kind"] as? String else {
                throw ScenarioError.decode
            }
            let common = Set(["kind", "name"])
            let variant: Set<String>
            switch kind {
            case "cell_source_equals", "cell_width_equals":
                variant = ["checkpoint", "cell", "expected"]
            case "region_nonblank":
                variant = ["checkpoint", "region", "minimum_occupied_cells"]
            case "glyph_count_equals":
                variant = ["checkpoint", "region", "expected"]
            case "glyph_resolved":
                variant = ["checkpoint", "region"]
            case "run_direction_equals":
                variant = ["checkpoint", "region", "source", "expected"]
            case "source_order":
                variant = ["checkpoint", "region", "sources", "visual_columns"]
            case "same_source_glyph_changed", "same_source_glyph_unchanged":
                variant = ["from_checkpoint", "to_checkpoint", "cell", "source"]
            case "fallback_present":
                variant = ["checkpoint", "region", "minimum_draws"]
            case "font_differs_from_base":
                variant = ["checkpoint", "region", "source"]
            case "primitive_kind_present":
                variant = ["checkpoint", "region", "primitive_kind", "minimum_count"]
            case "tile_changed":
                variant = ["from_checkpoint", "to_checkpoint", "cell"]
            case "corpus_covered":
                variant = ["checkpoints", "expected_sources"]
            default:
                throw ScenarioError.invalid("assertion-kind")
            }
            try exactKeys(assertion, common.union(variant), "assertion")
            if let cell = assertion["cell"] as? [String: Any] {
                try exactKeys(cell, ["col", "row"], "assertion-cell")
            }
            if let region = assertion["region"] as? [String: Any] {
                try exactKeys(region, ["col", "row", "cols", "rows"], "assertion-region")
            }
        }
    }

    private static func validateClosedManifestShape(_ data: Data) throws {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let viewport = root["viewport"] as? [String: Any],
            let frames = root["frames"] as? [[String: Any]]
        else {
            throw ScenarioError.invalid("manifest-decode")
        }
        try exactKeys(
            root,
            [
                "schema", "scenario_id", "scenario_sha256", "viewport",
                "frames", "expected_final_ordinal",
            ],
            "manifest"
        )
        try exactKeys(viewport, ["cols", "rows"], "manifest-viewport")
        for frame in frames {
            try exactKeys(
                frame,
                ["stream_ordinal", "tick", "checkpoint_names"],
                "manifest-frame"
            )
        }
    }

    private static func exactKeys(
        _ object: [String: Any],
        _ expected: Set<String>,
        _ field: String
    ) throws {
        guard Set(object.keys) == expected else {
            throw ScenarioError.invalid("\(field)-keys")
        }
    }
}

extension Digest {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
