import PorydawAppAudio
import PorydawSample
import PorydawVoicegroup

/// Pure conversion between editor ranges, store values and audition descriptions.
public enum KitDraftCodec {
    // The decoded value of kitBlankChildLine; identical in both mode views.
    private static let blank = kitBlankChildVoice

    public static func drumkitZones(children: [VgVoice?]) -> [KitZone] {
        var zones: [KitZone] = []
        var index = 0
        let count = min(children.count, 128)
        while index < count {
            guard let voice = assigned(children[index]) else {
                index += 1
                continue
            }
            let start = index
            var pitched = false
            index += 1
            if isSample(voice) {
                var step: Int?
                while index < count, let next = assigned(children[index]), sameParams(voice, next) {
                    let previousKey = children[index - 1]?.key ?? voice.key
                    let difference = next.key - previousKey
                    guard difference == 0 || difference == 1,
                        step == nil || step == difference
                    else { break }
                    step = difference
                    index += 1
                }
                pitched = step == 1
            } else {
                while index < count, assigned(children[index]) == voice { index += 1 }
            }
            zones.append(zone(voice, start: start, end: index - 1, pitched: pitched, mode: .drumkit))
        }
        return zones
    }

    public static func keysplitZones(children: [VgVoice?], table: KeysplitTable) -> [KitZone] {
        var zones: [KitZone] = []
        var key = 0
        let end = min(128, table.table.count)
        while key < end {
            let start = key
            let ordinal = Int(table.table[key])
            key += 1
            while key < end, Int(table.table[key]) == ordinal { key += 1 }
            guard ordinal < children.count, let voice = assigned(children[ordinal]) else { continue }
            zones.append(zone(voice, start: start, end: key - 1, pitched: false, mode: .keysplit))
        }
        return zones
    }

    public static func children(from zones: [KitZone], mode: KitMode) -> [VgVoice?] {
        let sorted = ordered(zones)
        switch mode {
        case .drumkit:
            var children = [VgVoice?](repeating: nil, count: 128)
            for zone in sorted {
                for key in zone.startKey...zone.endKey {
                    children[key] = voice(zone, key: key, mode: mode)
                }
            }
            return children
        case .keysplit:
            var children = sorted.map { voice($0, key: $0.startKey, mode: mode) }
            if hasGaps(sorted) { children.append(nil) }
            return children
        }
    }

    public static func table(from zones: [KitZone], name: String) -> KeysplitTable {
        let sorted = ordered(zones)
        let sentinel = hasGaps(sorted) ? UInt8(sorted.count) : 0
        var bytes = [UInt8](repeating: sentinel, count: 128)
        for (ordinal, zone) in sorted.enumerated() {
            for key in zone.startKey...zone.endKey { bytes[key] = UInt8(ordinal) }
        }
        return KeysplitTable(name: name, startingNote: 0, maxNote: 128, table: bytes)
    }

    public static func auditionTone(
        draft: KitDraft.Snapshot, mode: KitMode, key: Int,
        samples: [String: ProcessedSample], progWaves: [String: [UInt32]]
    ) -> KitAuditionTone? {
        let zones = mode == .drumkit ? draft.drumkitZones : draft.keysplitZones
        guard zones.contains(where: { $0.startKey <= key && key <= $0.endKey }) else { return nil }
        let voices = children(from: zones, mode: mode)
        let children: [KitAuditionTone.Child] = voices.map { voice in
            guard let voice else { return silentChild }
            if isSample(voice) {
                guard let sample = samples[voice.symbol] else { return silentChild }
                return .sample(
                    pcm: sample.s8, frequency: sample.freq, key: UInt8(voice.key),
                    panSweep: mode == .drumkit ? UInt8(0x80 | voice.pan) : 0,
                    adsr: AudioADSR(
                        attack: UInt8(voice.attack), decay: UInt8(voice.decay),
                        sustain: UInt8(voice.sustain), release: UInt8(voice.release)),
                    kind: Int(vgMacroVoiceType(voice.macro)), looped: sample.looped,
                    loopStart: Int(sample.loopStart))
            }
            return .psg(
                KitAuditionPsg(
                    kind: Int(voice.macro.rawValue), key: voice.key, pan: voice.pan,
                    sweep: voice.sweep, duty: voice.duty, period: voice.period,
                    attack: voice.attack, decay: voice.decay, sustain: voice.sustain,
                    release: voice.release, progWave: progWaves[voice.symbol]))
        }
        return KitAuditionTone(
            mode: mode == .drumkit ? .drumkit : .keysplit, children: children,
            splitTable: mode == .keysplit ? table(from: zones, name: "").table : nil)
    }

    private static var silentChild: KitAuditionTone.Child {
        .sample(
            pcm: [], frequency: 0, key: 60, panSweep: 0, adsr: AudioADSR(),
            kind: 0, looped: false, loopStart: 0)
    }

    private static func assigned(_ voice: VgVoice?) -> VgVoice? {
        voice == blank ? nil : voice
    }

    private static func isSample(_ voice: VgVoice) -> Bool {
        voice.macro == .directSound || voice.macro == .directSoundNoResample || voice.macro == .directSoundAlt
    }

    private static func sameParams(_ lhs: VgVoice, _ rhs: VgVoice) -> Bool {
        guard isSample(rhs) else { return false }
        var adjusted = rhs
        adjusted.key = lhs.key
        return adjusted == lhs
    }

    private static func zone(_ voice: VgVoice, start: Int, end: Int, pitched: Bool, mode: KitMode) -> KitZone {
        let pan = mode == .drumkit && voice.pan != 0 ? ((0x80 | voice.pan) - 0xC0) * 2 : 0
        return KitZone(
            startKey: start, endKey: end, sampleName: voice.symbol, rootKey: voice.key,
            pitched: pitched, pan: pan,
            adsr: (voice.attack, voice.decay, voice.sustain, voice.release),
            locked: !isSample(voice), lockedVoice: isSample(voice) ? nil : voice,
            sampleMacro: isSample(voice) ? voice.macro : .directSound)
    }

    private static func voice(_ zone: KitZone, key: Int, mode: KitMode) -> VgVoice? {
        if zone.locked { return zone.lockedVoice }
        let childKey = zone.rootKey + (mode == .drumkit && zone.pitched ? key - zone.startKey : 0)
        return VgVoice(
            macro: zone.sampleMacro, key: childKey, pan: mode == .drumkit ? 0x40 + zone.pan / 2 : 0,
            symbol: zone.sampleName, attack: zone.adsr.attack, decay: zone.adsr.decay,
            sustain: zone.adsr.sustain, release: zone.adsr.release)
    }

    private static func ordered(_ zones: [KitZone]) -> [KitZone] {
        var previousStart = -1
        for zone in zones {
            if zone.startKey < previousStart { return zones.sorted { $0.startKey < $1.startKey } }
            previousStart = zone.startKey
        }
        return zones
    }

    private static func hasGaps(_ sorted: [KitZone]) -> Bool {
        var next = 0
        for zone in sorted {
            if zone.startKey != next { return true }
            next = zone.endKey + 1
        }
        return next != 128
    }
}
