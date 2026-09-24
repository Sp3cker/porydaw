/// Project-scoped symbol choices used by the voice editor; the bank itself
/// carries only its currently loaded slot values.
public struct VoicegroupCatalog: Sendable {
    public var samples: [String]
    public var waves: [String]
    public var drumkits: [String]
    public var keysplits: [String: String]
    public var synths: [String]
    public var defaults: VoiceListAdsrDefaults

    public init(samples: [String], waves: [String], drumkits: [String],
                keysplits: [String: String], synths: [String],
                defaults: VoiceListAdsrDefaults) {
        self.samples = samples
        self.waves = waves
        self.drumkits = drumkits
        self.keysplits = keysplits
        self.synths = synths
        self.defaults = defaults
    }
}
