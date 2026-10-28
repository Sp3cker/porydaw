/// Shared GBA target-rate selection and selectable PCM rates for sample studios.
public enum SampleRatePolicy {
    /// The fixed GBA PCM rate table, ascending.
    public static let rates = [5734, 7884, 10512, 13379, 15768, 18157, 21024, 26758, 31536, 36314, 40137, 42048]

    /// Keeps a GBA-ready source's rate; otherwise caps at the GBA default without upsampling.
    public static func targetRate(gbaReady: Bool, sourceRate: Double) -> Double {
        gbaReady ? sourceRate : min(sourceRate, ImportedSample.gbaDefaultRate)
    }

    /// Lists the rounded source rate first when representable, then the fixed table without deduplication.
    public static func rateOptions(sourceRate: Double) -> [Int] {
        guard sourceRate.isFinite, sourceRate > 0, let source = Int(exactly: sourceRate.rounded()) else { return rates }
        var options: [Int] = []
        options.reserveCapacity(rates.count + 1)
        options.append(source)
        options.append(contentsOf: rates)
        return options
    }
}
