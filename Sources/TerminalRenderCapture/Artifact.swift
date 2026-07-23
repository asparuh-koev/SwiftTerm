import CryptoKit
import Darwin
import Foundation

enum EvidenceKind: String, Codable {
    case complete
    case incomplete
    case truncated
}

struct FailureReason: Codable, Equatable {
    let code: String
    let detail: String
    let limit: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case detail
        case limit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(detail, forKey: .detail)
        if let limit {
            try container.encode(limit, forKey: .limit)
        } else {
            try container.encodeNil(forKey: .limit)
        }
    }
}

struct EvidenceStatus: Codable, Equatable {
    let kind: EvidenceKind
    let reason: FailureReason?
    let lastAuthoritativeOrdinal: UInt32?

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
        case lastAuthoritativeOrdinal
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if let reason {
            try container.encode(reason, forKey: .reason)
        } else {
            try container.encodeNil(forKey: .reason)
        }
        if let lastAuthoritativeOrdinal {
            try container.encode(lastAuthoritativeOrdinal, forKey: .lastAuthoritativeOrdinal)
        } else {
            try container.encodeNil(forKey: .lastAuthoritativeOrdinal)
        }
    }
}

struct ArtifactScenario: Codable, Equatable {
    let id: String
    let sha256: String
}

struct ArtifactProvenance: Codable, Equatable {
    let toolCommit: String
    let swifttermForkCommit: String
    let swifttermUpstreamBase: String
}

struct ArtifactEnvironment: Codable, Equatable {
    let fingerprint: String
    let components: [String: String]
}

struct ArtifactTransport: Codable, Equatable {
    let kind: String
    let authoritativeBoundary: String
    let observedFrameCount: UInt32
}

struct ArtifactRetention: Codable, Equatable {
    let mode: String
    let limits: [String: UInt64]
    let retainedOrdinals: [UInt32]
}

struct Dimensions: Codable, Equatable {
    let cols: UInt16
    let rows: UInt16
}

struct CellRef: Codable, Equatable {
    let sourceText: String
    let width: UInt8
    let continuationOf: CellPoint?
    let glyphDrawIds: [UInt32]
    let primitiveDrawIds: [UInt32]
    let tileId: UInt32
    let foregroundRgba: RenderRGBA
    let backgroundRgba: RenderRGBA

    private enum CodingKeys: String, CodingKey {
        case sourceText
        case width
        case continuationOf
        case glyphDrawIds
        case primitiveDrawIds
        case tileId
        case foregroundRgba
        case backgroundRgba
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceText, forKey: .sourceText)
        try container.encode(width, forKey: .width)
        if let continuationOf {
            try container.encode(continuationOf, forKey: .continuationOf)
        } else {
            try container.encodeNil(forKey: .continuationOf)
        }
        try container.encode(glyphDrawIds, forKey: .glyphDrawIds)
        try container.encode(primitiveDrawIds, forKey: .primitiveDrawIds)
        try container.encode(tileId, forKey: .tileId)
        try container.encode(foregroundRgba, forKey: .foregroundRgba)
        try container.encode(backgroundRgba, forKey: .backgroundRgba)
    }
}

struct CellChange: Codable, Equatable {
    let col: UInt16
    let row: UInt16
    let cell: CellRef
}

enum DrawCall: Codable, Equatable {
    case glyph(id: UInt32, value: RenderedGlyph)
    case primitive(id: UInt32, value: RenderedPrimitive)

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case glyph
        case primitive
    }

    var id: UInt32 {
        switch self {
        case let .glyph(id, _), let .primitive(id, _):
            return id
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UInt32.self, forKey: .id)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .glyph:
            self = .glyph(id: id, value: try container.decode(RenderedGlyph.self, forKey: .value))
        case .primitive:
            self = .primitive(
                id: id,
                value: try container.decode(RenderedPrimitive.self, forKey: .value)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .glyph(id, value):
            try container.encode(id, forKey: .id)
            try container.encode(Kind.glyph, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .primitive(id, value):
            try container.encode(id, forKey: .id)
            try container.encode(Kind.primitive, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

struct Frame: Codable, Equatable {
    let streamOrdinal: UInt32
    let checkpoints: [String]
    let dimensions: Dimensions
    let baseRows: [[CellRef]]?
    let changes: [CellChange]
    let drawCalls: [DrawCall]
    let framebufferRgbaSha256: String

    private enum CodingKeys: String, CodingKey {
        case streamOrdinal
        case checkpoints
        case dimensions
        case baseRows
        case changes
        case drawCalls
        case framebufferRgbaSha256
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(streamOrdinal, forKey: .streamOrdinal)
        try container.encode(checkpoints, forKey: .checkpoints)
        try container.encode(dimensions, forKey: .dimensions)
        if let baseRows {
            try container.encode(baseRows, forKey: .baseRows)
        } else {
            try container.encodeNil(forKey: .baseRows)
        }
        try container.encode(changes, forKey: .changes)
        try container.encode(drawCalls, forKey: .drawCalls)
        try container.encode(framebufferRgbaSha256, forKey: .framebufferRgbaSha256)
    }
}

struct GlyphAtlasEntry: Codable, Equatable {
    let id: UInt32
    let fontFileSha256: String
    let glyphId: UInt16
    let pointSize: Double
    let affineMatrix: RenderAffine
    let rasterSha256: String
    let pixelWidth: UInt32
    let pixelHeight: UInt32
    let bearingPoints: RenderPoint
    let alphaMaskPackbitsBase64: String
    let braillePreview: [String]
}

struct CellTileAtlasEntry: Codable, Equatable {
    let id: UInt32
    let rgbaSha256: String
    let pixelWidth: UInt32
    let pixelHeight: UInt32
    let rgbaPackbitsBase64: String
    let braillePreview: [String]
}

struct PortableAssertionResult: Codable, Equatable {
    let name: String
    let kind: String
    let passed: Bool
    let detail: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case passed
        case detail
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(passed, forKey: .passed)
        if let detail {
            try container.encode(detail, forKey: .detail)
        } else {
            try container.encodeNil(forKey: .detail)
        }
    }
}

struct ExactAssertionResult: Codable, Equatable {
    let kind: String
    let firstDifference: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case firstDifference
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if let firstDifference {
            try container.encode(firstDifference, forKey: .firstDifference)
        } else {
            try container.encodeNil(forKey: .firstDifference)
        }
    }
}

struct ArtifactAssertions: Codable, Equatable {
    let portable: [PortableAssertionResult]
    let exact: ExactAssertionResult
}

struct CaptureOutcome: Codable, Equatable {
    let kind: String
    let failedAssertions: [String]
    let firstDifference: String?
    let reasonCode: String?
    let limit: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case failedAssertions
        case firstDifference
        case reasonCode
        case limit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(failedAssertions, forKey: .failedAssertions)
        if let firstDifference {
            try container.encode(firstDifference, forKey: .firstDifference)
        } else {
            try container.encodeNil(forKey: .firstDifference)
        }
        if let reasonCode {
            try container.encode(reasonCode, forKey: .reasonCode)
        } else {
            try container.encodeNil(forKey: .reasonCode)
        }
        if let limit {
            try container.encode(limit, forKey: .limit)
        } else {
            try container.encodeNil(forKey: .limit)
        }
    }

    static func passed() -> CaptureOutcome {
        CaptureOutcome(
            kind: "passed",
            failedAssertions: [],
            firstDifference: nil,
            reasonCode: nil,
            limit: nil
        )
    }
}

struct ArtifactSummary: Codable, Equatable {
    let outcome: CaptureOutcome
    let observedFrames: UInt32
    let retainedFrames: UInt32
    let glyphCalls: UInt32
    let primitiveCalls: UInt32
    let uniqueGlyphs: UInt32
    let uniqueTiles: UInt32
    let canonicalBytes: UInt64
    let utilization: [String: UInt64]
}

struct CaptureArtifact: Codable, Equatable {
    let schema: String
    let status: EvidenceStatus
    let scenario: ArtifactScenario
    let provenance: ArtifactProvenance
    let environment: ArtifactEnvironment
    let transport: ArtifactTransport
    let retention: ArtifactRetention
    let frames: [Frame]
    let glyphAtlas: [GlyphAtlasEntry]
    let cellTileAtlas: [CellTileAtlasEntry]
    let assertions: ArtifactAssertions
    let summary: ArtifactSummary
}

struct BaselinePayload: Codable, Equatable {
    let schema: String
    let scenario: ArtifactScenario
    let provenance: ArtifactProvenance
    let environment: ArtifactEnvironment
    let frames: [Frame]
    let glyphAtlas: [GlyphAtlasEntry]
    let cellTileAtlas: [CellTileAtlasEntry]
    let payloadSha256: String
}

enum ArtifactError: Error {
    case encode
    case decode
    case write
}

enum CanonicalJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(value) else {
            throw ArtifactError.encode
        }
        data.append(0x0a)
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let value = try? decoder.decode(type, from: data) else {
            throw ArtifactError.decode
        }
        return value
    }

    static func writeAtomic<T: Encodable>(_ value: T, to url: URL) throws -> UInt64 {
        let data = try encode(value)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let partial = url.appendingPathExtension("partial")
            try data.write(to: partial, options: [])
            let handle = try FileHandle(forWritingTo: partial)
            try handle.synchronize()
            try handle.close()
            guard rename(partial.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return UInt64(data.count)
        } catch {
            throw ArtifactError.write
        }
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard let data = try? Data(contentsOf: url) else {
            throw ArtifactError.decode
        }
        return try decode(type, from: data)
    }
}

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).hex
    }
}
