import Foundation

private struct ReconstructedFrame {
    let frame: Frame
    let rows: [[CellRef]]
}

enum PortableAssertions {
    static func evaluate(
        scenario: ValidatedScenario,
        frames: [Frame],
        glyphAtlas: [GlyphAtlasEntry]
    ) -> [PortableAssertionResult] {
        let reconstructed = reconstruct(frames)
        var byCheckpoint: [String: ReconstructedFrame] = [:]
        for value in reconstructed {
            for checkpoint in value.frame.checkpoints {
                byCheckpoint[checkpoint] = value
            }
        }
        return scenario.document.portableAssertions.map { assertion in
            do {
                try evaluateOne(
                    assertion,
                    byCheckpoint: byCheckpoint,
                    glyphAtlas: glyphAtlas
                )
                return PortableAssertionResult(
                    name: assertion.name,
                    kind: assertion.kind,
                    passed: true,
                    detail: nil
                )
            } catch {
                return PortableAssertionResult(
                    name: assertion.name,
                    kind: assertion.kind,
                    passed: false,
                    detail: "portable assertion did not match captured evidence"
                )
            }
        }
    }

    private static func reconstruct(_ frames: [Frame]) -> [ReconstructedFrame] {
        var current: [[CellRef]]?
        var result: [ReconstructedFrame] = []
        for frame in frames {
            if let baseRows = frame.baseRows {
                current = baseRows
            } else if var rows = current {
                for change in frame.changes {
                    rows[Int(change.row)][Int(change.col)] = change.cell
                }
                current = rows
            }
            if let current {
                result.append(ReconstructedFrame(frame: frame, rows: current))
            }
        }
        return result
    }

    private static func evaluateOne(
        _ assertion: PortableAssertion,
        byCheckpoint: [String: ReconstructedFrame],
        glyphAtlas: [GlyphAtlasEntry]
    ) throws {
        switch assertion.kind {
        case "cell_source_equals":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let cell = try cell(assertion.cell, value)
            guard case let .string(expected)? = assertion.expected, cell.sourceText == expected else {
                throw AssertionFailure.mismatch
            }
        case "cell_width_equals":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let cell = try cell(assertion.cell, value)
            guard case let .integer(expected)? = assertion.expected, Int(cell.width) == expected else {
                throw AssertionFailure.mismatch
            }
        case "region_nonblank":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let cells = try cells(assertion.region, value)
            let occupiedCount = cells.filter { occupied($0.cell) }.count
            guard occupiedCount >= Int(assertion.minimumOccupiedCells ?? 0) else {
                throw AssertionFailure.mismatch
            }
        case "glyph_count_equals":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let ids = Set(try cells(assertion.region, value).flatMap(\.cell.glyphDrawIds))
            guard case let .integer(expected)? = assertion.expected, ids.count == expected else {
                throw AssertionFailure.mismatch
            }
        case "glyph_resolved":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            for item in try cells(assertion.region, value) where occupied(item.cell)
                && item.cell.primitiveDrawIds.isEmpty
            {
                guard !item.cell.glyphDrawIds.isEmpty else {
                    throw AssertionFailure.mismatch
                }
                let glyphs = glyphCalls(item.cell.glyphDrawIds, value.frame)
                guard glyphs.allSatisfy({ glyph in
                    glyph.glyphID != 0 && glyphAtlas.contains(where: { entry in
                        entry.fontFileSha256 == glyph.fontFileSHA256
                            && entry.glyphId == glyph.glyphID
                            && !entry.alphaMaskPackbitsBase64.isEmpty
                    })
                }) else {
                    throw AssertionFailure.mismatch
                }
            }
        case "run_direction_equals":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let selected = try selectedGlyphs(assertion, value)
            let expected = assertion.expected == .string("right_to_left")
            guard !selected.isEmpty, selected.allSatisfy({ $0.rightToLeft == expected }) else {
                throw AssertionFailure.mismatch
            }
        case "source_order":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let sources = assertion.sources ?? []
            let columns = try sources.map { source -> Int in
                let matches = glyphs(in: try cells(assertion.region, value), frame: value.frame)
                    .filter { sourceString($0).contains(source) }
                guard matches.count == 1 else {
                    throw AssertionFailure.mismatch
                }
                return matches[0].slotColumn
            }
            let pairs = zip(columns, columns.dropFirst())
            let valid = assertion.visualColumns == "strictly_increasing"
                ? pairs.allSatisfy { $0.0 < $0.1 }
                : pairs.allSatisfy { $0.0 > $0.1 }
            guard valid else {
                throw AssertionFailure.mismatch
            }
        case "same_source_glyph_changed", "same_source_glyph_unchanged":
            let from = try frame(assertion.fromCheckpoint, byCheckpoint)
            let to = try frame(assertion.toCheckpoint, byCheckpoint)
            let fromCell = try cell(assertion.cell, from)
            let toCell = try cell(assertion.cell, to)
            guard
                fromCell.sourceText == assertion.source,
                toCell.sourceText == assertion.source
            else {
                throw AssertionFailure.mismatch
            }
            let before = glyphIdentity(fromCell, from.frame)
            let after = glyphIdentity(toCell, to.frame)
            let changed = before != after
            guard changed == (assertion.kind == "same_source_glyph_changed") else {
                throw AssertionFailure.mismatch
            }
        case "fallback_present":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let count = glyphs(in: try cells(assertion.region, value), frame: value.frame)
                .filter { $0.fontPostScriptName != "Menlo-Regular" }
                .count
            guard count >= Int(assertion.minimumDraws ?? 0) else {
                throw AssertionFailure.mismatch
            }
        case "font_differs_from_base":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let selected = try selectedGlyphs(assertion, value)
            guard
                !selected.isEmpty,
                selected.allSatisfy({ $0.fontPostScriptName != "Menlo-Regular" })
            else {
                throw AssertionFailure.mismatch
            }
        case "primitive_kind_present":
            let value = try frame(assertion.checkpoint, byCheckpoint)
            let ids = Set(try cells(assertion.region, value).flatMap(\.cell.primitiveDrawIds))
            let count = ids.compactMap { id in
                value.frame.drawCalls.first { $0.id == id }
            }.filter { draw in
                guard case let .primitive(_, primitive) = draw else {
                    return false
                }
                switch primitive {
                case .block:
                    return assertion.primitiveKind == "block"
                case .boxDrawing:
                    return assertion.primitiveKind == "box"
                }
            }.count
            guard count >= Int(assertion.minimumCount ?? 0) else {
                throw AssertionFailure.mismatch
            }
        case "tile_changed":
            let from = try frame(assertion.fromCheckpoint, byCheckpoint)
            let to = try frame(assertion.toCheckpoint, byCheckpoint)
            guard try cell(assertion.cell, from).tileId != cell(assertion.cell, to).tileId else {
                throw AssertionFailure.mismatch
            }
        case "corpus_covered":
            let checkpoints = assertion.checkpoints ?? []
            let sources = assertion.expectedSources ?? []
            for source in sources {
                let found = checkpoints.compactMap { byCheckpoint[$0] }.contains { value in
                    value.rows.flatMap { $0 }.contains {
                        $0.sourceText.contains(source)
                            && (!$0.glyphDrawIds.isEmpty || !$0.primitiveDrawIds.isEmpty)
                    }
                }
                guard found else {
                    throw AssertionFailure.mismatch
                }
            }
        default:
            throw AssertionFailure.mismatch
        }
    }

    private enum AssertionFailure: Error {
        case mismatch
    }

    private static func frame(
        _ name: String?,
        _ values: [String: ReconstructedFrame]
    ) throws -> ReconstructedFrame {
        guard let name, let value = values[name] else {
            throw AssertionFailure.mismatch
        }
        return value
    }

    private static func cell(
        _ point: CellPoint?,
        _ frame: ReconstructedFrame
    ) throws -> CellRef {
        guard
            let point,
            Int(point.row) < frame.rows.count,
            Int(point.col) < frame.rows[Int(point.row)].count
        else {
            throw AssertionFailure.mismatch
        }
        return frame.rows[Int(point.row)][Int(point.col)]
    }

    private static func cells(
        _ region: CellRegion?,
        _ frame: ReconstructedFrame
    ) throws -> [(point: CellPoint, cell: CellRef)] {
        guard let region, region.cols > 0, region.rows > 0 else {
            throw AssertionFailure.mismatch
        }
        var result: [(CellPoint, CellRef)] = []
        for row in region.row..<(region.row + region.rows) {
            for col in region.col..<(region.col + region.cols) {
                let point = CellPoint(col: col, row: row)
                result.append((point, try cell(point, frame)))
            }
        }
        return result
    }

    private static func occupied(_ cell: CellRef) -> Bool {
        let visible = cell.sourceText.unicodeScalars.contains {
            !$0.properties.isWhitespace && $0.properties.generalCategory != .format
        }
        return visible || !cell.glyphDrawIds.isEmpty || !cell.primitiveDrawIds.isEmpty
    }

    private static func glyphCalls(_ ids: [UInt32], _ frame: Frame) -> [RenderedGlyph] {
        ids.compactMap { id in
            guard
                let draw = frame.drawCalls.first(where: { $0.id == id }),
                case let .glyph(_, value) = draw
            else {
                return nil
            }
            return value
        }
    }

    private static func glyphs(
        in cells: [(point: CellPoint, cell: CellRef)],
        frame: Frame
    ) -> [RenderedGlyph] {
        glyphCalls(Array(Set(cells.flatMap(\.cell.glyphDrawIds))).sorted(), frame)
    }

    private static func selectedGlyphs(
        _ assertion: PortableAssertion,
        _ value: ReconstructedFrame
    ) throws -> [RenderedGlyph] {
        let source = assertion.source ?? ""
        return glyphs(in: try cells(assertion.region, value), frame: value.frame)
            .filter { sourceString($0).contains(source) }
    }

    private static func sourceString(_ glyph: RenderedGlyph) -> String {
        String(
            String.UnicodeScalarView(
                glyph.sourceScalars.compactMap(UnicodeScalar.init)
            )
        )
    }

    private static func glyphIdentity(_ cell: CellRef, _ frame: Frame) -> [String] {
        glyphCalls(cell.glyphDrawIds, frame)
            .map { "\($0.fontFileSHA256):\($0.glyphID)" }
            .sorted()
    }
}
