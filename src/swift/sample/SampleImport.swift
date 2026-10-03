import BinaryParsing
import Foundation

public enum SampleImport {
    public static func decode(
        _ bytes: Data, sourcePath: String,
        leftChannelOnly: Bool = false
    ) throws(SampleImportFailure) -> ImportedSample {
        let basename = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
        let name = SampleNames.sanitize(basename)
        return try bytes.withParserSpan { (input: inout ParserSpan) throws(SampleImportFailure) in
            let data = input.bytes
            func matches(_ position: Int, _ text: String) -> Bool {
                guard data.byteCount >= position + text.utf8.count else { return false }
                for (index, byte) in text.utf8.enumerated() where data[position + index] != byte {
                    return false
                }
                return true
            }
            var sample: ImportedSample
            if matches(0, "RIFF") && matches(8, "WAVE") {
                sample = try SampleWavReader.decode(data, leftChannelOnly: leftChannelOnly)
            } else if matches(0, "FORM") && matches(8, "AIFF") {
                sample = try SampleAiffReader.decode(data, leftChannelOnly: leftChannelOnly)
            } else if matches(0, "FORM") && matches(8, "AIFC") {
                throw SampleImportFailure("AIFF-C is not supported — export uncompressed AIFF or WAV.")
            } else if matches(0, "RIFF") && matches(8, "sfbk") {
                throw SampleImportFailure(
                    "SoundFont files hold multiple samples — pick a zone with the SoundFont zone picker.")
            } else if matches(0, "fLaC") {
                sample = try SampleCompressedDecode.decode(bytes, kind: .flac, leftChannelOnly: leftChannelOnly)
            } else if matches(0, "OggS") {
                sample = try SampleCompressedDecode.decode(bytes, kind: .ogg, leftChannelOnly: leftChannelOnly)
            } else if data.byteCount >= 4
                && (matches(0, "ID3")
                    || (data[0] == 0xFF && data[1] & 0xE0 == 0xE0))
            {
                sample = try SampleCompressedDecode.decode(bytes, kind: .mp3, leftChannelOnly: leftChannelOnly)
            } else {
                throw SampleImportFailure(
                    "not a supported audio file (WAV, AIFF, MP3, FLAC, and Ogg Vorbis sources are supported).")
            }
            sample.sourcePath = sourcePath
            sample.suggestedName = name
            let clipped = sample.buffer.reduce(0) { $0 + (abs($1) >= 0.9999 ? 1 : 0) }
            if sample.frameCount > 0 && Double(clipped) / Double(sample.frameCount) > 0.001 {
                sample.warnings.append("source is already clipped (\(clipped) samples at full scale).")
            }
            return sample
        }
    }

    public static func decodeFile(
        path: String, leftChannelOnly: Bool = false
    )
        throws(SampleImportFailure) -> ImportedSample
    {
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw SampleImportFailure("cannot read \(path).")
        }
        return try decode(bytes, sourcePath: path, leftChannelOnly: leftChannelOnly)
    }

    @discardableResult
    static func downmix(
        _ frames: Int, channels: Int, leftOnly: Bool,
        read: (Int) -> (value: Double, clamped: Bool), into sample: inout ImportedSample
    ) -> Int {
        var lr = 0.0
        var ll = 0.0
        var rr = 0.0
        var clippedSourceSamples = 0
        func consume(_ index: Int) -> Double {
            let source = read(index)
            if source.clamped { clippedSourceSamples += 1 }
            return source.value
        }
        sample.buffer = [Float](unsafeUninitializedCapacity: frames) { output, initialized in
            var destination = OutputSpan(buffer: output, initializedCount: 0)
            for frame in 0..<frames {
                let first = consume(frame * channels)
                if channels == 1 || leftOnly {
                    // Ignored channels still contribute to source clipping diagnostics.
                    if channels > 1 {
                        for channel in 1..<channels {
                            if read(frame * channels + channel).clamped { clippedSourceSamples += 1 }
                        }
                    }
                    destination.append(Float(first))
                } else {
                    // Preserve the fork's positive-zero start for near-cancelling stereo.
                    var sum = 0.0 + first
                    if channels == 2 {
                        let second = consume(frame * channels + 1)
                        sum += second
                        lr += first * second
                        ll += first * first
                        rr += second * second
                    } else {
                        for channel in 1..<channels { sum += consume(frame * channels + channel) }
                    }
                    destination.append(Float(sum / Double(channels)))
                }
            }
            initialized = destination.count
        }
        sample.phaseCancelStereo = channels == 2 && ll > 0 && rr > 0 && lr / sqrt(ll * rr) < 0
        if leftOnly && channels > 1 {
            sample.warnings.append("imported the left channel only.")
        } else if sample.phaseCancelStereo {
            sample.warnings.append(
                "left and right channels are phase-cancelling — the mono mix may sound hollow; consider re-importing with the left channel only."
            )
        }
        return clippedSourceSamples
    }
}
