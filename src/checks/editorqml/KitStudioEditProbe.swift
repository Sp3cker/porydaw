import PorydawDocument
import PorydawKitStudio
import PorydawVoicegroup
import QtBridge

@MainActor
@QtBridgeable
public final class KitStudioEditProbe: QmlInstantiableStatus {
    public var busy: Bool = false
    public var error: String = ""
    public var verified: Bool = false
    private var original: KitEditValue?
    private var task: Task<Void, Never>?

    public init() {}
    public func componentComplete() {}

    public func prepareFixture(root: String) -> Bool {
        let source = VoicegroupSource()
        var failure: String?
        let location = VoicegroupLocation(
            filePath: root + "/sound/voicegroups/fixture_drums_a.inc", sectionLabel: "fixture_drums_a")
        guard source.open(location: location, error: &failure), var voice = source.voiceAt(slot: 36) else {
            error = failure ?? "Cannot prepare odd-pan drumkit fixture."
            return false
        }
        voice.pan = 1
        guard source.setVoice(slot: 36, voice: voice),
            source.setVoice(
                slot: 38,
                voice: VgVoice(
                    macro: .progWave, key: 60, symbol: "ProgrammableWaveData_fixture_pulse",
                    attack: 2, decay: 3, sustain: 12, release: 4))
        else {
            error = "Cannot prepare programmable-wave drumkit fixture."
            return false
        }
        do { return try source.save() } catch {
            self.error = String(describing: error)
            return false
        }
    }

    public func capture(root: String, voicegroup: String, slot: Int) {
        task?.cancel()
        busy = true
        error = ""
        verified = false
        original = nil
        task = Task { [weak self] in
            let service = ProjectService()
            defer { if !Task.isCancelled { self?.task = nil } }
            do {
                try await service.open(root: root)
                let bank = try await service.loadBank(voicegroupArg: voicegroup)
                let kit = try await service.readKit(lease: bank.lease, slot: slot)
                try Task.checkCancellation()
                self?.original = kit
            } catch {
                if !Task.isCancelled { self?.error = String(describing: error) }
            }
            await service.close()
            guard !Task.isCancelled else { return }
            self?.busy = false
        }
    }

    public func verifySaved(
        root: String, firstKey: Int, lastKey: Int, rootKey: Int, removedFirstKey: Int, removedLastKey: Int
    ) {
        task?.cancel()
        guard let original else {
            busy = false
            verified = false
            error = "Capture the original kit before verifying save-back."
            return
        }
        busy = true
        error = ""
        task = Task { [weak self] in
            let service = ProjectService()
            do {
                try await service.open(root: root)
                let bank = try await service.loadBank(voicegroupArg: original.voicegroup)
                let saved = try await service.readKit(lease: bank.lease, slot: original.slot)
                try Task.checkCancellation()
                var matches =
                    saved.parent == original.parent && saved.subgroupSymbol == original.subgroupSymbol
                    && saved.tableName == original.tableName
                    && (removedFirstKey >= 0 || saved.table == original.table)
                for key in 0..<128 {
                    let oldIndex = original.table.map { Int($0[key]) } ?? key
                    let newIndex = saved.table.map { Int($0[key]) } ?? key
                    var expected = original.children[oldIndex]
                    if (firstKey...lastKey).contains(key) { expected?.key = Int32(rootKey) }
                    if removedFirstKey >= 0 && (removedFirstKey...removedLastKey).contains(key) { expected = nil }
                    let actual = saved.children[newIndex]
                    // Blank materialization changes source layout, not the playable mapping.
                    if expected == nil {
                        let blank = try actual.map(projectVoice) == kitBlankChildVoice
                        matches = matches && (actual == nil || blank)
                    } else {
                        matches = matches && actual == expected
                    }
                }
                if removedFirstKey >= 0 {
                    let activeCount = saved.table.map { Int($0.max() ?? 0) + 1 } ?? 128
                    for child in saved.children.dropFirst(activeCount) {
                        let blank = try child.map(projectVoice) == kitBlankChildVoice
                        matches = matches && (child == nil || blank)
                    }
                }
                self?.verified = matches
                if !matches { self?.error = "ProjectService save-back changed a parent, routing name or child voice." }
            } catch {
                if !Task.isCancelled { self?.error = String(describing: error) }
            }
            await service.close()
            guard !Task.isCancelled else { return }
            self?.busy = false
            self?.task = nil
        }
    }
}
