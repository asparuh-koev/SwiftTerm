import Foundation

func runBaselineTests() throws {
    let root = URL(fileURLWithPath: ".build/test-baselines", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    let artifact = sampleArtifact()
    let created = try BaselineStore.update(artifact: artifact, root: root, replace: false)
    try captureRequire(FileManager.default.fileExists(atPath: created.path), "baseline update failed")
    try captureRequire(
        BaselineStore.compare(artifact: artifact, root: root).kind == "passed",
        "matching environment and payload must compare exactly"
    )
    do {
        _ = try BaselineStore.update(artifact: artifact, root: root, replace: false)
        throw CaptureTestFailure.assertion("existing baseline was replaced without --replace")
    } catch BaselineError.exists {
    }
    _ = try BaselineStore.update(artifact: artifact, root: root, replace: true)

    let observational = sampleArtifact(transport: "observational-direct")
    do {
        _ = try BaselineStore.update(artifact: observational, root: root, replace: true)
        throw CaptureTestFailure.assertion("observational artifact updated a baseline")
    } catch BaselineError.ineligible {
    }
}
