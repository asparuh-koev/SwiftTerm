import Foundation

enum PackBits {
    static func encode(_ bytes: Data) -> Data {
        let input = [UInt8](bytes)
        var output: [UInt8] = []
        var index = 0
        while index < input.count {
            var runLength = 1
            while
                index + runLength < input.count,
                input[index + runLength] == input[index],
                runLength < 128
            {
                runLength += 1
            }
            if runLength >= 3 {
                output.append(UInt8(257 - runLength))
                output.append(input[index])
                index += runLength
                continue
            }

            let literalStart = index
            index += runLength
            while index < input.count && index - literalStart < 128 {
                var nextRun = 1
                while
                    index + nextRun < input.count,
                    input[index + nextRun] == input[index],
                    nextRun < 128
                {
                    nextRun += 1
                }
                if nextRun >= 3 {
                    break
                }
                index += min(nextRun, 128 - (index - literalStart))
            }
            let length = index - literalStart
            output.append(UInt8(length - 1))
            output.append(contentsOf: input[literalStart..<index])
        }
        return Data(output)
    }
}

enum BraillePreview {
    private static let dots = [
        [0x01, 0x02, 0x04, 0x40],
        [0x08, 0x10, 0x20, 0x80],
    ]

    static func alpha(_ bytes: Data, width: Int, height: Int) -> [String] {
        preview(width: width, height: height) { x, y in
            bytes[y * width + x] >= 96
        }
    }

    static func rgba(_ bytes: Data, width: Int, height: Int) -> [String] {
        preview(width: width, height: height) { x, y in
            let index = (y * width + x) * 4
            let red = Int(bytes[index])
            let green = Int(bytes[index + 1])
            let blue = Int(bytes[index + 2])
            let alpha = Int(bytes[index + 3])
            return alpha >= 64 && (red * 299 + green * 587 + blue * 114) / 1_000 >= 96
        }
    }

    private static func preview(
        width: Int,
        height: Int,
        occupied: (Int, Int) -> Bool
    ) -> [String] {
        var lines: [String] = []
        for blockY in stride(from: 0, to: height, by: 4) {
            var line = ""
            for blockX in stride(from: 0, to: width, by: 2) {
                var value = 0
                for x in 0..<2 {
                    for y in 0..<4
                    where blockX + x < width && blockY + y < height
                        && occupied(blockX + x, blockY + y)
                    {
                        value |= dots[x][y]
                    }
                }
                line.unicodeScalars.append(UnicodeScalar(0x2800 + value)!)
            }
            lines.append(line)
        }
        return lines
    }
}

final class CellTileAtlasBuilder {
    private var idsByDigest: [String: UInt32] = [:]
    private(set) var entries: [CellTileAtlasEntry] = []

    func insert(bytes: Data, width: Int, height: Int) -> UInt32 {
        let digest = bytes.sha256Hex
        if let id = idsByDigest[digest] {
            return id
        }
        let id = UInt32(entries.count)
        idsByDigest[digest] = id
        entries.append(
            CellTileAtlasEntry(
                id: id,
                rgbaSha256: digest,
                pixelWidth: UInt32(width),
                pixelHeight: UInt32(height),
                rgbaPackbitsBase64: PackBits.encode(bytes).base64EncodedString(),
                braillePreview: BraillePreview.rgba(bytes, width: width, height: height)
            )
        )
        return id
    }
}
