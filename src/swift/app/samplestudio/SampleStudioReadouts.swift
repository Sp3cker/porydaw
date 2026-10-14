import Foundation
import PorydawCore
import PorydawSample

public enum SampleStudioReadouts {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.*f", locale: posixLocale, places, value)
    }

    /// Strict decimal grammar for the editor's fractional fields: `[+-]?[0-9]+(\.[0-9]+)?`
    /// after trimming spaces; no exponent, hex or grouping.
    static func decimalValue(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let unsigned = trimmed.first == "-" || trimmed.first == "+" ? trimmed.dropFirst() : trimmed[...]
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
            parts.allSatisfy({ (part: Substring) -> Bool in
                !part.isEmpty
                    && part.allSatisfy { (character: Character) -> Bool in character.isASCII && character.isNumber }
            })
        else { return nil }
        return Double(trimmed).flatMap { (value: Double) -> Double? in value.isFinite ? value : nil }
    }

    public static func fileRate(_ rate: Double) -> String {
        "\(decimal(rate, places: rate == floor(rate) ? 0 : 2)) Hz"
    }

    public static func romSize(_ output: ProcessedSample) -> String {
        let romBytes = 16 + ((UInt64(output.size) + 3) & ~UInt64(3))
        return romBytes >= 1024 ? "\(decimal(Double(romBytes) / 1024, places: 1)) KB" : "\(romBytes) bytes"
    }

    public static func gain(_ output: ProcessedSample, mode: SampleEditParams.NormalizeMode) -> String {
        let value = mode == .off ? 0 : (output.normalizeGain > 0 ? 20 * log10(output.normalizeGain) : 0)
        return "gain \(decimal(value, places: 1)) dB"
    }
}
