import Foundation

public enum SampleReopen {
    public struct Result: Sendable {
        public let sample: ImportedSample
        public let restoredParams: SampleEditParams?
        public let fromSource: Bool
        public let provenance: SampleProvenance?
    }

    /// Re-decodes a matching provenance source, otherwise opens the committed WAV.
    public static func resolve(
        wav: Data, wavPath: String, provenance: SampleProvenance?
    )
        throws(SampleImportFailure) -> Result
    {
        if let provenance,
            let bytes = try? Data(contentsOf: URL(fileURLWithPath: provenance.sourcePath)),
            SampleSourceHash.sha256Hex(bytes) == provenance.sourceSha256
        {
            let sample: ImportedSample?
            if provenance.sf2Zone >= 0 {
                sample = try? Sf2Reader.extractZone(
                    Sf2Reader.read(bytes, sourcePath: provenance.sourcePath), index: provenance.sf2Zone)
            } else {
                sample = try? SampleImport.decode(
                    bytes, sourcePath: provenance.sourcePath, leftChannelOnly: provenance.leftOnly)
            }
            if let sample {
                return Result(
                    sample: sample, restoredParams: provenance.params,
                    fromSource: true, provenance: provenance)
            }
        }
        return Result(sample: try SampleImport.decode(wav, sourcePath: wavPath),
            restoredParams: nil, fromSource: false, provenance: nil)
    }
}
