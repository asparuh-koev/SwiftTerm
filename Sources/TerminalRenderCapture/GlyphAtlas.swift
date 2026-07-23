import AppKit
import CoreText
import Foundation

private struct GlyphAtlasKey: Hashable {
    let fontFileSHA256: String
    let glyphID: UInt16
    let pointSizeBits: UInt64
    let matrix: [UInt64]
}

final class GlyphAtlasBuilder {
    private var idsByKey: [GlyphAtlasKey: UInt32] = [:]
    private(set) var entries: [GlyphAtlasEntry] = []

    func insert(_ glyph: RenderedGlyph) -> UInt32? {
        let key = GlyphAtlasKey(
            fontFileSHA256: glyph.fontFileSHA256,
            glyphID: glyph.glyphID,
            pointSizeBits: glyph.pointSize.bitPattern,
            matrix: [
                glyph.affineMatrix.a.bitPattern,
                glyph.affineMatrix.b.bitPattern,
                glyph.affineMatrix.c.bitPattern,
                glyph.affineMatrix.d.bitPattern,
                glyph.affineMatrix.tx.bitPattern,
                glyph.affineMatrix.ty.bitPattern,
            ]
        )
        if let id = idsByKey[key] {
            return id
        }
        guard let raster = rasterize(glyph) else {
            return nil
        }
        let id = UInt32(entries.count)
        idsByKey[key] = id
        entries.append(
            GlyphAtlasEntry(
                id: id,
                fontFileSha256: glyph.fontFileSHA256,
                glyphId: glyph.glyphID,
                pointSize: glyph.pointSize,
                affineMatrix: glyph.affineMatrix,
                rasterSha256: raster.data.sha256Hex,
                pixelWidth: UInt32(raster.width),
                pixelHeight: UInt32(raster.height),
                bearingPoints: raster.bearing,
                alphaMaskPackbitsBase64: PackBits.encode(raster.data).base64EncodedString(),
                braillePreview: BraillePreview.alpha(
                    raster.data,
                    width: raster.width,
                    height: raster.height
                )
            )
        )
        return id
    }

    private func rasterize(
        _ glyph: RenderedGlyph
    ) -> (data: Data, width: Int, height: Int, bearing: RenderPoint)? {
        let transform = CGAffineTransform(
            a: glyph.affineMatrix.a,
            b: glyph.affineMatrix.b,
            c: glyph.affineMatrix.c,
            d: glyph.affineMatrix.d,
            tx: glyph.affineMatrix.tx,
            ty: glyph.affineMatrix.ty
        )
        var matrix = transform
        let font = CTFontCreateWithName(
            glyph.fontPostScriptName as CFString,
            glyph.pointSize,
            &matrix
        )
        var value = CGGlyph(glyph.glyphID)
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &value, &bounds, 1)
        let scale = 2.0
        let padding = 2
        let width = max(1, Int(ceil(bounds.width * scale)) + padding * 2)
        let height = max(1, Int(ceil(bounds.height * scale)) + padding * 2)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(NSColor.white.cgColor)
        context.scaleBy(x: scale, y: scale)
        var point = CGPoint(
            x: CGFloat(padding) / scale - bounds.minX,
            y: CGFloat(padding) / scale - bounds.minY
        )
        CTFontDrawGlyphs(font, &value, &point, 1, context)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alpha[index] = rgba[index * 4 + 3]
        }
        return (
            Data(alpha),
            width,
            height,
            RenderPoint(x: Double(bounds.minX), y: Double(bounds.minY))
        )
    }
}
