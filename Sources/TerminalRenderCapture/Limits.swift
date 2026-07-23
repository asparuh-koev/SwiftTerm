import Foundation

enum CaptureLimit: String, CaseIterable {
    case completeFrames = "complete_frames"
    case observedFrames = "observed_frames"
    case glyphAtlasEntries = "glyph_atlas_entries"
    case cellTileAtlasEntries = "cell_tile_atlas_entries"
    case canonicalJsonBytes = "canonical_json_bytes"
    case rawWireBytes = "raw_wire_bytes"
}

struct ActiveLimits {
    let observedFrames: UInt32
    let retainedFrames: UInt32
    let completeFrames: UInt32
    let glyphAtlasEntries: UInt32
    let cellTileAtlasEntries: UInt32
    let canonicalJsonBytes: UInt64
    let rawWireBytes: UInt64
    let childTimeoutMs: UInt64

    static let direct = ActiveLimits(
        observedFrames: 18_000,
        retainedFrames: 39,
        completeFrames: 300,
        glyphAtlasEntries: 4_096,
        cellTileAtlasEntries: 4_096,
        canonicalJsonBytes: 33_554_432,
        rawWireBytes: 16_777_216,
        childTimeoutMs: 120_000
    )

    init(_ limits: ScenarioLimits) {
        observedFrames = limits.observedFrames
        retainedFrames = limits.retainedFrames
        completeFrames = limits.completeFrames
        glyphAtlasEntries = limits.glyphAtlasEntries
        cellTileAtlasEntries = limits.cellTileAtlasEntries
        canonicalJsonBytes = limits.canonicalJsonBytes
        rawWireBytes = limits.rawWireBytes
        childTimeoutMs = limits.childTimeoutMs
    }

    private init(
        observedFrames: UInt32,
        retainedFrames: UInt32,
        completeFrames: UInt32,
        glyphAtlasEntries: UInt32,
        cellTileAtlasEntries: UInt32,
        canonicalJsonBytes: UInt64,
        rawWireBytes: UInt64,
        childTimeoutMs: UInt64
    ) {
        self.observedFrames = observedFrames
        self.retainedFrames = retainedFrames
        self.completeFrames = completeFrames
        self.glyphAtlasEntries = glyphAtlasEntries
        self.cellTileAtlasEntries = cellTileAtlasEntries
        self.canonicalJsonBytes = canonicalJsonBytes
        self.rawWireBytes = rawWireBytes
        self.childTimeoutMs = childTimeoutMs
    }

    var serialized: [String: UInt64] {
        [
            CaptureLimit.completeFrames.rawValue: UInt64(completeFrames),
            CaptureLimit.observedFrames.rawValue: UInt64(observedFrames),
            CaptureLimit.glyphAtlasEntries.rawValue: UInt64(glyphAtlasEntries),
            CaptureLimit.cellTileAtlasEntries.rawValue: UInt64(cellTileAtlasEntries),
            CaptureLimit.canonicalJsonBytes.rawValue: canonicalJsonBytes,
            CaptureLimit.rawWireBytes.rawValue: rawWireBytes,
        ]
    }
}
