import Foundation

/// One `SamplePeakPyramid` level of a source file, filled while the file decodes.
public struct SampleOverview: Sendable, Equatable {
    /// The finest ladder level kept has at most this many bins: wider than any strip.
    static let maxBins = 1 << 14

    public private(set) var frameCount = 0
    public private(set) var stride = 1
    public private(set) var decodedFrames = 0
    /// Completed bins over `[0, decodedFrames)`; the final partial bin lands once decoding ends.
    public private(set) var bins: [SamplePeakPyramid.MinMax] = []
    private var running = SamplePeakPyramid.MinMax(lo: 0, hi: 0)
    private var filled = 0

    public init() {}

    /// Decodes `path` once from a mapped file, publishing the overview as frames decode.
    /// `isCancelled` is polled between chunks; cancelling throws.
    public static func scan(
        path: String, publish: (SampleOverview) -> Void, isCancelled: () -> Bool
    ) throws(SampleImportFailure) -> ImportedSample {
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            throw SampleImportFailure("cannot read \(path).")
        }
        var overview = SampleOverview()
        return try SampleImport.decode(bytes, sourcePath: path) {
            (decoded: Span<Float>, total: Int) throws(SampleImportFailure) in
            if isCancelled() { throw SampleImportFailure("cancelled.") }
            overview.fold(decoded, total: total)
            publish(overview)
        }
    }

    mutating func fold(_ decoded: Span<Float>, total: Int) {
        if frameCount == 0 {
            frameCount = total
            let strides = SamplePeakPyramid.levelStrides(frameCount: total)
            stride =
                strides.first { (candidate: Int) -> Bool in (total + candidate - 1) / candidate <= Self.maxBins }
                ?? strides[strides.count - 1]
            bins.reserveCapacity((total + stride - 1) / stride)
        }
        for index in decodedFrames..<decoded.count {
            let value = decoded[index]
            if filled == 0 {
                running = SamplePeakPyramid.MinMax(lo: value, hi: value)
            } else {
                running.include(value)
            }
            filled += 1
            if filled == stride {
                bins.append(running)
                filled = 0
            }
        }
        decodedFrames = decoded.count
        if decodedFrames == frameCount && filled > 0 {
            bins.append(running)
            filled = 0
        }
    }
}
