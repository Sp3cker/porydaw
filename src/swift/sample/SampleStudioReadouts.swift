import Foundation

public enum SampleStudioReadouts {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.*f", locale: posixLocale, places, value)
    }

    /// Strict decimal grammar for the editor's fractional fields: `[+-]?[0-9]+(\.[0-9]+)?`
    /// after trimming spaces; no exponent, hex or grouping.
    public static func decimalValue(from text: String) -> Double? {
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

    /// Rate menu rows: the file's own rate first, then the fixed GBA table.
    public static func rateChoices(fileRate rate: Double) -> [String] {
        ["File rate (\(fileRate(rate)))"] + SampleRatePolicy.rates.map(String.init)
    }

    /// ROM cost of one sample: 16-byte header plus 4-byte-aligned PCM.
    public static func romBytes(_ output: ProcessedSample) -> UInt64 {
        16 + ((UInt64(output.size) + 3) & ~UInt64(3))
    }

    public static func romSize(bytes: UInt64) -> String {
        bytes >= 1024 ? "\(decimal(Double(bytes) / 1024, places: 1)) KB" : "\(bytes) bytes"
    }

    public static func gain(_ output: ProcessedSample, mode: SampleEditParams.NormalizeMode) -> String {
        let value = mode == .off ? 0 : (output.normalizeGain > 0 ? 20 * log10(output.normalizeGain) : 0)
        return "gain \(decimal(value, places: 1)) dB"
    }
}
