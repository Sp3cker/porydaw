import Foundation
import PorydawCore
import PorydawSample

public enum SampleStudioReadouts {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.*f", locale: posixLocale, places, value)
    }
    /// Parses the editor's numeric or note-name prefix, including its displayed "C4 (60)" form.
    public static func midiKey(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Int(trimmed) { return min(127, max(0, direct)) }
        let pattern = #"^([A-Ga-g])([#b]?)(-?\d+)"#
        guard let match = trimmed.range(of: pattern, options: .regularExpression),
            let letter = trimmed[match].first
        else { return nil }
        let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let semitone = semitones[Character(letter.uppercased())] else { return nil }
        let rest = trimmed[match].dropFirst()
        let accidental = rest.first == "#" ? 1 : (rest.first == "b" ? -1 : 0)
        let octave = Int(accidental == 0 ? rest : rest.dropFirst()) ?? 0
        return octave >= 11
            ? 127
            : octave <= -3
                ? 0
                : min(127, max(0, (octave + 1) * 12 + semitone + accidental))
    }

    public static func sourceLine(_ source: ImportedSample) -> String {
        var kind: String
        switch source.sourceKind {
        case .wav: kind = source.sourceFloat ? "float WAV" : "PCM WAV"
        case .aif: kind = "AIFF"
        case .mp3: kind = "MP3"
        case .flac: kind = "FLAC"
        case .ogg: kind = "Ogg Vorbis"
        case .sf2: kind = "SoundFont zone"
        }
        if source.sourceBits > 0 { kind = "\(source.sourceBits)-bit \(kind)" }
        let rate = decimal(source.sampleRate, places: source.sampleRate == floor(source.sampleRate) ? 0 : 2)
        var result =
            "\(kind), \(source.sourceChannels) channel\(source.sourceChannels == 1 ? "" : "s"), \(rate) Hz, \(source.frameCount) samples"
        if source.sampleRate > 0 {
            result += " (\(decimal(Double(source.frameCount) / source.sampleRate, places: 2)) s)"
        }
        return result
    }

    public static func summary(source: ImportedSample, output: ProcessedSample) -> String {
        let romBytes = 16 + ((UInt64(output.size) + 3) & ~UInt64(3))
        var lines: [String] = []
        let cost = romBytes >= 1024 ? "\(decimal(Double(romBytes) / 1024, places: 1)) KB ROM" : "\(romBytes) bytes ROM"
        let duration =
            output.outputRate > 0 ? "\(decimal(Double(output.size) / output.outputRate, places: 2)) s · " : ""
        lines.append(duration + cost)
        lines.append(contentsOf: (source.warnings + output.warnings).map { "Warning: \($0)" })
        return lines.joined(separator: "\n")
    }

    public static func gain(_ output: ProcessedSample, mode: SampleEditParams.NormalizeMode) -> String {
        let value = mode == .off ? 0 : (output.normalizeGain > 0 ? 20 * log10(output.normalizeGain) : 0)
        return "gain \(decimal(value, places: 1)) dB"
    }

    public static func technical(_ output: ProcessedSample) -> String {
        let romBytes = 16 + ((UInt64(output.size) + 3) & ~UInt64(3))
        let loop = output.looped ? " — loop \(output.loopStart)..\(output.size)" : " — one-shot"
        var lines = ["Output: \(output.size) samples @ \(output.declaredRate) Hz\(loop)"]
        lines.append(
            "Pitch: \(decimal(Double(output.freq) / 1024, places: 2)) Hz at C4 (60) — agbp \(output.freq), unity \(output.unityNote) (\(midiKeyName(output.unityNote)))"
        )
        var cost = "ROM cost: \(romBytes) bytes"
        if output.seam.valid {
            cost += " — seam amp \(output.seam.ampLsb) LSB, slope \(output.seam.derivLsb)"
            if output.seam.nccValid { cost += ", match \(Int(output.seam.ncc * 100))%" }
        }
        lines.append(cost)
        return lines.joined(separator: "\n")
    }
}
