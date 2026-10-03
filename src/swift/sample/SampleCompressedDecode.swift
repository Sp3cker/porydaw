import Foundation
import PorydawSampleCodec

enum SampleCompressedDecode {
    static func decode(
        _ bytes: Data, kind: SampleSourceKind, leftChannelOnly: Bool
    ) throws(SampleImportFailure) -> ImportedSample {
        let codec: PdSampleCodec
        let label: String
        let corruption: String
        switch kind {
        case .mp3:
            codec = PD_SAMPLE_CODEC_MP3
            label = "MP3"
            corruption = "the MP3 file is corrupt or truncated."
        case .flac:
            codec = PD_SAMPLE_CODEC_FLAC
            label = "FLAC"
            corruption = "the FLAC file is corrupt or truncated."
        case .ogg:
            codec = PD_SAMPLE_CODEC_OGG
            label = "Ogg"
            corruption = "cannot decode the Ogg file — only Ogg Vorbis is supported (Opus and other codecs are not)."
        case .wav, .aif, .sf2:
            preconditionFailure("only compressed sources use the codec bridge")
        }
        var pcm = PdSamplePcm()
        let status = bytes.withUnsafeBytes { input in
            pd_sample_decode(codec, input.bindMemory(to: UInt8.self).baseAddress, input.count, 1 << 26, &pcm)
        }
        defer { pd_sample_pcm_free(&pcm) }
        if status != PD_SAMPLE_DECODE_OK {
            if status == PD_SAMPLE_DECODE_EMPTY { throw SampleImportFailure("no audio data.") }
            if status == PD_SAMPLE_DECODE_TOO_LONG || status == PD_SAMPLE_DECODE_NO_MEMORY {
                throw SampleImportFailure("the \(label) file is too long to import.")
            }
            throw SampleImportFailure(corruption)
        }
        let channels = Int(pcm.channels)
        let frames = Int(pcm.sampleCount) / channels
        var sample = ImportedSample(
            sampleRate: Double(pcm.sampleRate), playLength: frames, sourceKind: kind,
            sourceChannels: channels, sourceBits: kind == .flac ? Int(pcm.bitsPerSample) : 0)
        if kind == .flac {
            guard let raw = pcm.s32 else { throw SampleImportFailure(corruption) }
            let values = Span(_unsafeStart: raw, count: Int(pcm.sampleCount))
            SampleImport.downmix(
                frames, channels: channels, leftOnly: leftChannelOnly,
                read: { (Double(values[$0]) / 2_147_483_648, false) }, into: &sample)
        } else {
            guard let raw = pcm.f32 else { throw SampleImportFailure(corruption) }
            let values = Span(_unsafeStart: raw, count: Int(pcm.sampleCount))
            SampleImport.downmix(
                frames, channels: channels, leftOnly: leftChannelOnly,
                read: { (min(1, max(-1, Double(values[$0]))), false) }, into: &sample)
        }
        return sample
    }
}
