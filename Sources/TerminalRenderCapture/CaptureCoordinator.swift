import AppKit
import Foundation

private enum ObservedDraw {
    case glyph(RenderedGlyph)
    case primitive(RenderedPrimitive)
}

private struct FrameTransaction {
    let info: RenderFrameInfo
    var draws: [ObservedDraw]
    var ended: Bool
}

final class CaptureCoordinator: TerminalRenderObserver {
    private let scenario: ValidatedScenario?
    private let manifest: CheckpointManifest?
    private let checkpointNames: [UInt32: [String]]
    private let limits: ActiveLimits
    private let retainComplete: Bool

    private var transaction: FrameTransaction?
    private var retainedRows: [[CellRef]]?
    private let glyphAtlasBuilder = GlyphAtlasBuilder()
    private let tileAtlasBuilder = CellTileAtlasBuilder()
    private(set) var frames: [Frame] = []
    private(set) var observedFrameCount: UInt32 = 0
    private(set) var failure: FailureReason?
    private(set) var truncation: CaptureLimit?
    private(set) var lastFrameInfo: RenderFrameInfo?
    private(set) var lastAuthoritativePixels: OffscreenFramePixels?

    init(
        scenario: ValidatedScenario?,
        manifest: CheckpointManifest?,
        checkpointNames: [UInt32: [String]],
        limits: ActiveLimits,
        retainComplete: Bool
    ) {
        self.scenario = scenario
        self.manifest = manifest
        self.checkpointNames = checkpointNames
        self.limits = limits
        self.retainComplete = retainComplete
    }

    func terminalView(
        _ source: TerminalView,
        synchronizedOutputEnded reason: SynchronizedOutputEndReason
    ) {
        guard failure == nil, truncation == nil else {
            return
        }
        guard Thread.isMainThread else {
            fail(code: "observer_reentrancy", detail: "observer callback was not on the main queue")
            return
        }
        guard reason == .explicitReset else {
            let code = reason == .timeout
                ? "synchronized_timeout"
                : "synchronized_terminal_reset"
            fail(code: code, detail: "synchronized output ended without explicit DEC reset")
            return
        }
        guard observedFrameCount < limits.observedFrames else {
            truncate(.observedFrames)
            return
        }
        let ordinal = observedFrameCount
        let terminal = source.getTerminal()
        let expected = scenario?.document.viewport
        if let expected,
           terminal.cols != Int(expected.cols) || terminal.rows != Int(expected.rows)
        {
            fail(code: "dimension_mismatch", detail: "terminal dimensions differ from scenario")
            return
        }
        guard transaction == nil else {
            fail(code: "observer_reentrancy", detail: "nested frame observation")
            return
        }

        do {
            let pixels = try OffscreenRenderer.render(view: source)
            guard let completed = transaction, completed.ended else {
                fail(code: "draw_failed", detail: "forced draw did not complete")
                transaction = nil
                return
            }
            transaction = nil
            observedFrameCount += 1
            lastFrameInfo = completed.info
            lastAuthoritativePixels = pixels
            if shouldRetain(ordinal: ordinal) {
                try commit(
                    ordinal: ordinal,
                    terminal: terminal,
                    transaction: completed,
                    pixels: pixels
                )
            }
        } catch {
            transaction = nil
            fail(code: "draw_failed", detail: "offscreen draw failed")
        }
    }

    func terminalView(_ source: TerminalView, beginFrame frame: RenderFrameInfo) {
        guard failure == nil, truncation == nil else {
            return
        }
        guard transaction == nil else {
            fail(code: "observer_reentrancy", detail: "beginFrame was nested")
            return
        }
        transaction = FrameTransaction(info: frame, draws: [], ended: false)
    }

    func terminalView(_ source: TerminalView, drewGlyph glyph: RenderedGlyph) {
        guard transaction != nil else {
            fail(code: "observer_reentrancy", detail: "glyph callback outside a frame")
            return
        }
        transaction?.draws.append(.glyph(glyph))
    }

    func terminalView(_ source: TerminalView, drewPrimitive primitive: RenderedPrimitive) {
        guard transaction != nil else {
            fail(code: "observer_reentrancy", detail: "primitive callback outside a frame")
            return
        }
        transaction?.draws.append(.primitive(primitive))
    }

    func terminalView(_ source: TerminalView, endFrame frame: RenderFrameInfo) {
        guard var active = transaction, active.info == frame, !active.ended else {
            fail(code: "observer_reentrancy", detail: "endFrame did not match beginFrame")
            return
        }
        active.ended = true
        transaction = active
    }

    func finish(terminal: Terminal) {
        if failure != nil || truncation != nil {
            return
        }
        if terminal.synchronizedOutputActive {
            fail(code: "synchronized_eof", detail: "stream ended inside synchronized output")
            return
        }
        guard observedFrameCount > 0 else {
            fail(code: "no_synchronized_frame", detail: "stream contained no explicit synchronized frame")
            return
        }
        if let manifest, observedFrameCount != UInt32(manifest.frames.count) {
            fail(code: "frame_sequence_mismatch", detail: "observed frame count differs from manifest")
        }
    }

    func operationalFailure(code: String, detail: String) {
        fail(code: code, detail: detail)
    }

    func resourceLimit(_ limit: CaptureLimit) {
        truncate(limit)
    }

    func glyphAtlas() -> [GlyphAtlasEntry] {
        glyphAtlasBuilder.entries
    }

    func cellTileAtlas() -> [CellTileAtlasEntry] {
        tileAtlasBuilder.entries
    }

    private func shouldRetain(ordinal: UInt32) -> Bool {
        if retainComplete {
            return ordinal < limits.completeFrames
        }
        guard let manifest else {
            return true
        }
        return !(checkpointNames[ordinal] ?? []).isEmpty
            || ordinal == manifest.expectedFinalOrdinal
    }

    private func commit(
        ordinal: UInt32,
        terminal: Terminal,
        transaction: FrameTransaction,
        pixels: OffscreenFramePixels
    ) throws {
        let directLastFrame = manifest == nil && !retainComplete
        if directLastFrame {
            frames.removeAll(keepingCapacity: true)
            retainedRows = nil
        }
        if retainComplete && frames.count >= Int(limits.completeFrames) {
            truncate(.completeFrames)
            return
        }
        if !retainComplete && frames.count >= Int(limits.retainedFrames) {
            truncate(.completeFrames)
            return
        }

        var drawCalls: [DrawCall] = []
        var glyphIds: [CellPoint: [UInt32]] = [:]
        var primitiveIds: [CellPoint: [UInt32]] = [:]
        for draw in transaction.draws {
            switch draw {
            case let .glyph(glyph):
                let source = String(
                    String.UnicodeScalarView(
                        glyph.sourceScalars.compactMap(UnicodeScalar.init)
                    )
                )
                guard source.contains(where: { !$0.isWhitespace }) else {
                    continue
                }
                let id = UInt32(drawCalls.count)
                guard glyphAtlasBuilder.insert(glyph) != nil else {
                    fail(code: "draw_failed", detail: "glyph rasterization failed")
                    return
                }
                drawCalls.append(.glyph(id: id, value: glyph))
                for column in glyph.slotColumn..<(glyph.slotColumn + glyph.slotWidth)
                where column >= 0 && column < terminal.cols
                    && glyph.row >= 0 && glyph.row < terminal.rows
                {
                    glyphIds[
                        CellPoint(col: UInt16(column), row: UInt16(glyph.row)),
                        default: []
                    ].append(id)
                }
            case let .primitive(primitive):
                let id = UInt32(drawCalls.count)
                drawCalls.append(.primitive(id: id, value: primitive))
                let row: Int
                let column: Int
                let width: Int
                switch primitive {
                case let .block(value):
                    row = value.row
                    column = value.column
                    width = value.columnWidth
                case let .boxDrawing(value):
                    row = value.row
                    column = value.column
                    width = value.columnWidth
                }
                for target in column..<(column + width)
                where target >= 0 && target < terminal.cols && row >= 0 && row < terminal.rows
                {
                    primitiveIds[
                        CellPoint(col: UInt16(target), row: UInt16(row)),
                        default: []
                    ].append(id)
                }
            }
        }
        if glyphAtlasBuilder.entries.count > Int(limits.glyphAtlasEntries) {
            truncate(.glyphAtlasEntries)
            return
        }

        let cellWidth = Int(
            (transaction.info.cellSizePoints.width * transaction.info.backingScale).rounded()
        )
        let cellHeight = Int(
            (transaction.info.cellSizePoints.height * transaction.info.backingScale).rounded()
        )
        var rows: [[CellRef]] = []
        for row in 0..<terminal.rows {
            var cells: [CellRef] = []
            for column in 0..<terminal.cols {
                let point = CellPoint(col: UInt16(column), row: UInt16(row))
                let data = terminal.getCharData(col: column, row: row)
                let width = UInt8(max(0, Int(data?.width ?? 1)))
                let text: String
                if let data, data.width != 0 {
                    text = terminal.getRenderString(for: data).replacingOccurrences(of: "\0", with: "")
                } else {
                    text = ""
                }
                let tile = pixels.cellRGBA(
                    column: column,
                    row: row,
                    frame: transaction.info
                ) ?? Data(repeating: 0, count: cellWidth * cellHeight * 4)
                let tileID = tileAtlasBuilder.insert(bytes: tile, width: cellWidth, height: cellHeight)
                let (foreground, background) = colors(data?.attribute ?? .empty)
                cells.append(
                    CellRef(
                        sourceText: text,
                        width: width,
                        continuationOf: width == 0 && column > 0
                            ? CellPoint(col: UInt16(column - 1), row: UInt16(row))
                            : nil,
                        glyphDrawIds: Array(Set(glyphIds[point] ?? [])).sorted(),
                        primitiveDrawIds: Array(Set(primitiveIds[point] ?? [])).sorted(),
                        tileId: tileID,
                        foregroundRgba: foreground,
                        backgroundRgba: background
                    )
                )
            }
            rows.append(cells)
        }
        if tileAtlasBuilder.entries.count > Int(limits.cellTileAtlasEntries) {
            truncate(.cellTileAtlasEntries)
            return
        }

        let baseRows: [[CellRef]]?
        var changes: [CellChange] = []
        if let previous = retainedRows {
            baseRows = nil
            for row in 0..<rows.count {
                for column in 0..<rows[row].count where rows[row][column] != previous[row][column] {
                    changes.append(
                        CellChange(
                            col: UInt16(column),
                            row: UInt16(row),
                            cell: rows[row][column]
                        )
                    )
                }
            }
        } else {
            baseRows = rows
        }
        retainedRows = rows
        frames.append(
            Frame(
                streamOrdinal: ordinal,
                checkpoints: checkpointNames[ordinal] ?? [],
                dimensions: Dimensions(cols: UInt16(terminal.cols), rows: UInt16(terminal.rows)),
                baseRows: baseRows,
                changes: changes,
                drawCalls: drawCalls,
                framebufferRgbaSha256: pixels.rgba.sha256Hex
            )
        )
    }

    private func colors(_ attribute: Attribute) -> (RenderRGBA, RenderRGBA) {
        var foreground = rgba(attribute.fg, fallback: (1, 1, 1))
        var background = rgba(attribute.bg, fallback: (0, 0, 0))
        if attribute.style.contains(.inverse) {
            swap(&foreground, &background)
        }
        return (foreground, background)
    }

    private func rgba(
        _ color: Attribute.Color,
        fallback: (Double, Double, Double)
    ) -> RenderRGBA {
        switch color {
        case let .trueColor(red, green, blue):
            return RenderRGBA(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255,
                alpha: 1
            )
        case let .ansi256(code):
            let value = Double(code) / 255
            return RenderRGBA(red: value, green: value, blue: value, alpha: 1)
        case .defaultColor, .defaultInvertedColor:
            return RenderRGBA(
                red: fallback.0,
                green: fallback.1,
                blue: fallback.2,
                alpha: 1
            )
        }
    }

    private func fail(code: String, detail: String) {
        if failure == nil && truncation == nil {
            failure = FailureReason(code: code, detail: detail, limit: nil)
        }
    }

    private func truncate(_ limit: CaptureLimit) {
        if failure == nil && truncation == nil {
            truncation = limit
        }
    }
}
