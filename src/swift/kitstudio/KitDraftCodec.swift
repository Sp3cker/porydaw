import PorydawAppAudio
import PorydawSample
import PorydawVoicegroup

/// Pure conversion between editor ranges, store values and audition descriptions.
public enum KitDraftCodec {
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

    private static func isSample(_ voice: VgVoice) -> Bool {
        voice.macro == .directSound || voice.macro == .directSoundNoResample || voice.macro == .directSoundAlt
    }

    private static func voice(_ zone: KitZone, key _: Int, mode: KitMode) -> VgVoice? {
        // Every key in a zone plays at the root key; one slice maps to one key.
        return VgVoice(
            macro: zone.sampleMacro, key: zone.rootKey, pan: mode == .drumkit ? 0x40 + zone.pan / 2 : 0,
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
