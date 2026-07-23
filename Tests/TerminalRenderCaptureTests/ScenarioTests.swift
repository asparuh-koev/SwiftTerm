import Foundation

private func point() -> [String: Any] {
    ["col": 1, "row": 1]
}

private func region() -> [String: Any] {
    ["col": 1, "row": 1, "cols": 1, "rows": 1]
}

private func scenarioDocument() -> [String: Any] {
    let assertions: [[String: Any]] = [
        [
            "kind": "cell_source_equals", "name": "source",
            "checkpoint": "first", "cell": point(), "expected": "א",
        ],
        [
            "kind": "cell_width_equals", "name": "width",
            "checkpoint": "first", "cell": point(), "expected": 1,
        ],
        [
            "kind": "region_nonblank", "name": "nonblank",
            "checkpoint": "first", "region": region(), "minimum_occupied_cells": 1,
        ],
        [
            "kind": "glyph_count_equals", "name": "glyph-count",
            "checkpoint": "first", "region": region(), "expected": 1,
        ],
        [
            "kind": "glyph_resolved", "name": "resolved",
            "checkpoint": "first", "region": region(),
        ],
        [
            "kind": "run_direction_equals", "name": "direction",
            "checkpoint": "first", "region": region(), "source": "א",
            "expected": "right_to_left",
        ],
        [
            "kind": "source_order", "name": "order",
            "checkpoint": "first", "region": region(), "sources": ["א"],
            "visual_columns": "strictly_decreasing",
        ],
        [
            "kind": "same_source_glyph_changed", "name": "changed",
            "from_checkpoint": "first", "to_checkpoint": "second",
            "cell": point(), "source": "א",
        ],
        [
            "kind": "same_source_glyph_unchanged", "name": "unchanged",
            "from_checkpoint": "first", "to_checkpoint": "second",
            "cell": point(), "source": "א",
        ],
        [
            "kind": "fallback_present", "name": "fallback",
            "checkpoint": "first", "region": region(), "minimum_draws": 1,
        ],
        [
            "kind": "font_differs_from_base", "name": "font",
            "checkpoint": "first", "region": region(), "source": "א",
        ],
        [
            "kind": "primitive_kind_present", "name": "primitive",
            "checkpoint": "first", "region": region(),
            "primitive_kind": "block", "minimum_count": 1,
        ],
        [
            "kind": "tile_changed", "name": "tile",
            "from_checkpoint": "first", "to_checkpoint": "second", "cell": point(),
        ],
        [
            "kind": "corpus_covered", "name": "corpus",
            "checkpoints": ["first"], "expected_sources": ["א"],
        ],
    ]
    return [
        "schema": "ai-survivors.terminal-render-scenario/v1",
        "id": "validator-fixture",
        "fixture": [
            "kind": "ai-survivors-special-characters",
            "version": 1,
            "stages": [[
                "name": "only",
                "cells": [[
                    "col": 1, "row": 1, "symbol": "א",
                    "fg": [255, 255, 255], "bg": [0, 0, 0],
                ]],
            ]],
        ],
        "seed": 1,
        "viewport": ["cols": 100, "rows": 20],
        "sim_hz": 60,
        "flush_every": 2,
        "ticks": 4,
        "inputs": [],
        "checkpoints": [
            ["name": "first", "tick": 2],
            ["name": "second", "tick": 4],
        ],
        "portable_assertions": assertions,
        "limits": [
            "observed_frames": 10,
            "retained_frames": 3,
            "complete_frames": 10,
            "failure_context_before": 0,
            "failure_context_after": 0,
            "glyph_atlas_entries": 100,
            "cell_tile_atlas_entries": 100,
            "canonical_json_bytes": 1_000_000,
            "raw_wire_bytes": 1_000_000,
            "child_timeout_ms": 1_000,
        ],
    ]
}

private func writeScenario(_ value: [String: Any], _ url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try data.write(to: url, options: .atomic)
}

func runScenarioTests() throws {
    let root = URL(fileURLWithPath: ".build/test-scenario-validation", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("scenario.json")
    try writeScenario(scenarioDocument(), url)
    let loaded = try ScenarioLoader.load(url)
    try captureRequire(
        loaded.document.fixture.stages.count == 1,
        "fixture-owned stage nesting was not accepted"
    )

    var unknown = scenarioDocument()
    var fixture = unknown["fixture"] as! [String: Any]
    fixture["unexpected"] = true
    unknown["fixture"] = fixture
    try writeScenario(unknown, url)
    do {
        _ = try ScenarioLoader.load(url)
        throw CaptureTestFailure.assertion("unknown fixture field was accepted")
    } catch is ScenarioError {
    }

    let mutations: [(inout [String: Any]) -> Void] = [
        { $0["expected"] = "" },
        { $0["expected"] = 3 },
        { $0["minimum_occupied_cells"] = 0 },
        { $0["expected"] = 2 },
        { $0["checkpoint"] = "missing" },
        { $0["expected"] = "sideways" },
        { $0["sources"] = ["א", "א"] },
        { $0["to_checkpoint"] = "first" },
        { $0["source"] = "" },
        { $0["minimum_draws"] = 0 },
        { $0["source"] = "" },
        { $0["primitive_kind"] = "triangle" },
        { $0["to_checkpoint"] = "first" },
        { $0["checkpoints"] = ["first", "first"] },
    ]
    for (index, mutate) in mutations.enumerated() {
        var value = scenarioDocument()
        var assertions = value["portable_assertions"] as! [[String: Any]]
        mutate(&assertions[index])
        value["portable_assertions"] = assertions
        try writeScenario(value, url)
        do {
            _ = try ScenarioLoader.load(url)
            throw CaptureTestFailure.assertion(
                "invalid assertion variant \(index) was accepted"
            )
        } catch is ScenarioError {
        }
    }
}
