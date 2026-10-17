import PorydawDocument
import PorydawKitStudio
import PorydawSample
import PorydawVoicegroup

/// Resolves committed mappings and audition assets without changing the current window.
@MainActor
enum KitEditLoader {
    struct LoadedKit {
        var name: String
        var location: VoicegroupLocation
        var tableName: String?
        var childCount: Int
        var mode: KitMode
        var zones: [KitZone]
        var samples: [String: ProcessedSample]
        var waves: [String: [UInt32]]
    }

    static func load(
        service: ProjectService, projectRoot: String, lease: ProjectBankLease, slot: Int, parent: BankVoice
    ) async throws -> LoadedKit {
        let kit = try await service.readKit(lease: lease, slot: slot)
        try Task.checkCancellation()
        guard kit.parent == parent else {
            throw ProjectServiceError.operationFailed("Split Studio: the selected voice changed while loading.")
        }
        let children = try kit.children.map { (voice: BankVoice?) -> VgVoice? in
            try voice.map(projectVoice)
        }
        let mode: KitMode = parent.macro == BankVoiceMacro.keysplitAll ? .drumkit : .keysplit
        guard mode != .keysplit || kit.table?.count == 128 else {
            throw ProjectServiceError.operationFailed("Split Studio: missing keysplit table.")
        }
        var samples: [String: ProcessedSample] = [:]
        var waves: [String: [UInt32]] = [:]
        for child in children {
            guard let voice = child else { continue }
            switch voice.macro {
            case .directSound, .directSoundNoResample, .directSoundAlt:
                if samples[voice.symbol] == nil,
                    let asset = try await service.sampleAsset(lease: lease, symbol: voice.symbol)
                {
                    var sample = ProcessedSample()
                    sample.s8 = asset.pcm
                    sample.freq = asset.frequency
                    sample.size = UInt32(asset.pcm.count)
                    sample.looped = asset.looped
                    sample.loopStart = UInt32(asset.loopStart)
                    samples[voice.symbol] = sample
                }
            case .progWave, .progWaveAlt:
                if waves[voice.symbol] == nil {
                    waves[voice.symbol] = try await service.progWaveWords(lease: lease, symbol: voice.symbol)
                }
            default: break
            }
            try Task.checkCancellation()
        }
        let locator = VoicegroupLocator(layout: ProjectLayout(projectRoot: projectRoot))
        guard let location = locator.locateSubgroup(symbol: Array(kit.subgroupSymbol.utf8)[...]) else {
            throw ProjectServiceError.operationFailed("Cannot locate \(kit.subgroupSymbol).")
        }
        let name =
            kit.subgroupSymbol.hasPrefix("voicegroup_")
            ? String(kit.subgroupSymbol.dropFirst(11)) : kit.subgroupSymbol
        return LoadedKit(
            name: name, location: location, tableName: kit.tableName,
            childCount: kit.children.lastIndex(where: { (voice: BankVoice?) -> Bool in voice != nil }).map { $0 + 1 }
                ?? 0,
            mode: mode, zones: KitDraftCodec.zones(children: children, mode: mode, table: kit.table),
            samples: samples, waves: waves)
    }
}
