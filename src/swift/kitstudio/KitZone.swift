import PorydawVoicegroup

/// One inclusive, non-overlapping key range in a kit mode view.
public struct KitZone: Equatable, Sendable {
    public var startKey: Int
    public var endKey: Int
    public var sampleName: String
    public var rootKey: Int
    public var pan: Int
    public var adsr: (attack: Int, decay: Int, sustain: Int, release: Int)
    public var sampleMacro: VgMacro

    public init(
        startKey: Int, endKey: Int, sampleName: String, rootKey: Int,
        pan: Int,
        adsr: (attack: Int, decay: Int, sustain: Int, release: Int),
        sampleMacro: VgMacro = .directSound
    ) {
        self.startKey = startKey
        self.endKey = endKey
        self.sampleName = sampleName
        self.rootKey = rootKey
        self.pan = pan
        self.adsr = adsr
        self.sampleMacro = sampleMacro
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startKey == rhs.startKey && lhs.endKey == rhs.endKey
            && lhs.sampleName == rhs.sampleName && lhs.rootKey == rhs.rootKey
            && lhs.pan == rhs.pan
            && lhs.adsr == rhs.adsr && lhs.sampleMacro == rhs.sampleMacro
    }
}

/// The two independently retained kit editor views.
public enum KitMode: String, Sendable { case drumkit, keysplit }
