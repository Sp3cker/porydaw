import PorydawProject

/// Project-scoped symbol choices used by the voice editor; the bank itself
/// carries only its currently loaded slot values.
public struct VoicegroupCatalog: Sendable {
    public var groupArgs: [String]
    public var samples: [String]
    public var waves: [String]
    public var drumkits: [String]
    public var keysplits: [String: String]
    public var synths: [String]
    public var synthDefinitions: [String: VgSynthDesc]
    public var canMintSynths: Bool
    public var defaults: VoiceListAdsrDefaults

    public init(groupArgs: [String], samples: [String], waves: [String], drumkits: [String],
                keysplits: [String: String], synths: [String],
                synthDefinitions: [String: VgSynthDesc], canMintSynths: Bool,
                defaults: VoiceListAdsrDefaults) {
        self.groupArgs = groupArgs
        self.samples = samples
        self.waves = waves
        self.drumkits = drumkits
        self.keysplits = keysplits
        self.synths = synths
        self.synthDefinitions = synthDefinitions
        self.canMintSynths = canMintSynths
        self.defaults = defaults
    }
}
