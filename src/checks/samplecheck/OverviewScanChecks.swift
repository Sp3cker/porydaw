import Foundation
import PorydawSample

internal func runOverviewScanChecks(_ report: CheckReport) {
    let check = report.scoped(cppID: "swiftcore/SampleOverview::scan")
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav").path
    defer { try? FileManager.default.removeItem(atPath: path) }  // Best-effort scratch cleanup.
    // Three full chunks plus a partial one, 16-bit stereo, so the scan publishes progressively.
    let frames = 3 * SampleImport.observedChunk + 123
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<(frames * 4)).map { (_: Int) -> UInt8 in UInt8.random(in: 0...255, using: &generator) }
    do {
        try fixtureWav(SampleFixtureSpec(bits: 16, channels: 2, rate: 48000, samples: bytes, withSmpl: false))
            .write(to: URL(fileURLWithPath: path))
    } catch {
        check.expect(false, message: "the scan fixture must be writable: \(error)")
        return
    }

    var snapshots: [SampleOverview] = []
    let scanned: ImportedSample
    do {
        scanned = try SampleOverview.scan(
            path: path, publish: { (overview: SampleOverview) in snapshots.append(overview) },
            isCancelled: { () -> Bool in false })
    } catch {
        check.expect(false, message: "the fixture must scan: \(error.message)")
        return
    }
    check.expect(
        (try? SampleImport.decodeFile(path: path)) == scanned,
        message: "a scan decodes exactly what a whole-file decode does")
    let decodedFrames = snapshots.map(\.decodedFrames)
    check.expect(
        decodedFrames == [1, 2, 3].map { (chunk: Int) -> Int in chunk * SampleImport.observedChunk } + [frames],
        message: "the overview fills chunk by chunk up to the whole file")
    guard let final = snapshots.last, let first = snapshots.first else { return }
    check.expect(
        first.bins.count == first.decodedFrames / first.stride,
        message: "a partial overview holds only completed bins")
    let buffer = scanned.buffer
    let expected = stride(from: 0, to: frames, by: final.stride).map { (start: Int) -> [Float] in
        let slice = buffer[start..<min(frames, start + final.stride)]
        return [slice.min() ?? 0, slice.max() ?? 0]
    }
    check.expect(
        SamplePeakPyramid.levelStrides(frameCount: frames).contains(final.stride)
            && final.bins.map { (bin: SamplePeakPyramid.MinMax) -> [Float] in [bin.lo, bin.hi] } == expected,
        message: "the finished overview is the exact per-bin extrema at one of the pyramid's own strides")

    var published = 0
    do {
        _ = try SampleOverview.scan(
            path: path, publish: { (_: SampleOverview) in published += 1 },
            isCancelled: { () -> Bool in published > 0 })
        check.expect(false, message: "a cancelled scan must not finish")
    } catch {
        check.expect(published == 1, message: "cancelling stops the scan before its next chunk")
    }
}
