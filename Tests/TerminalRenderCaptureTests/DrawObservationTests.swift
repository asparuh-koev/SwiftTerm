import AppKit
import Foundation

private struct ObservedFrame: Equatable {
    let glyphs: [RenderedGlyph]
    let primitives: [RenderedPrimitive]
}

private final class DrawObserver: TerminalRenderObserver {
    private(set) var frames: [ObservedFrame] = []
    private var glyphs: [RenderedGlyph] = []
    private var primitives: [RenderedPrimitive] = []
    private var drawing = false

    func terminalView(
        _ source: TerminalView,
        synchronizedOutputEnded reason: SynchronizedOutputEndReason
    ) {
        guard reason == .explicitReset else {
            return
        }
        _ = try? OffscreenRenderer.render(view: source)
    }

    func terminalView(_ source: TerminalView, beginFrame frame: RenderFrameInfo) {
        precondition(!drawing)
        drawing = true
        glyphs = []
        primitives = []
    }

    func terminalView(_ source: TerminalView, drewGlyph glyph: RenderedGlyph) {
        precondition(drawing)
        glyphs.append(glyph)
    }

    func terminalView(_ source: TerminalView, drewPrimitive primitive: RenderedPrimitive) {
        precondition(drawing)
        primitives.append(primitive)
    }

    func terminalView(_ source: TerminalView, endFrame frame: RenderFrameInfo) {
        precondition(drawing)
        drawing = false
        frames.append(ObservedFrame(glyphs: glyphs, primitives: primitives))
    }
}

private func makeObservedView() throws -> (TerminalView, DrawObserver) {
    guard let font = NSFont(name: "Menlo-Regular", size: 18) else {
        throw CaptureTestFailure.assertion("Menlo-Regular 18pt is unavailable")
    }
    let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400), font: font)
    view.renderObservationScaleOverride = 2
    view.getTerminal().resize(cols: 100, rows: 20)
    view.frame = view.getOptimalFrameSize()
    let observer = DrawObserver()
    view.renderObserver = observer
    return (view, observer)
}

private func syncFrame(_ body: String) -> [UInt8] {
    Array(("\u{1b}[?2026h\u{1b}[2J\u{1b}[H" + body + "\u{1b}[?2026l").utf8)
}

private func feed(_ bytes: [UInt8], to terminal: Terminal, chunks: [Int]) {
    var offset = 0
    var index = 0
    while offset < bytes.count {
        let end = min(bytes.count, offset + chunks[index % chunks.count])
        terminal.feed(buffer: bytes[offset..<end])
        offset = end
        index += 1
    }
}

private func structural(_ frames: [ObservedFrame]) -> [[String]] {
    frames.map { frame in
        let glyphs = frame.glyphs.map {
            "g:\($0.row):\($0.slotColumn):\($0.sourceScalars):\($0.fontPostScriptName):\($0.glyphID):\($0.rightToLeft)"
        }
        let primitives = frame.primitives.map { primitive -> String in
            switch primitive {
            case let .block(value):
                return "b:\(value.row):\(value.column):\(value.codePoint):\(value.rectsPoints.count)"
            case let .boxDrawing(value):
                return "x:\(value.row):\(value.column):\(value.codePoint):\(value.baseThicknessPixels)"
            }
        }
        return glyphs + primitives
    }
}

func runDrawObservationTests() throws {
    let body = "אאב | سلام | ب | ⠿ | █░▄ | ─\r\n"
    let neighbor = "אאב | سلام | بب | ⠿ | █░▄ | ─\r\n"
    let erased = "אאב | سلام | ب  | ⠿ | █░▄ | ─\r\n"
    let payloads = [syncFrame(body), syncFrame(neighbor), syncFrame(erased)]

    let (wholeView, wholeObserver) = try makeObservedView()
    wholeView.getTerminal().feed(buffer: payloads.flatMap { $0 }[...])
    try captureRequire(
        wholeObserver.frames.count == 3,
        "every explicit frame must force one draw; observed \(wholeObserver.frames.count)"
    )

    let (chunkedView, chunkedObserver) = try makeObservedView()
    for payload in payloads {
        feed(payload, to: chunkedView.getTerminal(), chunks: [1, 2, 5, 3, 8, 13])
    }
    try captureRequire(
        structural(wholeObserver.frames) == structural(chunkedObserver.frames),
        "draw observation must not depend on UTF-8, CSI, or marker chunking"
    )

    let first = wholeObserver.frames[0]
    let second = wholeObserver.frames[1]
    let third = wholeObserver.frames[2]

    try captureRequire(
        first.glyphs.contains(where: { $0.rightToLeft && $0.sourceScalars.contains(0x05D0) }),
        "Hebrew must be observed from a right-to-left CoreText run"
    )
    let firstArabic = first.glyphs.first(where: { $0.sourceScalars.contains(0x0628) })
    let neighborArabic = second.glyphs.first(where: { $0.sourceScalars.contains(0x0628) })
    let erasedArabic = third.glyphs.first(where: { $0.sourceScalars.contains(0x0628) })
    try captureRequire(firstArabic != nil && neighborArabic != nil && erasedArabic != nil, "Arabic glyphs missing")
    try captureRequire(
        firstArabic?.glyphID != neighborArabic?.glyphID,
        "adding an Arabic neighbor must change the actual glyph selection"
    )
    try captureRequire(
        firstArabic?.glyphID == erasedArabic?.glyphID,
        "erasing the Arabic neighbor must restore the isolated glyph"
    )
    try captureRequire(
        first.glyphs.contains(where: {
            $0.sourceScalars.contains(0x05D0) && $0.fontPostScriptName != "Menlo-Regular"
        }),
        "fallback selection must be observed rather than inferred"
    )
    try captureRequire(
        first.glyphs.filter { $0.sourceScalars.contains(where: { (0x0600...0x06ff).contains($0) }) }.count < 6,
        "Arabic ligature shaping should collapse at least one source cluster"
    )
    try captureRequire(
        first.primitives.contains(where: {
            if case .block = $0 { return true }
            return false
        }),
        "block and shade glyphs must be recorded at the primitive draw site"
    )
    try captureRequire(
        first.primitives.contains(where: {
            if case .boxDrawing = $0 { return true }
            return false
        }),
        "box drawing must be recorded at its primitive draw site"
    )

    let pixels = try OffscreenRenderer.render(view: wholeView)
    let frameInfo = wholeView.renderFrameInfo()
    let firstCell = pixels.cellRGBA(column: 0, row: 0, frame: frameInfo)
    let blankCell = pixels.cellRGBA(column: 99, row: 19, frame: frameInfo)
    try captureRequire(firstCell != nil && blankCell != nil, "literal cell crops must be available")
    try captureRequire(firstCell != blankCell, "visible and blank cells must retain different literal pixels")
}
