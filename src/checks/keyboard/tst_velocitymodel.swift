import PorydawApp
import PorydawCore

private let velocityResolutionID = "velocity-model/VelocityModelTest::resolvesVoiceKinds"
private let velocityLevelsID = "velocity-model/VelocityModelTest::levelsCanonicalizeAndMove"

@MainActor
internal func runVelocityMapOracleChecks(_ report: CheckReport) {
    for kind in 0..<8 {
        let map = VelocityMap(voiceKind: VoiceKind(rawValue: kind) ?? .invalid)
        coreMidiExpectOracleValue(map.isPSG ? 1 : 0, .velocityIsPSG, Int64(kind),
                          row: "velocity-kind-\(kind)-is-psg", cppID: velocityResolutionID,
                          report: report)
        coreMidiExpectOracleValue(Int64(map.levelCount), .velocityLevelCount, Int64(kind),
                          row: "velocity-kind-\(kind)-count", cppID: velocityLevelsID,
                          report: report)
        coreMidiExpectOracleText(map.voiceName, .velocityName, Int64(kind),
                         row: "velocity-kind-\(kind)-name", cppID: velocityResolutionID,
                         report: report)
        for other in 0..<8 {
            let otherMap = VelocityMap(voiceKind: VoiceKind(rawValue: other) ?? .invalid)
            coreMidiExpectOracleValue(map.compatible(with: otherMap) ? 1 : 0, .velocityCompatible,
                              Int64(kind), Int64(other),
                              row: "velocity-kind-\(kind)-compatible-\(other)",
                              cppID: velocityResolutionID, report: report)
        }
        for level in -2...18 {
            let range = map.levelRange(level)
            let packed = Int64(range.first) << 8 | Int64(range.last)
            coreMidiExpectOracleValue(packed, .velocityLevelRange, Int64(kind), Int64(level),
                              row: "velocity-kind-\(kind)-range-\(level)",
                              cppID: velocityLevelsID, report: report)
            coreMidiExpectOracleValue(Int64(map.representative(level)), .velocityRepresentative,
                              Int64(kind), Int64(level),
                              row: "velocity-kind-\(kind)-representative-\(level)",
                              cppID: velocityLevelsID, report: report)
        }
        for velocity in -2...130 {
            coreMidiExpectOracleValue(Int64(map.level(of: velocity) ?? -1), .velocityLevel,
                              Int64(kind), Int64(velocity),
                              row: "velocity-kind-\(kind)-level-of-\(velocity)",
                              cppID: velocityLevelsID, report: report)
            coreMidiExpectOracleValue(Int64(map.canonicalize(velocity)), .velocityCanonicalize,
                              Int64(kind), Int64(velocity),
                              row: "velocity-kind-\(kind)-canonical-\(velocity)",
                              cppID: velocityLevelsID, report: report)
        }
        for origin in [0, 1, 8, 9, 60, 64, 65, 80, 95, 112, 127, 128] {
            for delta in -3...3 {
                let actual = Int64(map.moveLevels(from: UInt8(truncatingIfNeeded: origin),
                                                  by: delta))
                coreMidiExpectOracleValue(actual, .velocityMoveLevels, Int64(kind), Int64(origin),
                                  Int64(delta), 0,
                                  row: "velocity-kind-\(kind)-move-\(origin)-\(delta)",
                                  cppID: velocityLevelsID, report: report)
            }
        }
    }
    runVelocityAxisParityChecks(report)
    runVelocityGestureParityChecks(report)
    var childMacros = Array(repeating: Int32(-1), count: 128)
    childMacros[60] = BankVoiceMacro.keysplit
    childMacros[67] = BankVoiceMacro.programmableWave
    let nested = BankSlotView(kind: BankSlotKind.editable,
                              voice: BankVoice(macro: BankVoiceMacro.keysplitAll),
                              subvoiceMacros: childMacros)
    let slots = [BankSlotView(kind: BankSlotKind.editable,
                              voice: BankVoice(macro: BankVoiceMacro.keysplitAll)), nested]
    let invalid = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: 60)
    report.expect(!invalid.map.isPSG && invalid.status == .invalidSubvoice,
                  cppID: velocityResolutionID, message: "A067 invalid split child is not PSG")
    let nestedChild = VelocityContextPolicy.resolve(slot: 1, endTick: nil, slots: slots, key: 60)
    report.expect(!nestedChild.map.isPSG && nestedChild.status == .invalidSubvoice,
                  cppID: velocityResolutionID, message: "A068 nested split child is not PSG")
    let keyless = VelocityContextPolicy.resolve(slot: 1, endTick: nil, slots: slots)
    report.expect(!keyless.map.isPSG && keyless.status == .keysplitSubvoice,
                  cppID: velocityResolutionID, message: "A069 keyless split is not PSG")
    let wave = VelocityContextPolicy.resolve(slot: 1, endTick: nil, slots: slots, key: 67)
    report.expect(wave.map.isPSG && wave.status == .resolved,
                  cppID: velocityResolutionID, message: "A070 split wave child resolves PSG")
    report.expectEqual(expected: "Programmable Wave", actual: wave.map.voiceName,
                       cppID: velocityResolutionID, what: "A071 split child names Programmable Wave")

}
