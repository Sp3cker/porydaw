import Foundation

public enum SampleReopen {
    public struct Result: Sendable {
        public let sample: ImportedSample
        public let restoredParams: SampleEditParams?
        public let fromSource: Bool
        public let sidecar: SampleSidecar?
    }

    /// Re-decodes a matching provenance source, otherwise opens the committed WAV.
    public static func resolve(wav: Data, wavPath: String, sidecar: SampleSidecar?)
        throws(SampleImportFailure) -> Result
    {
        if let sidecar,
            let bytes = try? Data(contentsOf: URL(fileURLWithPath: sidecar.sourcePath)),
            SampleSourceHash.sha256Hex(bytes) == sidecar.sourceSha256
        {
            let sample: ImportedSample?
            if sidecar.sf2Zone >= 0 {
                sample = try? Sf2Reader.extractZone(
                    Sf2Reader.read(bytes, sourcePath: sidecar.sourcePath), index: sidecar.sf2Zone)
            } else {
                sample = try? SampleImport.decode(
                    bytes, sourcePath: sidecar.sourcePath, leftChannelOnly: sidecar.leftOnly)
            }
            if let sample {
                return Result(sample: sample, restoredParams: sidecar.params,
                    fromSource: true, sidecar: sidecar)
            }
        }
        return Result(sample: try SampleImport.decode(wav, sourcePath: wavPath),
            restoredParams: nil, fromSource: false, sidecar: nil)
    }
}
