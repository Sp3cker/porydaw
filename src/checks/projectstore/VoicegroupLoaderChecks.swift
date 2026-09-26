import Foundation
import PorydawProject
import PorydawProjectNative
import Synchronization

private let batchAssetCount = 16

private final class LoaderAdapter: Sendable {
    struct State {
        var requested: [String: Int] = [:]
        var populated = 0
        var released = 0
        var inFlight = 0
        var maxInFlight = 0
        var failureSuffix: String?
    }

    let root: URL
    let width: Int
    let state = Mutex(State())

    var failureSuffix: String? {
        get { state.withLock { $0.failureSuffix } }
        set { state.withLock { $0.failureSuffix = newValue } }
    }

    init(root: URL, width: Int = 4) {
        self.root = root
        self.width = width
    }

    func reset() {
        state.withLock { state in
            let suffix = state.failureSuffix
            state = State()
            state.failureSuffix = suffix
        }
    }

    func read(_ paths: UnsafePointer<UnsafePointer<CChar>?>, count: Int,
              out: UnsafeMutablePointer<VoicegroupFileBlob>, error: UnsafeMutablePointer<CChar>?,
              capacity: Int) -> Bool {
        let names = (0..<count).compactMap { paths[$0].map { String(cString: $0) } }
        guard names.count == count else { return false }
        state.withLock { state in
            for name in names { state.requested[name, default: 0] += 1 }
        }
        let fetched = Mutex(Array<Data?>(repeating: nil, count: count))
        let gateFailed = Mutex(false)
        for start in stride(from: 0, to: count, by: width) {
            let end = min(count, start + width)
            let gate = LoaderStartGate(count: end - start)
            let completed = DispatchGroup()
            for index in start..<end {
                completed.enter()
                Thread {
                    defer { completed.leave() }
                    self.state.withLock { state in
                        state.inFlight += 1
                        state.maxInFlight = max(state.maxInFlight, state.inFlight)
                    }
                    gate.arrive()
                    self.state.withLock { $0.inFlight -= 1 }
                    let name = names[index]
                    let path = name.hasPrefix("/") ? URL(filePath: name) : self.root.appendingPathComponent(name)
                    if let data = try? Data(contentsOf: path) {
                        fetched.withLock { $0[index] = data }
                    } else if FileManager.default.fileExists(atPath: path.path) {
                        gateFailed.withLock { $0 = true }
                    }
                }.start()
            }
            completed.wait()
        }
        let blobs = fetched.withLock { $0 }
        for (index, blob) in blobs.enumerated() {
            guard let blob else { continue }
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, blob.count))
            blob.withUnsafeBytes { buffer in
                if let base = buffer.baseAddress, blob.count > 0 {
                    bytes.initialize(from: base.assumingMemoryBound(to: UInt8.self), count: blob.count)
                }
            }
            out[index] = VoicegroupFileBlob(data: bytes, size: blob.count, found: true)
            state.withLock { $0.populated += 1 }
        }
        let failed = gateFailed.withLock { $0 } || names.contains { failureSuffix.map($0.contains) == true }
        if failed {
            let message = Array("injected batch transport failure".utf8)
            if let error, capacity > 0 {
                for index in 0..<min(capacity - 1, message.count) { error[index] = CChar(bitPattern: message[index]) }
                error[min(capacity - 1, message.count)] = 0
            }
        }
        return !failed
    }

    func release(_ blobs: UnsafeMutablePointer<VoicegroupFileBlob>, count: Int) {
        for index in 0..<count {
            if blobs[index].found {
                blobs[index].data?.deallocate()
                state.withLock { $0.released += 1 }
            }
            blobs[index] = VoicegroupFileBlob()
        }
    }

    var fileIo: VoicegroupFileIo {
        VoicegroupFileIo(user: Unmanaged.passUnretained(self).toOpaque(),
                         readBatch: loaderReadBatch, releaseBatch: loaderReleaseBatch)
    }
}

private final class LoaderStartGate: Sendable {
    private let count: Int
    private let remaining: Mutex<Int>
    private let ready = DispatchSemaphore(value: 0)

    init(count: Int) {
        self.count = count
        remaining = Mutex(count)
    }

    func arrive() {
        let last = remaining.withLock { remaining in
            remaining -= 1
            return remaining == 0
        }
        if last {
            for _ in 0..<count { ready.signal() }
        }
        ready.wait()
    }
}

private let loaderReadBatch: VoicegroupReadBatchFn = { user, paths, count, out, error, capacity in
    guard let user, let paths, let out else { return false }
    for index in 0..<count { out[index] = VoicegroupFileBlob() }
    let adapter = Unmanaged<LoaderAdapter>.fromOpaque(user).takeUnretainedValue()
    return adapter.read(paths, count: count, out: out, error: error, capacity: capacity)
}

private let loaderReleaseBatch: VoicegroupReleaseBatchFn = { user, blobs, count in
    guard let user, let blobs else { return }
    Unmanaged<LoaderAdapter>.fromOpaque(user).takeUnretainedValue().release(blobs, count: count)
}

private func loaderStage(_ root: URL) throws {
    let sample = root.appendingPathComponent("sound/direct_sound_samples/fixture_pluck.bin")
    var definitions = ""
    var group = "\t.align 2\nvoice_group check_batch\n"
    for index in 0..<batchAssetCount {
        let suffix = String(format: "%02d", index)
        let relative = "sound/direct_sound_samples/check_batch_\(suffix).bin"
        try FileManager.default.copyItem(at: sample, to: root.appendingPathComponent(relative))
        let symbol = "DirectSoundWaveData_check_batch_\(suffix)"
        definitions += "\(symbol)::\n\t.incbin \"\(relative)\"\n\n"
        group += "\tvoice_directsound 60, 0, \(symbol), \(255 - index * 2), \(128 + index * 2), \(200 - index * 5), \(64 + index)\n"
    }
    let sound = root.appendingPathComponent("sound/direct_sound_data.inc")
    try FileHandle(forWritingTo: sound).withHandle { try $0.seekToEnd(); try $0.write(contentsOf: Data(definitions.utf8)) }
    try Data(group.utf8).write(to: root.appendingPathComponent("sound/voicegroups/check_batch.inc"))
    let include = root.appendingPathComponent("sound/voice_groups.inc")
    try FileHandle(forWritingTo: include).withHandle {
        try $0.seekToEnd()
        try $0.write(contentsOf: Data("    .include \"sound/voicegroups/check_batch.inc\"\n".utf8))
    }
    try Data("\t.align 2\nvoice_group check_alias_kit, 60\n\tvoice_directsound 60, 0, DirectSoundWaveData_fixture_drum, 255, 80, 144, 40\n\tvoice_directsound 60, 0, DirectSoundWaveData_fixture_pluck, 240, 140, 176, 64\n".utf8)
        .write(to: root.appendingPathComponent("sound/voicegroups/check_alias_parts.inc"))
    try Data("\t.align 2\nvoice_group check_alias_host\n\tvoice_keysplit_all voicegroup_check_alias_kit\n".utf8)
        .write(to: root.appendingPathComponent("sound/voicegroups/check_alias_host.inc"))
}

private extension FileHandle {
    func withHandle(_ body: (FileHandle) throws -> Void) throws {
        defer { try? close() }
        try body(self)
    }
}

private func loaderBank(_ root: URL, _ name: String) -> UnsafeMutablePointer<LoadedVoiceGroup>? {
    root.path.withCString { path in name.withCString { voicegroup_load(path, $0, nil) } }
}

private func loaderContext(_ root: URL, _ adapter: LoaderAdapter) -> OpaquePointer? {
    var fileIo = adapter.fileIo
    return root.path.withCString { voicegroup_project_open($0, nil, &fileIo) }
}

private func loaderProjectBank(_ context: OpaquePointer, _ root: URL, _ name: String)
    -> UnsafeMutablePointer<LoadedVoiceGroup>? {
    root.appendingPathComponent("sound/voicegroups/\(name).inc").path.withCString { path in
        var target = VoicegroupTarget(filePath: path, sectionLabel: nil)
        return voicegroup_project_load(context, &target)
    }
}

private func loaderTone(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ slot: Int) -> ToneData {
    withUnsafePointer(to: &bank.pointee.voices) {
        $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[slot] }
    }
}

private func loaderBytes(_ pointer: UnsafeRawPointer?, _ count: Int) -> [UInt8]? {
    guard let pointer else { return nil }
    return Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: count))
}

private func loaderSameWave(_ lhs: UnsafeMutablePointer<WaveData>?, _ rhs: UnsafeMutablePointer<WaveData>?) -> Bool {
    if lhs == rhs { return true }
    if lhs == nil || rhs == nil { return false }
    guard let lhs, let rhs else { return false }
    let a = lhs.pointee, b = rhs.pointee
    return a.type == b.type && a.status == b.status && a.freq == b.freq &&
        a.loopStart == b.loopStart && a.size == b.size &&
        loaderBytes(a.data.map(UnsafeRawPointer.init), Int(a.size)) ==
        loaderBytes(b.data.map(UnsafeRawPointer.init), Int(b.size))
}

private func loaderSameTones(_ a: UnsafePointer<ToneData>?, _ b: UnsafePointer<ToneData>?, depth: Int) -> Bool {
    guard (a == nil) == (b == nil) else { return false }
    guard let a, let b else { return true }
    return (0..<128).allSatisfy { index in
        let x = a[index], y = b[index]
        guard x.type == y.type && x.key == y.key && x.length == y.length && x.panSweep == y.panSweep &&
                x.attack == y.attack && x.decay == y.decay && x.sustain == y.sustain && x.release == y.release else {
            return false
        }
        if x.type & UInt8(VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL) != 0 {
            guard loaderBytes(x.keySplitTable.map(UnsafeRawPointer.init), 128) ==
                    loaderBytes(y.keySplitTable.map(UnsafeRawPointer.init), 128) else { return false }
            return depth > 0 ? loaderSameTones(x.subGroup?.assumingMemoryBound(to: ToneData.self),
                                               y.subGroup?.assumingMemoryBound(to: ToneData.self), depth: depth - 1)
                : (x.subGroup == nil) == (y.subGroup == nil)
        }
        if x.type == UInt8(VOICE_PROGRAMMABLE_WAVE) || x.type == UInt8(VOICE_PROGRAMMABLE_WAVE_ALT) {
            return loaderBytes(x.wavePointer.map(UnsafeRawPointer.init), 16) ==
                loaderBytes(y.wavePointer.map(UnsafeRawPointer.init), 16)
        }
        if x.type & 0x07 == UInt8(VOICE_SQUARE_1) ||
            x.type & 0x07 == UInt8(VOICE_SQUARE_2) ||
            x.type & 0x07 == UInt8(VOICE_NOISE) {
            return x.wav == y.wav
        }
        return loaderSameWave(x.wav, y.wav)
    }
}

private func loaderSameBank(_ a: UnsafeMutablePointer<LoadedVoiceGroup>,
                            _ b: UnsafeMutablePointer<LoadedVoiceGroup>) -> Bool {
    let x = a.pointee, y = b.pointee
    guard x.waveDataCount == y.waveDataCount && x.progWaveCount == y.progWaveCount &&
            x.subGroupCount == y.subGroupCount && x.keySplitTableCount == y.keySplitTableCount else { return false }
    let namesEqual = withUnsafeBytes(of: x.voiceNames) { left in
        withUnsafeBytes(of: y.voiceNames) { right in left.elementsEqual(right) }
    }
    guard namesEqual else { return false }
    for index in 0..<Int(x.waveDataCount) where !loaderSameWave(x.waveDatas[index], y.waveDatas[index]) { return false }
    for index in 0..<Int(x.progWaveCount) where
        loaderBytes(x.progWaves[index].map(UnsafeRawPointer.init), 16) !=
        loaderBytes(y.progWaves[index].map(UnsafeRawPointer.init), 16) { return false }
    for index in 0..<Int(x.keySplitTableCount) where
        loaderBytes(x.keySplitTables[index].map(UnsafeRawPointer.init), 128) !=
        loaderBytes(y.keySplitTables[index].map(UnsafeRawPointer.init), 128) { return false }
    for index in 0..<Int(x.subGroupCount) where
        !loaderSameTones(x.subGroups[index].map { UnsafePointer($0) },
                         y.subGroups[index].map { UnsafePointer($0) }, depth: 3) {
        return false
    }
    return withUnsafePointer(to: &a.pointee.voices) { ap in
        withUnsafePointer(to: &b.pointee.voices) { bp in
            ap.withMemoryRebound(to: ToneData.self, capacity: 128) { aa in
                bp.withMemoryRebound(to: ToneData.self, capacity: 128) { bb in
                    loaderSameTones(aa, bb, depth: 3)
                }
            }
        }
    }
}

private func loaderSubgroupNames(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::subgroupNames"
    let entries: [(Int, Int, Int, String)] = [
        (8, Int(VOICE_KEYSPLIT), 0, ""), (8, Int(VOICE_KEYSPLIT), 1, "fixture_loop"),
        (8, Int(VOICE_KEYSPLIT), 2, "fixture_pulse"), (10, Int(VOICE_KEYSPLIT_ALL), 0, ""),
        (10, Int(VOICE_KEYSPLIT_ALL), 36, "fixture_drum"), (10, Int(VOICE_KEYSPLIT_ALL), 37, ""),
        (10, Int(VOICE_KEYSPLIT_ALL), 38, "fixture_pluck"),
        (11, Int(VOICE_KEYSPLIT_ALL), 36, "fixture_pluck"),
        (11, Int(VOICE_KEYSPLIT_ALL), 37, "fixture_saw"),
        (11, Int(VOICE_KEYSPLIT_ALL), 38, "fixture_drum")
    ]
    var allMatch = true
    var unnamed = true
    for (program, type, slot, expected) in entries {
        let tone = loaderTone(bank, program)
        guard Int(tone.type) == type, let subgroup = tone.subGroup?.assumingMemoryBound(to: ToneData.self),
              let names = voicegroup_subgroup_names(bank, subgroup),
              let actual = voicegroup_subgroup_slot_name(bank, subgroup, Int32(slot)) else {
            allMatch = false
            unnamed = false
            continue
        }
        let fromTable = withUnsafePointer(to: names[slot]) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(VG_VOICE_NAME_LEN)) { String(cString: $0) }
        }
        allMatch = allMatch && String(cString: actual) == expected && fromTable == expected
        if expected.isEmpty { unnamed = unnamed && actual.pointee == 0 }
    }
    report.expect(allMatch, cppID: cppID,
                  message: "keysplit and drumkit subgroups publish their per-slot display names")
    report.expect(unnamed, cppID: cppID,
                  message: "registered but unnamed subgroup slots are empty, not missing")
    let subgroup = loaderTone(bank, 8).subGroup?.assumingMemoryBound(to: ToneData.self)
    let invalid = withUnsafePointer(to: &bank.pointee.voices) { voices in
        voices.withMemoryRebound(to: ToneData.self, capacity: 128) { top in
            voicegroup_subgroup_names(nil, subgroup) == nil &&
                voicegroup_subgroup_names(bank, nil) == nil &&
                voicegroup_subgroup_names(bank, top) == nil &&
                voicegroup_subgroup_slot_name(nil, subgroup, 0) == nil &&
                voicegroup_subgroup_slot_name(bank, nil, 0) == nil &&
                voicegroup_subgroup_slot_name(bank, top, 0) == nil &&
                voicegroup_subgroup_slot_name(bank, subgroup, -1) == nil &&
                voicegroup_subgroup_slot_name(bank, subgroup, 128) == nil
        }
    }
    report.expect(invalid, cppID: cppID,
                  message: "subgroup name lookups reject null banks, null subgroups, unregistered subgroups and out-of-range slots")
}

internal func runVoicegroupLoaderChecks(_ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::parityAndWarmReuse"
    do {
        try withTempProjectCopy(prefix: "voicegroup-loader", stagedFile: "sound/voice_groups.inc") { root in
            try loaderStage(root)
            loaderParity(root, report)
            loaderAlias(root, report)
            loaderBatch(root, report)
            loaderTransport(root, report)
            let midi = root.appendingPathComponent("sound/songs/midi/mus_gym.mid")
            try FileManager.default.createDirectory(at: midi.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data([0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
                      0x4d, 0x54, 0x72, 0x6b, 0, 0, 0, 4, 0, 0xff, 0x2f, 0]).write(to: midi)
            loaderBench(root, report)
        }
    } catch {
        report.fail(cppID, "loader fixture or staging failed: \(error)")
    }
}

private func loaderParity(_ root: URL, _ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::parityAndWarmReuse"
    let adapter = LoaderAdapter(root: root)
    guard let context = loaderContext(root, adapter) else { report.fail(cppID, "context did not open"); return }
    defer { voicegroup_project_free(context) }
    var parity = true
    var warm = true
    func compareBank(_ name: String) -> Bool {
        guard let expected = loaderBank(root, name) else {
            report.fail(cppID, "one-shot \(name) did not load")
            return false
        }
        defer { voicegroup_free(expected) }
        guard let loaded = loaderProjectBank(context, root, name) else {
            report.fail(cppID, "context \(name) did not load")
            return false
        }
        parity = parity && loaderSameBank(loaded, expected)
        if name == "fixture_rich" { loaderSubgroupNames(loaded, report) }
        voicegroup_free(loaded)
        adapter.reset()
        guard let again = loaderProjectBank(context, root, name) else {
            report.fail(cppID, "warm \(name) did not load")
            return false
        }
        warm = warm && loaderSameBank(again, expected) &&
            ["direct_sound_data.inc", "programmable_wave_data.inc", "keysplit_tables.inc"].allSatisfy { part in
                !adapter.state.withLock { $0.requested.keys.contains(where: { $0.contains(part) }) }
            }
        voicegroup_free(again)
        return true
    }
    for name in ["fixture_rich", "check_batch"] {
        guard compareBank(name) else { return }
    }
    report.expect(parity, cppID: cppID,
                  message: "one-shot and context banks load the same voices, names, waves and subgroups")
    report.expect(warm, cppID: cppID,
                  message: "a warm context reload reuses the parsed maps without re-reading sound data")
    let samples = ["DirectSoundWaveData_fixture_loop"]
    let waves = ["ProgrammableWaveData_fixture_pulse"]
    let keys = ["fixture_keys"]
    let tables = ["keysplit_fixture"]
    func compare(_ body: (UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?,
                          UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?) -> Bool) -> Bool {
        samples[0].withCString { sample in waves[0].withCString { wave in
            keys[0].withCString { key in tables[0].withCString { table in
                var s: [UnsafePointer<CChar>?] = [sample]
                var w: [UnsafePointer<CChar>?] = [wave]
                var k: [UnsafePointer<CChar>?] = [key]
                var t: [UnsafePointer<CChar>?] = [table]
                return body(&s, &w, &k, &t)
            } }
        } }
    }
    let matched = root.path.withCString { path in
        compare { s, w, k, t in
            guard let one = voicegroup_load_samples(path, s, 1, w, 1, k, t, 1, nil) else { return false }
            defer { voicegroup_free_samples(one) }
            guard let other = voicegroup_project_load_samples(context, s, 1, w, 1, k, t, 1) else { return false }
            defer { voicegroup_free_samples(other) }
            let x = one.pointee, y = other.pointee
            return x.count == 1 && y.count == x.count && y.progWaveCount == x.progWaveCount &&
                y.keysplitCount == x.keysplitCount && x.waves[0] != nil &&
                loaderSameWave(x.waves[0], y.waves[0]) &&
                loaderBytes(x.progWaves[0].map(UnsafeRawPointer.init), 16) ==
                loaderBytes(y.progWaves[0].map(UnsafeRawPointer.init), 16) &&
                loaderBytes(x.keysplits[0].table.map(UnsafeRawPointer.init), 128) ==
                loaderBytes(y.keysplits[0].table.map(UnsafeRawPointer.init), 128) &&
                loaderSameTones(x.keysplits[0].subGroup.map { UnsafePointer($0) },
                                y.keysplits[0].subGroup.map { UnsafePointer($0) }, depth: 3)
        }
    }
    report.expect(matched, cppID: cppID,
                  message: "context and one-shot sample sets resolve identical waves, prog waves and keysplit tables")
}

private func loaderAlias(_ root: URL, _ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::declaredNameResolution"
    guard let host = loaderBank(root, "check_alias_host") else { report.fail(cppID, "alias host did not load"); return }
    defer { voicegroup_free(host) }
    let tone = loaderTone(host, 0)
    let kit = tone.subGroup?.assumingMemoryBound(to: ToneData.self)
    let names = [59, 60, 61, 62].map { slot -> String? in
        guard let raw = voicegroup_subgroup_slot_name(host, kit, Int32(slot)) else { return nil }
        return String(cString: raw)
    }
    report.expect(tone.type == UInt8(VOICE_KEYSPLIT_ALL) && kit != nil &&
                  names == ["", "fixture_drum", "fixture_pluck", ""], cppID: cppID,
                  message: "a declared voice_group name resolves through a mismatched file name")
    guard let direct = loaderBank(root, "check_alias_kit") else { report.fail(cppID, "declared kit did not load"); return }
    defer { voicegroup_free(direct) }
    report.expect(loaderTone(direct, 59).wav == nil && loaderTone(direct, 60).wav != nil &&
                  loaderTone(direct, 61).wav != nil && loaderTone(direct, 62).wav == nil, cppID: cppID,
                  message: "the declared kit loads top-level with its starting-note window")
}

private func loaderBatch(_ root: URL, _ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::batchAdapters"
    guard let expected = loaderBank(root, "check_batch") else { report.fail(cppID, "batch oracle did not load"); return }
    defer { voicegroup_free(expected) }
    func compareWidth(_ width: Int) -> Bool {
        let adapter = LoaderAdapter(root: root, width: width)
        guard let context = loaderContext(root, adapter) else {
            report.fail(cppID, "batch context did not open")
            return false
        }
        defer { voicegroup_project_free(context) }
        guard let loaded = loaderProjectBank(context, root, "check_batch") else {
            report.fail(cppID, "batch width \(width) did not load")
            return false
        }
        defer { voicegroup_free(loaded) }
        let state = adapter.state.withLock { $0 }
        report.expect(loaderSameBank(loaded, expected), cppID: cppID,
                      message: "serial and four-wide adapters preserve the bank")
        report.expect(state.maxInFlight == width, cppID: cppID,
                      message: "observed batch concurrency is exactly the adapter width")
        report.expect(state.populated > 0 && state.populated == state.released &&
                      state.requested.values.allSatisfy { $0 == 1 }, cppID: cppID,
                      message: "every populated blob is released and each path is requested once")
        report.expect((0..<batchAssetCount).allSatisfy { index in
            let name = String(format: "check_batch_%02d.bin", index)
            let path = root.appendingPathComponent("sound/direct_sound_samples").appendingPathComponent(name).path
            return state.requested[path] == 1
        }, cppID: cppID, message: "every staged batch asset is requested exactly once")
        return true
    }
    for width in [1, 4] {
        guard compareWidth(width) else { return }
    }
}

private func loaderTransport(_ root: URL, _ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::transportFailure"
    guard let expected = loaderBank(root, "check_batch") else { report.fail(cppID, "failure oracle did not load"); return }
    defer { voicegroup_free(expected) }
    let adapter = LoaderAdapter(root: root)
    adapter.failureSuffix = "check_batch_07.bin"
    guard let context = loaderContext(root, adapter) else { report.fail(cppID, "failure context did not open"); return }
    defer { voicegroup_project_free(context) }
    let failed = loaderProjectBank(context, root, "check_batch")
    if let failed { voicegroup_free(failed) }
    let counts = adapter.state.withLock { $0 }
    report.expect(failed == nil && counts.populated >= 1 && counts.populated == counts.released, cppID: cppID,
                  message: "a failed batch releases its partial blobs")
    adapter.failureSuffix = nil
    adapter.reset()
    let healed = loaderProjectBank(context, root, "check_batch")
    let matches = healed.map { loaderSameBank($0, expected) } == true
    if let healed { voicegroup_free(healed) }
    report.expect(matches, cppID: cppID,
                  message: "the context heals and loads after a failed batch")
}

private func loaderBench(_ root: URL, _ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLoaderChecks::benchGuards"
    do {
        let store = ProjectStore(projectRoot: root)
        let open = awaitValue { try await store.open() }
        let song = awaitValue { try await store.songMeta(label: "mus_gym") }
        guard case .success(let snapshot)? = open, case .success(let info)? = song else {
            report.fail(cppID, "bench project or mus_gym did not open"); return
        }
        report.expect(SongName(info.label) != nil, cppID: cppID,
                      message: "the bench song label resolves to a valid song name")
        report.expect(snapshot.isOpen && info.isPlayable, cppID: cppID,
                      message: "the project opens and locates a playable song")
        let argument = info.cfg.voicegroupArgument
        let first = awaitValue { try await store.loadBank(voicegroupArg: argument) }
        let warm = awaitValue { try await store.loadBank(voicegroupArg: argument) }
        guard case .success(let a)? = first, case .success(let b)? = warm else {
            report.fail(cppID, "bench bank did not load"); return
        }
        report.expect(a.bankToken == b.bankToken, cppID: cppID,
                      message: "a warm reload reuses the loaded bank identity")
    }
}
