import Foundation

private func decodePackBits(_ data: Data) -> Data {
    let bytes = [UInt8](data)
    var output: [UInt8] = []
    var index = 0
    while index < bytes.count {
        let control = Int(Int8(bitPattern: bytes[index]))
        index += 1
        if control >= 0 {
            let count = control + 1
            output.append(contentsOf: bytes[index..<(index + count)])
            index += count
        } else if control != -128 {
            let count = 1 - control
            output.append(contentsOf: repeatElement(bytes[index], count: count))
            index += 1
        }
    }
    return Data(output)
}

func runLimitTests() throws {
    let source = Data([1, 1, 1, 2, 3, 4, 4, 5, 5, 5, 5, 6])
    let packed = PackBits.encode(source)
    try captureRequire(decodePackBits(packed) == source, "PackBits must be lossless")
    try captureRequire(
        CaptureLimit.allCases.map(\.rawValue) == [
            "complete_frames",
            "observed_frames",
            "glyph_atlas_entries",
            "cell_tile_atlas_entries",
            "canonical_json_bytes",
            "raw_wire_bytes",
        ],
        "runtime limit vocabulary or priority changed"
    )
    do {
        _ = try CLI.parse([
            "capture", "--artifact", "a.json", "--direct",
            "--cols", "100", "--rows", "20", "--timeout-seconds", "601",
            "--", "/usr/bin/ssh", "host",
        ])
        throw CaptureTestFailure.assertion("direct timeout above ceiling was accepted")
    } catch CLIError.usage {
    }
}
