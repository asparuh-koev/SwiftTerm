#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct RenderPoint: Codable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct RenderSize: Codable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct RenderRect: Codable, Equatable {
    public let origin: RenderPoint
    public let size: RenderSize

    public init(origin: RenderPoint, size: RenderSize) {
        self.origin = origin
        self.size = size
    }
}

public struct RenderRGBA: Codable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct RenderAffine: Codable, Equatable {
    public let a: Double
    public let b: Double
    public let c: Double
    public let d: Double
    public let tx: Double
    public let ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }
}

public struct RenderFrameInfo: Codable, Equatable {
    public let rows: Int
    public let columns: Int
    public let cellSizePoints: RenderSize
    public let backingScale: Double

    public init(rows: Int, columns: Int, cellSizePoints: RenderSize, backingScale: Double) {
        self.rows = rows
        self.columns = columns
        self.cellSizePoints = cellSizePoints
        self.backingScale = backingScale
    }
}

public struct RenderedGlyph: Codable, Equatable {
    public let row: Int
    public let segmentColumn: Int
    public let slotColumn: Int
    public let slotWidth: Int
    public let sourceUTF16Location: Int
    public let sourceUTF16Length: Int
    public let sourceScalars: [UInt32]
    public let runStatusRaw: UInt32
    public let rightToLeft: Bool
    public let fontPostScriptName: String
    public let fontFullName: String
    public let fontVersion: String
    public let fontFileSHA256: String
    public let pointSize: Double
    public let affineMatrix: RenderAffine
    public let glyphID: UInt16
    public let glyphNameIfAvailable: String?
    public let positionPoints: RenderPoint
    public let advancePoints: RenderSize
    public let foregroundRGBA: RenderRGBA

    public init(
        row: Int,
        segmentColumn: Int,
        slotColumn: Int,
        slotWidth: Int,
        sourceUTF16Location: Int,
        sourceUTF16Length: Int,
        sourceScalars: [UInt32],
        runStatusRaw: UInt32,
        rightToLeft: Bool,
        fontPostScriptName: String,
        fontFullName: String,
        fontVersion: String,
        fontFileSHA256: String,
        pointSize: Double,
        affineMatrix: RenderAffine,
        glyphID: UInt16,
        glyphNameIfAvailable: String?,
        positionPoints: RenderPoint,
        advancePoints: RenderSize,
        foregroundRGBA: RenderRGBA
    ) {
        self.row = row
        self.segmentColumn = segmentColumn
        self.slotColumn = slotColumn
        self.slotWidth = slotWidth
        self.sourceUTF16Location = sourceUTF16Location
        self.sourceUTF16Length = sourceUTF16Length
        self.sourceScalars = sourceScalars
        self.runStatusRaw = runStatusRaw
        self.rightToLeft = rightToLeft
        self.fontPostScriptName = fontPostScriptName
        self.fontFullName = fontFullName
        self.fontVersion = fontVersion
        self.fontFileSHA256 = fontFileSHA256
        self.pointSize = pointSize
        self.affineMatrix = affineMatrix
        self.glyphID = glyphID
        self.glyphNameIfAvailable = glyphNameIfAvailable
        self.positionPoints = positionPoints
        self.advancePoints = advancePoints
        self.foregroundRGBA = foregroundRGBA
    }

    private enum CodingKeys: String, CodingKey {
        case row
        case segmentColumn
        case slotColumn
        case slotWidth
        case sourceUTF16Location
        case sourceUTF16Length
        case sourceScalars
        case runStatusRaw
        case rightToLeft
        case fontPostScriptName
        case fontFullName
        case fontVersion
        case fontFileSHA256
        case pointSize
        case affineMatrix
        case glyphID
        case glyphNameIfAvailable
        case positionPoints
        case advancePoints
        case foregroundRGBA
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(segmentColumn, forKey: .segmentColumn)
        try container.encode(slotColumn, forKey: .slotColumn)
        try container.encode(slotWidth, forKey: .slotWidth)
        try container.encode(sourceUTF16Location, forKey: .sourceUTF16Location)
        try container.encode(sourceUTF16Length, forKey: .sourceUTF16Length)
        try container.encode(sourceScalars, forKey: .sourceScalars)
        try container.encode(runStatusRaw, forKey: .runStatusRaw)
        try container.encode(rightToLeft, forKey: .rightToLeft)
        try container.encode(fontPostScriptName, forKey: .fontPostScriptName)
        try container.encode(fontFullName, forKey: .fontFullName)
        try container.encode(fontVersion, forKey: .fontVersion)
        try container.encode(fontFileSHA256, forKey: .fontFileSHA256)
        try container.encode(pointSize, forKey: .pointSize)
        try container.encode(affineMatrix, forKey: .affineMatrix)
        try container.encode(glyphID, forKey: .glyphID)
        if let glyphNameIfAvailable {
            try container.encode(glyphNameIfAvailable, forKey: .glyphNameIfAvailable)
        } else {
            try container.encodeNil(forKey: .glyphNameIfAvailable)
        }
        try container.encode(positionPoints, forKey: .positionPoints)
        try container.encode(advancePoints, forKey: .advancePoints)
        try container.encode(foregroundRGBA, forKey: .foregroundRGBA)
    }
}

public struct RenderedBlock: Codable, Equatable {
    public let codePoint: UInt32
    public let row: Int
    public let column: Int
    public let columnWidth: Int
    public let rgba: RenderRGBA
    public let rectsPoints: [RenderRect]

    public init(
        codePoint: UInt32,
        row: Int,
        column: Int,
        columnWidth: Int,
        rgba: RenderRGBA,
        rectsPoints: [RenderRect]
    ) {
        self.codePoint = codePoint
        self.row = row
        self.column = column
        self.columnWidth = columnWidth
        self.rgba = rgba
        self.rectsPoints = rectsPoints
    }
}

public struct RenderedBox: Codable, Equatable {
    public let codePoint: UInt32
    public let row: Int
    public let column: Int
    public let columnWidth: Int
    public let rgba: RenderRGBA
    public let cellOriginPoints: RenderPoint
    public let cellSizePoints: RenderSize
    public let scale: Double
    public let baseThicknessPixels: Int

    public init(
        codePoint: UInt32,
        row: Int,
        column: Int,
        columnWidth: Int,
        rgba: RenderRGBA,
        cellOriginPoints: RenderPoint,
        cellSizePoints: RenderSize,
        scale: Double,
        baseThicknessPixels: Int
    ) {
        self.codePoint = codePoint
        self.row = row
        self.column = column
        self.columnWidth = columnWidth
        self.rgba = rgba
        self.cellOriginPoints = cellOriginPoints
        self.cellSizePoints = cellSizePoints
        self.scale = scale
        self.baseThicknessPixels = baseThicknessPixels
    }
}

public enum RenderedPrimitive: Codable, Equatable {
    case block(RenderedBlock)
    case boxDrawing(RenderedBox)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case block
        case box
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .block:
            self = .block(try container.decode(RenderedBlock.self, forKey: .value))
        case .box:
            self = .boxDrawing(try container.decode(RenderedBox.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .block(value):
            try container.encode(Kind.block, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .boxDrawing(value):
            try container.encode(Kind.box, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

public protocol TerminalRenderObserver: AnyObject {
    func terminalView(
        _ source: TerminalView,
        synchronizedOutputEnded reason: SynchronizedOutputEndReason
    )
    func terminalView(_ source: TerminalView, beginFrame frame: RenderFrameInfo)
    func terminalView(_ source: TerminalView, drewGlyph glyph: RenderedGlyph)
    func terminalView(_ source: TerminalView, drewPrimitive primitive: RenderedPrimitive)
    func terminalView(_ source: TerminalView, endFrame frame: RenderFrameInfo)
}

private final class RenderFontDigestCache {
    static let shared = RenderFontDigestCache()

    private let lock = NSLock()
    private var values: [URL: String] = [:]

    func digest(for url: URL) -> String? {
        lock.lock()
        if let value = values[url] {
            lock.unlock()
            return value
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let value = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        lock.lock()
        values[url] = value
        lock.unlock()
        return value
    }
}

extension TerminalView {
    func renderFrameInfo() -> RenderFrameInfo {
        RenderFrameInfo(
            rows: terminal.rows,
            columns: terminal.cols,
            cellSizePoints: RenderSize(
                width: Double(cellDimension.width),
                height: Double(cellDimension.height)
            ),
            backingScale: Double(backingScaleFactor())
        )
    }

    func renderRGBA(_ color: TTColor) -> RenderRGBA? {
        #if os(macOS)
        guard let converted = color.usingColorSpace(.deviceRGB) else {
            return nil
        }
        return RenderRGBA(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
        #else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return RenderRGBA(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
        #endif
    }

    func observedGlyph(
        row: Int,
        segment: ViewLineSegment,
        slotColumn: Int,
        slotWidth: Int,
        run: CTRun,
        glyphIndex: Int,
        glyph: CGGlyph,
        font: CTFont,
        position: CGPoint,
        advance: CGSize,
        foregroundColor: TTColor
    ) -> RenderedGlyph? {
        guard
            position.x.isFinite,
            position.y.isFinite,
            advance.width.isFinite,
            advance.height.isFinite,
            let fontURL = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
            let digest = RenderFontDigestCache.shared.digest(for: fontURL),
            let rgba = renderRGBA(foregroundColor)
        else {
            return nil
        }

        let count = CTRunGetGlyphCount(run)
        var indices = [CFIndex](repeating: 0, count: count)
        CTRunGetStringIndices(run, CFRange(), &indices)
        let runRange = CTRunGetStringRange(run)
        let location = indices[glyphIndex]
        let sortedBoundaries = Set(indices.filter { $0 >= runRange.location })
            .union([runRange.location + runRange.length])
            .sorted()
        let next = sortedBoundaries.first(where: { $0 > location }) ?? (runRange.location + runRange.length)
        let length = max(0, next - location)
        let sourceRange = NSRange(location: location, length: length)
        let scalars: [UInt32]
        if NSMaxRange(sourceRange) <= segment.attributedString.length {
            scalars = segment.attributedString
                .attributedSubstring(from: sourceRange)
                .string
                .unicodeScalars
                .map(\.value)
        } else {
            scalars = []
        }

        let matrix = CTFontGetMatrix(font)
        let status = CTRunGetStatus(run)
        return RenderedGlyph(
            row: row,
            segmentColumn: segment.column,
            slotColumn: slotColumn,
            slotWidth: slotWidth,
            sourceUTF16Location: location,
            sourceUTF16Length: length,
            sourceScalars: scalars,
            runStatusRaw: UInt32(status.rawValue),
            rightToLeft: status.contains(.rightToLeft),
            fontPostScriptName: CTFontCopyPostScriptName(font) as String,
            fontFullName: (CTFontCopyFullName(font) as String?) ?? "",
            fontVersion: (CTFontCopyName(font, kCTFontVersionNameKey) as String?) ?? "",
            fontFileSHA256: digest,
            pointSize: Double(CTFontGetSize(font)),
            affineMatrix: RenderAffine(
                a: Double(matrix.a),
                b: Double(matrix.b),
                c: Double(matrix.c),
                d: Double(matrix.d),
                tx: Double(matrix.tx),
                ty: Double(matrix.ty)
            ),
            glyphID: UInt16(glyph),
            glyphNameIfAvailable: CTFontCopyNameForGlyph(font, glyph) as String?,
            positionPoints: RenderPoint(x: Double(position.x), y: Double(position.y)),
            advancePoints: RenderSize(width: Double(advance.width), height: Double(advance.height)),
            foregroundRGBA: rgba
        )
    }
}
#endif
