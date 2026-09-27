import Foundation
import PorydawCore
import PorydawCoreCheckNative

private struct ExpectedCCDescriptor {
    let eventClass: Int64
    let lane: Int64
    let name: String
    let display: String
}

// This is the retained semantic specification. It is deliberately data-driven:
// production functions are never called while constructing an expected result.
private let expectedCCOverrides: [Int: ExpectedCCDescriptor] = [
    0x01: ExpectedCCDescriptor(eventClass: 2, lane: 0, name: "MOD", display: "Modulation"),
    0x05: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PORTAMENTO",
                               display: "Portamento"),
    0x07: ExpectedCCDescriptor(eventClass: 2, lane: 1, name: "VOL", display: "Volume"),
    0x0A: ExpectedCCDescriptor(eventClass: 2, lane: 2, name: "PAN", display: "Pan"),
    0x0C: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC",
                               display: "Memory op"),
    0x0D: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC op",
                               display: "Memory op select"),
    0x0E: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC p1",
                               display: "Memory op param 1"),
    0x0F: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC p2",
                               display: "Memory op param 2"),
    0x10: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC",
                               display: "Memory op"),
    0x11: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "Label",
                               display: "Loop label"),
    0x14: ExpectedCCDescriptor(eventClass: 2, lane: 3, name: "BENDR",
                               display: "Bend range"),
    0x15: ExpectedCCDescriptor(eventClass: 2, lane: 4, name: "LFOS",
                               display: "LFO speed"),
    0x16: ExpectedCCDescriptor(eventClass: 2, lane: 5, name: "MODT",
                               display: "LFO type"),
    0x17: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PWMC",
                               display: "Pulse-width pattern"),
    0x18: ExpectedCCDescriptor(eventClass: 2, lane: 6, name: "TUNE",
                               display: "Fine tune"),
    0x19: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PWMS",
                               display: "Pulse-width speed"),
    0x1A: ExpectedCCDescriptor(eventClass: 2, lane: 7, name: "LFODL",
                               display: "LFO delay"),
    0x1D: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "XCMD",
                               display: "Pseudo-echo"),
    0x1E: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "XCMD op",
                               display: "Pseudo-echo select"),
    0x1F: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "XCMD",
                               display: "Pseudo-echo"),
    0x21: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PRIO",
                               display: "Priority"),
    0x27: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PRIO",
                               display: "Priority"),
]

private let expectedExportedCCs: Set<Int> =
    [0x01, 0x07, 0x0A, 0x0C, 0x10, 0x11, 0x14, 0x15, 0x16, 0x18, 0x1A, 0x21, 0x27]
private let expectedLaneNames = [
    "Modulation", "Volume", "Pan", "Bend range", "LFO speed", "LFO type",
    "Fine tune", "LFO delay", "Pitch bend", "Echo volume", "Echo length", "Tempo",
]
private let expectedPitchNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
]
private let expectedVoiceNamesByLowBits = [
    "Sample", "Square 1", "Square 2", "Wave", "Noise", "Sample", "Sample", "Sample",
]
private let expectedVelocityNames = [
    "", "", "", "", "Square 1", "Square 2", "Programmable Wave", "Noise",
]
private let expectedTimeSignatureDenominators = [1, 2, 4, 8, 16, 32, 64, 64, 64, 64, 64]
private let expectedVelocityCeilings = [
    4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64,
    68, 72, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 120, 124, 127,
]
private let expectedPSGRepresentatives = [
    1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
]
private let expectedWaveRepresentatives = [1, 32, 64, 96, 127]
private let expectedPSGRanges: [(first: Int, last: Int)] = [
    (1, 8), (9, 16), (17, 24), (25, 32), (33, 40), (41, 48), (49, 56), (57, 64),
    (65, 72), (73, 80), (81, 88), (89, 96), (97, 104), (105, 112), (113, 120),
    (121, 127),
]
private let expectedWaveRanges: [(first: Int, last: Int)] =
    [(1, 16), (17, 48), (49, 80), (81, 112), (113, 127)]
private let expectedControllerDefaults: [Int: Int] = [
    0x01: 0, 0x05: 0, 0x07: 127, 0x0A: 64, 0x14: 2, 0x15: 22,
    0x16: 0, 0x17: 0, 0x18: 64, 0x19: 0, 0x1A: 0,
]
private let expectedDurationTable = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 24, 24, 24, 28, 28, 30, 30, 32, 32, 32, 32,
    36, 36, 36, 36, 40, 40, 42, 42, 44, 44, 44, 44, 48, 48, 48, 48,
    52, 52, 54, 54, 56, 56, 56, 56, 60, 60, 60, 60, 64, 64, 66, 66,
    68, 68, 68, 68, 72, 72, 72, 72, 76, 76, 78, 78, 80, 80, 80, 80,
    84, 84, 84, 84, 88, 88, 90, 90, 92, 92, 92, 92, 96,
]

private func expectedCCDescriptor(_ controller: Int) -> ExpectedCCDescriptor {
    expectedCCOverrides[controller] ??
        ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "CC", display: "Controller")
}

private func expectedCCValue(controller: Int, value: Int) -> String {
    if controller == 0x0A || controller == 0x18 {
        let offset = value - 64
        return "c_v\(value >= 64 ? "+" : "")\(offset)"
    }
    if controller == 0x16 {
        let names = ["Vibrato", "Tremolo", "Autopan"]
        if value < names.count { return names[value] }
    }
    return String(value)
}

private func expectedEffectiveVelocity(_ value: Int) -> Int {
    if value <= 0 { return 0 }
    for ceiling in expectedVelocityCeilings where value <= ceiling { return ceiling }
    return 127
}

private func expectedClampedVelocity(_ value: Int) -> Int {
    min(max(value, 1), 127)
}

private func expectedVelocityRanges(_ kind: Int) -> [(first: Int, last: Int)]? {
    if kind == 6 { return expectedWaveRanges }
    if (4...7).contains(kind) { return expectedPSGRanges }
    return nil
}

private func expectedVelocityRepresentatives(_ kind: Int) -> [Int]? {
    if kind == 6 { return expectedWaveRepresentatives }
    if (4...7).contains(kind) { return expectedPSGRepresentatives }
    return nil
}

private func expectedVelocityLevel(kind: Int, velocity: Int) -> Int {
    guard let ranges = expectedVelocityRanges(kind) else { return -1 }
    let effective = expectedEffectiveVelocity(expectedClampedVelocity(velocity))
    return ranges.firstIndex(where: { $0.first <= effective && effective <= $0.last })!
}

private func expectedDuration(_ duration: Int64, division: Int64,
                              extended: Bool, exact: Bool) -> Int64 {
    let clocks: Int64
    switch (division, extended) {
    case (0, _), (24, false): clocks = duration
    case (24, true): clocks = duration * 2
    case (48, false): clocks = duration / 2
    case (48, true): clocks = duration
    case (96, false): clocks = duration / 4
    case (96, true): clocks = duration / 2
    case (480, false): clocks = duration / 20
    case (480, true): clocks = duration / 10
    default: preconditionFailure("unexpected retained duration division \(division)")
    }
    let positive = max(clocks, 1)
    if exact || positive >= 96 { return positive }
    return Int64(expectedDurationTable[Int(positive)])
}

func independentExpectedValue(_ operation: CoreMidiOracleValueOp,
                                      _ a: Int64, _ b: Int64,
                                      _ c: Int64, _ d: Int64) -> Int64 {
    switch operation {
    case .ccClass: return expectedCCDescriptor(Int(a)).eventClass
    case .ccLane: return expectedCCDescriptor(Int(a)).lane
    case .ccExport: return expectedExportedCCs.contains(Int(a)) ? 0 : 1
    case .xcmdLane: return a == 9 ? 10 : 9
    case .effectiveVelocity: return Int64(expectedEffectiveVelocity(Int(a)))
    case .effectiveDuration:
        return expectedDuration(a, division: b, extended: c != 0, exact: d != 0)
    case .velocityIsPSG: return (4...7).contains(Int(a)) ? 1 : 0
    case .velocityCompatible:
        return (4...7).contains(Int(a)) && a == b ? 1 : 0
    case .velocityLevelCount:
        if a == 6 { return 5 }
        return (4...7).contains(Int(a)) ? 16 : 0
    case .velocityLevelRange:
        if let ranges = expectedVelocityRanges(Int(a)) {
            let level = min(max(Int(b), 0), ranges.count - 1)
            return Int64(ranges[level].first << 8 | ranges[level].last)
        }
        let velocity = expectedClampedVelocity(Int(b))
        return Int64(velocity << 8 | velocity)
    case .velocityLevel:
        return Int64(expectedVelocityLevel(kind: Int(a), velocity: Int(b)))
    case .velocityRepresentative:
        guard let representatives = expectedVelocityRepresentatives(Int(a)) else {
            return Int64(expectedClampedVelocity(Int(b)))
        }
        return Int64(representatives[min(max(Int(b), 0), representatives.count - 1)])
    case .velocityCanonicalize:
        guard let representatives = expectedVelocityRepresentatives(Int(a)) else {
            return Int64(expectedClampedVelocity(Int(b)))
        }
        return Int64(representatives[expectedVelocityLevel(kind: Int(a), velocity: Int(b))])
    case .velocityMoveLevels:
        let origin = expectedClampedVelocity(Int(b))
        guard let representatives = expectedVelocityRepresentatives(Int(a)) else {
            return Int64(expectedClampedVelocity(origin + Int(c)))
        }
        let originLevel = expectedVelocityLevel(kind: Int(a), velocity: origin)
        let target = min(max(originLevel + Int(c), 0), representatives.count - 1)
        return Int64(target == originLevel ? origin : representatives[target])
    case .controllerDefault:
        return Int64(expectedControllerDefaults[Int(a)] ?? -1)
    case .laneMinimum: return a == 0xFF ? -8192 : 0
    case .laneMaximum: return a == 0xFF ? 8191 : (a == 0x16 ? 2 : 127)
    case .laneCentered: return [0x0A, 0x18, 0xFF].contains(a) ? 1 : 0
    case .laneZoomable:
        return [0x0A, 0x16, 0x18, 0xFF].contains(a) ? 0 : 1
    case .hasEngineDefault: return a == 0x07 || a == 0x0A ? 1 : 0
    case .tempoFromBPM:
        let bpm = min(max(a, 20), 255)
        return (60_000_000 + bpm / 2) / bpm
    case .bpmFromTempo:
        let value = a == 0 ? 120.0 : 60_000_000.0 / Double(a)
        return Int64(bitPattern: value.bitPattern)
    case .clampTempo: return min(max(a, 235_294), 3_000_000)
    case .shiftTick:
        if b <= -a { return 0 }
        let headroom = 4_294_967_294 - a
        if b >= headroom { return 4_294_967_294 }
        return a + b
    case .tickFromDouble:
        let value = Double(bitPattern: UInt64(bitPattern: a))
        if !(value > 0) { return 0 }
        if !(value < 4_294_967_295.0) { return 4_294_967_294 }
        return Int64(value)
    case .trackCapacity: return 16
    case .noteIDAssigned: return a == 0 ? 0 : 1
    case .noteIDStorage: return 1
    }
}

func independentExpectedText(_ operation: CoreMidiOracleTextOp,
                                     _ a: Int64, _ b: Int64) -> String {
    switch operation {
    case .ccName: return expectedCCDescriptor(Int(a)).name
    case .ccDisplay: return expectedCCDescriptor(Int(a)).display
    case .laneName: return expectedLaneNames[Int(a)]
    case .ccValue: return expectedCCValue(controller: Int(a), value: Int(b))
    case .advancedCCLabel:
        let descriptor = expectedCCDescriptor(Int(a))
        if descriptor.name == "CC" { return "CC \(a) = \(b) (no m4a meaning)" }
        return "\(descriptor.name) \(expectedCCValue(controller: Int(a), value: Int(b)))"
    case .bend: return "\(a > 0 ? "+" : "")\(a)"
    case .voiceType:
        if a == 0x80 { return "Drumkit" }
        if a == 0x08 { return "Sample (fixed pitch)" }
        if a == 0x10 { return "Sample (reverse)" }
        return expectedVoiceNamesByLowBits[Int(a) & 0x07]
    case .keyName:
        let key = Int(a)
        return "\(expectedPitchNames[key % 12])\(key / 12 - 1)"
    case .timeSignature:
        return "\(a)/\(expectedTimeSignatureDenominators[Int(b)])"
    case .velocityName: return expectedVelocityNames[Int(a)]
    }
}
