import PorydawVoicegroup

/// One inclusive, non-overlapping key range in a kit mode view.
public struct KitZone: Equatable, Sendable {
    public var startKey: Int
    public var endKey: Int
    public var sampleName: String
    public var rootKey: Int
    public var pitched: Bool
    public var pan: Int
    public var adsr: (attack: Int, decay: Int, sustain: Int, release: Int)
    public var locked: Bool
    public var lockedVoice: VgVoice?
    public var sampleMacro: VgMacro

    public init(
        startKey: Int, endKey: Int, sampleName: String, rootKey: Int,
        pitched: Bool, pan: Int,
        adsr: (attack: Int, decay: Int, sustain: Int, release: Int),
        locked: Bool = false, lockedVoice: VgVoice? = nil,
        sampleMacro: VgMacro = .directSound
    ) {
        self.startKey = startKey
        self.endKey = endKey
        self.sampleName = sampleName
        self.rootKey = rootKey
        self.pitched = pitched
        self.pan = pan
        self.adsr = adsr
        self.locked = locked
        self.lockedVoice = lockedVoice
        self.sampleMacro = sampleMacro
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startKey == rhs.startKey && lhs.endKey == rhs.endKey
            && lhs.sampleName == rhs.sampleName && lhs.rootKey == rhs.rootKey
            && lhs.pitched == rhs.pitched && lhs.pan == rhs.pan
            && lhs.adsr == rhs.adsr && lhs.locked == rhs.locked
            && lhs.lockedVoice == rhs.lockedVoice && lhs.sampleMacro == rhs.sampleMacro
    }
}

/// The two independently retained kit editor views.
public enum KitMode: String, Sendable { case drumkit, keysplit }
