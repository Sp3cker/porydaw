import Foundation

private let midiNoteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

public enum M4aLane: Int, CaseIterable, Sendable {
    case modulation
    case volume
    case pan
    case bendRange
    case lfoSpeed
    case lfoType
    case fineTune
    case lfoDelay
    case pitchBend
    case echoVolume
    case echoLength
    case tempo
}

public enum M4aEventClass: Int, Sendable {
    case note
    case voice
    case audibleLane
    case advanced
    case tempo
}

public enum M4aExportSupport: Int, Sendable {
    case supported
    case notExported
}

public struct M4aCCInfo: Equatable, Sendable {
    public let eventClass: M4aEventClass
    public let lane: M4aLane
    public let name: String
    public let display: String

    public init(eventClass: M4aEventClass, lane: M4aLane, name: String, display: String) {
        self.eventClass = eventClass
        self.lane = lane
        self.name = name
        self.display = display
    }
}

public enum VoiceKind: Int, CaseIterable, Sendable {
    case unresolved
    case invalid
    case keyless
    case directSound
    case square1
    case square2
    case wave
    case noise
}

public struct VelocityLevelRange: Equatable, Sendable {
    public let first: UInt8
    public let last: UInt8

    public init(first: UInt8 = 1, last: UInt8 = 127) {
        self.first = first
        self.last = last
    }
}

public struct VelocityMap: Equatable, Sendable {
    public let voiceKind: VoiceKind

    public init(voiceKind: VoiceKind) {
        self.voiceKind = voiceKind
    }

    public var isPSG: Bool {
        switch voiceKind {
        case .square1, .square2, .wave, .noise: return true
        default: return false
        }
    }

    public func compatible(with other: VelocityMap) -> Bool {
        isPSG && other.isPSG && voiceKind == other.voiceKind
    }

    public var voiceName: String {
        switch voiceKind {
        case .square1: return "Square 1"
        case .square2: return "Square 2"
        case .wave: return "Programmable Wave"
        case .noise: return "Noise"
        default: return ""
        }
    }

    public var levelCount: Int {
        guard isPSG else { return 0 }
        return voiceKind == .wave ? Self.waveRepresentatives.count : Self.psgRepresentatives.count
    }

    public func levelRange(_ requestedLevel: Int) -> VelocityLevelRange {
        guard isPSG else {
            let velocity = clampVelocity(requestedLevel)
            return VelocityLevelRange(first: velocity, last: velocity)
        }
        let highest = levelCount - 1
        let level = min(max(requestedLevel, 0), highest)
        if voiceKind == .wave { return Self.waveRanges[level] }
        return VelocityLevelRange(first: UInt8(level == 0 ? 1 : level * 8 + 1),
                                  last: UInt8(level == highest ? 127 : (level + 1) * 8))
    }

    public func level(of storedVelocity: Int) -> Int? {
        guard isPSG else { return nil }
        let effective = mid2agbEffectiveVelocity(Int(clampVelocity(storedVelocity)))
        let hardwareLevel = (effective - 1) / 8
        guard voiceKind == .wave else { return hardwareLevel }
        switch hardwareLevel {
        case ...1: return 0
        case ...5: return 1
        case ...9: return 2
        case ...13: return 3
        default: return 4
        }
    }

    public func representative(_ requestedLevel: Int) -> UInt8 {
        guard isPSG else { return clampVelocity(requestedLevel) }
        let values = voiceKind == .wave ? Self.waveRepresentatives : Self.psgRepresentatives
        return values[min(max(requestedLevel, 0), values.count - 1)]
    }

    public func canonicalize(_ proposedVelocity: Int) -> UInt8 {
        let proposed = clampVelocity(proposedVelocity)
        guard let level = level(of: Int(proposed)) else { return proposed }
        return representative(level)
    }

    public func moveLevels(from exactOrigin: UInt8, by delta: Int) -> UInt8 {
        let origin = clampVelocity(Int(exactOrigin))
        guard isPSG, let originLevel = level(of: Int(origin)) else {
            return clampVelocity(Int(origin) + delta)
        }
        let target = min(max(originLevel + delta, 0), levelCount - 1)
        return target == originLevel ? origin : representative(target)
    }

    private static let psgRepresentatives: [UInt8] = [
        1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
    ]
    private static let waveRepresentatives: [UInt8] = [1, 32, 64, 96, 127]
    private static let waveRanges: [VelocityLevelRange] = [
        VelocityLevelRange(first: 1, last: 16),
        VelocityLevelRange(first: 17, last: 48),
        VelocityLevelRange(first: 49, last: 80),
        VelocityLevelRange(first: 81, last: 112),
        VelocityLevelRange(first: 113, last: 127),
    ]
}

public func m4aClassifyCC(_ controller: UInt8) -> M4aCCInfo {
    switch controller {
    case 0x01: return M4aCCInfo(eventClass: .audibleLane, lane: .modulation,
                               name: "MOD", display: "Modulation")
    case 0x07: return M4aCCInfo(eventClass: .audibleLane, lane: .volume,
                               name: "VOL", display: "Volume")
    case 0x0A: return M4aCCInfo(eventClass: .audibleLane, lane: .pan,
                               name: "PAN", display: "Pan")
    case 0x14: return M4aCCInfo(eventClass: .audibleLane, lane: .bendRange,
                               name: "BENDR", display: "Bend range")
    case 0x15: return M4aCCInfo(eventClass: .audibleLane, lane: .lfoSpeed,
                               name: "LFOS", display: "LFO speed")
    case 0x16: return M4aCCInfo(eventClass: .audibleLane, lane: .lfoType,
                               name: "MODT", display: "LFO type")
    case 0x18: return M4aCCInfo(eventClass: .audibleLane, lane: .fineTune,
                               name: "TUNE", display: "Fine tune")
    case 0x1A: return M4aCCInfo(eventClass: .audibleLane, lane: .lfoDelay,
                               name: "LFODL", display: "LFO delay")
    case 0x05: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "PORTAMENTO", display: "Portamento")
    case 0x17: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "PWMC", display: "Pulse-width pattern")
    case 0x19: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "PWMS", display: "Pulse-width speed")
    case 0x0C, 0x10: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                                     name: "MEMACC", display: "Memory op")
    case 0x0D: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "MEMACC op", display: "Memory op select")
    case 0x0E: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "MEMACC p1", display: "Memory op param 1")
    case 0x0F: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "MEMACC p2", display: "Memory op param 2")
    case 0x11: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "Label", display: "Loop label")
    case 0x1D, 0x1F: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                                     name: "XCMD", display: "Pseudo-echo")
    case 0x1E: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                               name: "XCMD op", display: "Pseudo-echo select")
    case 0x21, 0x27: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                                     name: "PRIO", display: "Priority")
    default: return M4aCCInfo(eventClass: .advanced, lane: .modulation,
                             name: "CC", display: "Controller")
    }
}

// This audited subset is intentionally adjacent to `m4aClassifyCC`: event
// classification does not imply that the bundled exporter emits the CC.
public func m4aExportSupport(_ controller: UInt8) -> M4aExportSupport {
    switch controller {
    case 0x01, 0x07, 0x0A, 0x0C, 0x10, 0x11, 0x14, 0x15, 0x16, 0x18, 0x1A, 0x21, 0x27:
        return .supported
    default:
        return .notExported
    }
}

public func m4aLane(forXCMDSelector selector: UInt8) -> M4aLane {
    switch selector {
    case 0x08: return .echoVolume
    case 0x09: return .echoLength
    default: return .echoVolume
    }
}

public func m4aLaneName(_ lane: M4aLane) -> String {
    switch lane {
    case .modulation: return "Modulation"
    case .volume: return "Volume"
    case .pan: return "Pan"
    case .bendRange: return "Bend range"
    case .lfoSpeed: return "LFO speed"
    case .lfoType: return "LFO type"
    case .fineTune: return "Fine tune"
    case .lfoDelay: return "LFO delay"
    case .pitchBend: return "Pitch bend"
    case .echoVolume: return "Echo volume"
    case .echoLength: return "Echo length"
    case .tempo: return "Tempo"
    }
}

public func m4aFormatCCValue(controller: UInt8, value: UInt8) -> String {
    switch controller {
    case 0x0A, 0x18:
        let offset = Int(value) - 64
        return "c_v\(value >= 64 ? "+" : "")\(offset)"
    case 0x16:
        switch value {
        case 0: return "Vibrato"
        case 1: return "Tremolo"
        case 2: return "Autopan"
        default: return String(value)
        }
    default:
        return String(value)
    }
}

public func m4aFormatBend(_ bend14: Int) -> String {
    "\(bend14 > 0 ? "+" : "")\(bend14)"
}

public func m4aAdvancedCCLabel(controller: UInt8, value: UInt8) -> String {
    let info = m4aClassifyCC(controller)
    if info.name == "CC" { return "CC \(controller) = \(value) (no m4a meaning)" }
    return "\(info.name) \(m4aFormatCCValue(controller: controller, value: value))"
}

public func m4aVoiceTypeName(_ type: UInt8) -> String {
    let voiceKeysplitAll: UInt8 = 0x80
    let voiceDirectSoundNoResample: UInt8 = 0x08
    let voiceDirectSoundAlternate: UInt8 = 0x10
    if type == voiceKeysplitAll { return "Drumkit" }
    if type == voiceDirectSoundNoResample { return "Sample (fixed pitch)" }
    if type == voiceDirectSoundAlternate { return "Sample (reverse)" }
    switch type & 0x07 {
    case 0x01: return "Square 1"
    case 0x02: return "Square 2"
    case 0x03: return "Wave"
    case 0x04: return "Noise"
    default: return "Sample"
    }
}

public func midiKeyName(_ key: Int) -> String {
    var octave = key / 12
    var pitchClass = key % 12
    if pitchClass < 0 {
        pitchClass += 12
        octave -= 1
    }
    return "\(midiNoteNames[pitchClass])\(octave - 1)"
}

public func midiTimeSignatureLabel(numerator: Int, denominatorPowerOfTwo: Int) -> String {
    "\(numerator)/\(1 << min(denominatorPowerOfTwo, 6))"
}

public func clampVelocity(_ velocity: Int) -> UInt8 {
    UInt8(min(max(velocity, 1), 127))
}

public func mid2agbEffectiveVelocity(_ velocity: Int) -> Int {
    guard velocity > 0 else { return 0 }
    return min(((velocity + 3) / 4) * 4, 127)
}

public func mid2agbEffectiveDuration(_ durationTicks: Int64, division: UInt32,
                                     extendedClocks: Bool, exactGate: Bool) -> Int {
    let clocksPerBeat: Int64 = extendedClocks ? 48 : 24
    var duration = division == 0 ? durationTicks : clocksPerBeat * durationTicks / Int64(division)
    if duration <= 0 { duration = 1 }
    if !exactGate && duration < 96 { duration = Int64(durationTable[Int(duration)]) }
    return Int(duration)
}

private let durationTable: [UInt8] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 24, 24, 24, 28, 28, 30, 30, 32, 32, 32, 32, 36, 36, 36, 36,
    40, 40, 42, 42, 44, 44, 44, 44, 48, 48, 48, 48, 52, 52, 54, 54, 56, 56, 56, 56,
    60, 60, 60, 60, 64, 64, 66, 66, 68, 68, 68, 68, 72, 72, 72, 72, 76, 76, 78, 78,
    80, 80, 80, 80, 84, 84, 84, 84, 88, 88, 90, 90, 92, 92, 92, 92, 96,
]
