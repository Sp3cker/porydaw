public enum ScaleID: Int, CaseIterable, Sendable {
    case major
    case naturalMinor
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case locrian
    case harmonicMinor
    case melodicMinor
    case harmonicMajor
    case majorPentatonic
    case minorPentatonic
    case minorBlues
    case wholeTone
    case halfWholeDiminished
    case wholeHalfDiminished
    case dorianSharp4
    case phrygianDominant
    case lydianAugmented
    case lydianDominant
    case altered
    case eightToneSpanish
    case bhairav
    case hungarianMinor
    case hirajoshi
    case inSen
    case iwato
    case kumoi

    public static let scaleCount = 28
    public static let rootCount = 12
    public static let defaultScale: ScaleID = .major
    public static let defaultRoot = 0
    public static let displayOrder: [ScaleID] = allCases

    public var mask: UInt16 { Self.masks[rawValue] }
    public var displayName: String { Self.names[rawValue] }

    public static func rootDisplayName(_ root: Int) -> String {
        rootNames[pitchClass(root)]
    }

    public func isPitch(_ midiPitch: Int, root: Int) -> Bool {
        let interval = Self.pitchClass(Self.pitchClass(midiPitch) - Self.pitchClass(root))
        return mask & (UInt16(1) << interval) != 0
    }

    public func firstPitchAbove(_ midiPitch: Int, root: Int) -> Int {
        guard midiPitch < 127 else { return -1 }
        let first = midiPitch < 0 ? 0 : midiPitch + 1
        for pitch in first...127 {
            if isPitch(pitch, root: root) { return pitch }
        }
        return -1
    }

    public func firstPitchBelow(_ midiPitch: Int, root: Int) -> Int {
        guard midiPitch > 0 else { return -1 }
        let first = midiPitch > 127 ? 127 : midiPitch - 1
        for pitch in stride(from: first, through: 0, by: -1) {
            if isPitch(pitch, root: root) { return pitch }
        }
        return -1
    }

    public func pitch(_ midiPitch: Int, steps: Int, root: Int) -> Int {
        guard midiPitch >= 0 && midiPitch <= 127 else { return -1 }
        var current = midiPitch
        var remaining = steps
        while remaining > 0 {
            current = firstPitchAbove(current, root: root)
            guard current >= 0 else { return -1 }
            remaining -= 1
        }
        while remaining < 0 {
            current = firstPitchBelow(current, root: root)
            guard current >= 0 else { return -1 }
            remaining += 1
        }
        return current
    }

    public static func resolveDiatonicDestinations(
        scale: ScaleID, root: Int, sources: [UInt8], steps: [Int], dests: inout [UInt8]
    ) -> Bool {
        guard sources.count == steps.count && sources.count == dests.count else { return false }
        let count = sources.count
        guard count > 0 else { return true }
        var movingDown = true
        for step in steps {
            if step > 0 {
                movingDown = false
                break
            }
        }
        if !movingDown {
            var previous = -1
            for i in 0..<count {
                if i > 0 && sources[i] == sources[i - 1] {
                    dests[i] = dests[i - 1]
                    continue
                }
                var destination = scale.pitch(Int(sources[i]), steps: steps[i], root: root)
                if destination < 0 {
                    fillRejected(&dests)
                    return false
                }
                if previous >= 0 && destination <= previous {
                    destination = scale.firstPitchAbove(previous, root: root)
                }
                if destination < 0 {
                    fillRejected(&dests)
                    return false
                }
                dests[i] = UInt8(destination)
                previous = destination
            }
            return true
        }
        var previous = 128
        for i in stride(from: count - 1, through: 0, by: -1) {
            if !(i > 0 && sources[i] == sources[i - 1]) {
                var destination = scale.pitch(Int(sources[i]), steps: steps[i], root: root)
                if destination < 0 {
                    fillRejected(&dests)
                    return false
                }
                if destination >= previous {
                    destination = scale.firstPitchBelow(previous, root: root)
                }
                if destination < 0 {
                    fillRejected(&dests)
                    return false
                }
                var lastDuplicate = i
                while lastDuplicate + 1 < count && sources[lastDuplicate + 1] == sources[i] {
                    lastDuplicate += 1
                }
                for duplicate in i...lastDuplicate {
                    dests[duplicate] = UInt8(destination)
                }
                previous = destination
            }
        }
        return true
    }

    private static func pitchClass(_ pitch: Int) -> Int {
        ((pitch % rootCount) + rootCount) % rootCount
    }

    private static func fillRejected(_ dests: inout [UInt8]) {
        for i in dests.indices { dests[i] = UInt8(0xFF) }
    }

    private static let masks: [UInt16] = [
        0xAB5, 0x5AD, 0x6AD, 0x5AB, 0xAD5, 0x6B5, 0x56B, 0x9AD,
        0xAAD, 0x9B5, 0x295, 0x4A9, 0x4E9, 0x555, 0x6DB, 0xB6D,
        0x6CD, 0x5B3, 0xB55, 0x6D5, 0x55B, 0x57B, 0x9B3, 0x9CD,
        0x18D, 0x4A3, 0x463, 0x28D,
    ]

    private static let names = [
        "Major",
        "Natural Minor",
        "Dorian",
        "Phrygian",
        "Lydian",
        "Mixolydian",
        "Locrian",
        "Harmonic Minor",
        "Melodic Minor",
        "Harmonic Major",
        "Major Pentatonic",
        "Minor Pentatonic",
        "Minor Blues",
        "Whole Tone",
        "Half-Whole Diminished",
        "Whole-Half Diminished",
        "Dorian #4",
        "Phrygian Dominant",
        "Lydian Augmented",
        "Lydian Dominant",
        "Altered (Super Locrian)",
        "8-Tone Spanish",
        "Bhairav",
        "Hungarian Minor",
        "Hirajoshi",
        "In-Sen",
        "Iwato",
        "Kumoi",
    ]

    private static let rootNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]
}
