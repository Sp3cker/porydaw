import Foundation
import PorydawVoicegroupNative

@testable import PorydawVoicegroup

private func bankDecodeParity(
    _ cache: WaveCache, path: String, format: WaveFormat, _ report: CheckReport
) throws {
    let check = report.scoped(cppID: "voicegroup/BankOwnershipChecks::decode/\(format)")
    let data = try ProjectFileStore.read(path)
    var hardFailure = false
    let reference = data.withUnsafeBytes { bytes -> UnsafeMutablePointer<WaveData>? in
        let source = bytes.bindMemory(to: UInt8.self)
        return path.withCString { path in
            switch format {
            case .wav:
                return vg_asset_decode_wav(source.baseAddress, source.count, path, &hardFailure)
            case .aiff:
                return vg_asset_decode_aiff(source.baseAddress, source.count, path, &hardFailure)
            case .bin:
                return vg_asset_decode_bin(source.baseAddress, source.count, path, &hardFailure)
            }
        }
    }
    guard let reference else {
        check.fail("reference decoder did not decode the valid sample; hardFailure=\(hardFailure)")
        return
    }
    defer { free(reference) }
    guard let wave = try cache.wave(absolutePath: path, format: format) else {
        check.fail("WaveCache did not decode the valid sample")
        return
    }
    withExtendedLifetime(cache) {
        let actual = wave.pointee
        let expected = reference.pointee
        check.expectEqual(expected: expected.type, actual: actual.type, what: "type matches native decoder")
        check.expectEqual(expected: expected.status, actual: actual.status, what: "status matches native decoder")
        check.expectEqual(expected: expected.freq, actual: actual.freq, what: "frequency matches native decoder")
        check.expectEqual(
            expected: expected.loopStart, actual: actual.loopStart, what: "loop start matches native decoder")
        check.expectEqual(expected: expected.size, actual: actual.size, what: "size matches native decoder")
        guard actual.size == expected.size else { return }
        guard let actualBytes = actual.data, let expectedBytes = expected.data else {
            check.fail("decoded wave has no PCM pointer")
            return
        }
        let count = Int(expected.size) + 1
        check.expect(
            memcmp(actualBytes, expectedBytes, count) == 0,
            message: "PCM bytes and guard byte match native decoder")
        let payload = UnsafeMutableRawPointer(wave).advanced(by: MemoryLayout<WaveData>.size)
        check.expect(
            UnsafeMutableRawPointer(actualBytes) == payload,
            message: "header and PCM occupy one native allocation")
    }
    check.expectEqual(
        expected: wave, actual: try cache.wave(absolutePath: path, format: format),
        what: "wave preserves its exact path cache key")
    let warm = try cache.wave(absolutePath: path, format: format)
    check.expect(warm == wave, message: "second decode returns the identical object")
    let samePathOtherFormat = try cache.wave(absolutePath: path, format: .wav)
    check.expect(samePathOtherFormat == wave, message: "cache identity depends only on the exact path")
}

private func bankDecoderChecks(_ root: URL, _ report: CheckReport) throws {
    let cache = WaveCache()
    let loop = root.appendingPathComponent("sound/direct_sound_samples/fixture_loop.bin").path
    try bankDecodeParity(cache, path: loop, format: .bin, report)

    let wav = root.appendingPathComponent("sound/direct_sound_samples/check_bank.wav")
    try Data([
        0x52, 0x49, 0x46, 0x46, 40, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
        0x66, 0x6D, 0x74, 0x20, 16, 0, 0, 0, 1, 0, 1, 0,
        0x40, 0x1F, 0, 0, 0x40, 0x1F, 0, 0, 1, 0, 8, 0,
        0x64, 0x61, 0x74, 0x61, 3, 0, 0, 0, 0, 128, 255, 0,
    ]).write(to: wav)
    try bankDecodeParity(cache, path: wav.path, format: .wav, report)

    let aiff = root.appendingPathComponent("sound/direct_sound_samples/check_bank.aif")
    try Data([
        0x46, 0x4F, 0x52, 0x4D, 0, 0, 0, 50, 0x41, 0x49, 0x46, 0x46,
        0x43, 0x4F, 0x4D, 0x4D, 0, 0, 0, 18, 0, 1, 0, 0, 0, 3, 0, 8,
        0x40, 0x0B, 0xFA, 0, 0, 0, 0, 0, 0, 0,
        0x53, 0x53, 0x4E, 0x44, 0, 0, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0,
        128, 0, 127, 0,
    ]).write(to: aiff)
    try bankDecodeParity(cache, path: aiff.path, format: .aiff, report)

    let check = report.scoped(cppID: "voicegroup/BankOwnershipChecks::softMisses")
    let missing = root.appendingPathComponent("sound/direct_sound_samples/check_bank_missing.bin")
    let garbage = root.appendingPathComponent("sound/direct_sound_samples/check_bank_garbage.bin")
    try Data([1, 2, 3]).write(to: garbage)
    for format in [WaveFormat.bin, .wav, .aiff] {
        let absent = try cache.wave(absolutePath: missing.path, format: format)
        check.expect(absent == nil, message: "missing \(format) path returns nil without throwing")
        let invalid = try cache.wave(absolutePath: garbage.path, format: format)
        check.expect(invalid == nil, message: "three-byte \(format) input is a soft miss")
    }
    let missingProg = try cache.prog(absolutePath: missing.path)
    let invalidProg = try cache.prog(absolutePath: garbage.path)
    check.expect(missingProg == nil, message: "missing programmable wave returns nil without throwing")
    check.expect(invalidProg == nil, message: "three-byte programmable wave is a soft miss")
    let sampleBytes = try ProjectFileStore.read(loop)
    try sampleBytes.write(to: garbage)
    try sampleBytes.write(to: missing)
    let recovered = try cache.wave(absolutePath: garbage.path, format: .bin)
    let appeared = try cache.wave(absolutePath: missing.path, format: .bin)
    check.expect(recovered != nil, message: "malformed input is not cached")
    check.expect(appeared != nil, message: "missing input is not cached")
    let distinctPath = root.path + "/sound/direct_sound_samples/./fixture_loop.bin"
    let canonical = try cache.wave(absolutePath: loop, format: .bin)
    let distinct = try cache.wave(absolutePath: distinctPath, format: .bin)
    check.expect(
        distinct != nil && distinct != canonical, message: "different path strings remain distinct cache keys")

    let hard = report.scoped(cppID: "voicegroup/BankOwnershipChecks::hardReadFailure")
    do {
        _ = try cache.wave(absolutePath: root.path, format: .bin)
        hard.fail("reading an existing directory as a wave must throw")
    } catch let error as WaveDecodeError {
        hard.expectEqual(expected: root.path, actual: error.path, what: "wave hard-read error carries the path")
    }
    do {
        _ = try cache.prog(absolutePath: root.path)
        hard.fail("reading an existing directory as a programmable wave must throw")
    } catch let error as WaveDecodeError {
        hard.expectEqual(expected: root.path, actual: error.path, what: "prog hard-read error carries the path")
    }
}

private func bankSynthChecks(_ report: CheckReport) {
    let check = report.scoped(cppID: "voicegroup/BankOwnershipChecks::synth")
    let cache = WaveCache()
    let descriptor: [UInt8] = [0x80, 1, 0x30, 6, 0x10, 0x20]
    let symbol = Array("check_bank".utf8)[...]
    guard let wave = cache.synth(symbol: symbol, descriptor: descriptor) else {
        check.fail("synth allocation failed")
        return
    }
    withExtendedLifetime(cache) {
        let header = wave.pointee
        check.expectEqual(expected: UInt16(0), actual: header.type, what: "synth type is zero")
        check.expectEqual(expected: UInt16(0x4000), actual: header.status, what: "synth status is 0x4000")
        check.expectEqual(
            expected: UInt32(0x0105_8920), actual: header.freq, what: "synth frequency matches native constant")
        check.expectEqual(expected: UInt32(0), actual: header.loopStart, what: "synth loop start is zero")
        check.expectEqual(expected: UInt32(0), actual: header.size, what: "synth size stays zero")
        guard let data = header.data else {
            check.fail("synth has no payload")
            return
        }
        let payload = UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: payload, count: 17))
        let expected = descriptor + Array(repeating: UInt8(0), count: 11)
        check.expectEqual(expected: expected, actual: bytes, what: "six descriptor bytes precede eleven zero bytes")
        check.expect(
            UnsafeRawPointer(data) == UnsafeRawPointer(wave).advanced(by: MemoryLayout<WaveData>.size),
            message: "synth payload immediately follows its header")
    }
    check.expectEqual(
        expected: wave, actual: cache.synth(symbol: symbol, descriptor: descriptor),
        what: "synth symbol cache key resolves its allocation")
    let warm = cache.synth(symbol: symbol, descriptor: [0x80, 2, 0, 0, 0, 0])
    check.expect(warm == wave, message: "a synth cache hit returns the original symbol's object")
    let bank = Bank.make(cache: cache)
    bank.register(wave: wave)
    cache.removeAll()
    let fresh = cache.synth(symbol: symbol, descriptor: descriptor)
    check.expect(fresh != nil && fresh != wave, message: "cache eviction permits a new synth allocation")
    withExtendedLifetime(bank) {}
}

private func bankNameChecks(
    _ names: UnsafeMutablePointer<CChar>, nameAt: (Int) -> String, _ check: CheckReport.Scoped
) {
    let nameLength = Int(VG_VOICE_NAME_LEN)
    let zeroed = UnsafeRawBufferPointer(start: names, count: 128 * nameLength)
    check.expect(zeroed.allSatisfy { $0 == 0 }, message: "all 128 display-name slots are calloc-zeroed")
    check.expectEqual(expected: "", actual: nameAt(127), what: "unnamed final slot is empty")
    for (index, byte) in "  loop  \0ignored".utf8.enumerated() { names[index] = CChar(bitPattern: byte) }
    check.expectEqual(expected: "  loop  ", actual: nameAt(0), what: "name stops at NUL and preserves whitespace")
    for index in 0..<nameLength { names[nameLength + index] = 65 }
    names[2 * nameLength] = 66
    check.expectEqual(
        expected: String(repeating: "A", count: nameLength), actual: nameAt(1),
        what: "nonterminated name is bounded to one slot")
}

private func bankBufferChecks(_ report: CheckReport) {
    let check = report.scoped(cppID: "voicegroup/BankOwnershipChecks::buffers")
    let bank = Bank.make()
    let subgroup = SubBank.make()
    let zeroedBank = UnsafeRawBufferPointer(start: bank.voices, count: 128 * MemoryLayout<ToneData>.stride)
    let zeroedSubgroup = UnsafeRawBufferPointer(start: subgroup.voices, count: 128 * MemoryLayout<ToneData>.stride)
    check.expect(zeroedBank.allSatisfy { $0 == 0 }, message: "all 128 bank tones are calloc-zeroed")
    check.expect(zeroedSubgroup.allSatisfy { $0 == 0 }, message: "all 128 sub-bank tones are calloc-zeroed")
    bankNameChecks(
        bank.names, nameAt: bank.name(at:), report.scoped(cppID: "voicegroup/BankOwnershipChecks::bankNames"))
    bankNameChecks(
        subgroup.names, nameAt: subgroup.name(at:), report.scoped(cppID: "voicegroup/BankOwnershipChecks::subBankNames")
    )

    var source = (0..<128).map { UInt8($0) }
    let copied = bank.registerTable(source.span)
    source.withUnsafeBufferPointer { bytes in
        check.expect(UnsafePointer(copied) != bytes.baseAddress, message: "registered table owns a distinct allocation")
    }
    source[0] = 255
    check.expect(
        (0..<128).allSatisfy { copied[$0] == UInt8($0) }, message: "registered table copies all bytes independently")
    bank.voices[0].keySplitTable = copied
    check.expect(bank.voices[0].keySplitTable == copied, message: "bank tone borrows the registered table")

    bank.register(subBank: subgroup)
    var tone = ToneData()
    check.expect(bank.subBank(for: tone) == nil, message: "nil subgroup has no registered sub-bank")
    tone.subGroup = UnsafeMutableRawPointer(subgroup.voices)
    check.expect(bank.subBank(for: tone) === subgroup, message: "sub-bank lookup matches voices pointer identity")
    let unrelated = SubBank.make()
    tone.subGroup = UnsafeMutableRawPointer(unrelated.voices)
    check.expect(bank.subBank(for: tone) == nil, message: "unregistered subgroup pointer does not match")
}

private func bankLifetimeChecks(_ root: URL, _ report: CheckReport) throws {
    let check = report.scoped(cppID: "voicegroup/BankOwnershipChecks::lifetime")
    let path = root.appendingPathComponent("sound/direct_sound_samples/fixture_loop.bin").path
    let cache = WaveCache()
    var firstBank: Bank? = Bank.make(cache: cache)
    var lastBank: Bank? = Bank.make(cache: cache)
    var liveWave: UnsafeMutablePointer<WaveData>?
    do {
        guard let wave = try cache.wave(absolutePath: path, format: .bin) else {
            check.fail("lifetime sample did not decode")
            return
        }
        liveWave = wave
        firstBank?.register(wave: wave)
        firstBank?.register(wave: wave)
        lastBank?.register(wave: wave)
        firstBank?.voices[0].wav = wave
        lastBank?.voices[0].wav = wave
        check.expectEqual(
            expected: 2, actual: cache.references(to: wave), what: "wave registration is identity-idempotent")
    }
    cache.removeAll()
    withExtendedLifetime((firstBank, lastBank)) {
        check.expect(
            liveWave.flatMap { cache.references(to: $0) } == 2,
            message: "live banks retain the wave after cache eviction")
    }
    firstBank = nil
    withExtendedLifetime(lastBank) {
        check.expect(
            liveWave.flatMap { cache.references(to: $0) } == 1,
            message: "a second bank continues to retain the shared wave")
    }
    guard let liveWave else { return }
    let freedWave = parityObservesFree(UnsafeRawPointer(liveWave)) { lastBank = nil }
    check.expect(freedWave, message: "dropping the last bank deallocates the evicted wave")

    var owner: Bank? = Bank.make(cache: cache)
    var liveProg: UnsafeMutablePointer<UInt32>?
    weak var liveSubBank: SubBank?
    do {
        guard let prog = try cache.prog(absolutePath: path), let second = try cache.prog(absolutePath: path) else {
            check.fail("programmable wave did not decode")
            return
        }
        check.expect(
            prog != second, message: "programmable waves are freshly allocated, never cached"
        )
        defer { free(second) }
        check.expect(prog != second, message: "programmable source path decodes into a fresh allocation")
        let bytes = try ProjectFileStore.read(path)
        let sameBytes = bytes.withUnsafeBytes { source -> Bool in
            guard let base = source.baseAddress else { return false }
            return memcmp(prog, base, 16) == 0
        }
        check.expect(sameBytes, message: "programmable decoder copies exactly the first sixteen input bytes")
        liveProg = prog
        owner?.register(prog: prog)
        owner?.register(prog: prog)
        owner?.voices[0].wavePointer = prog
        check.expect(
            owner?.voices[0].wavePointer == prog, message: "bank tone borrows the registered programmable wave")
        let subgroup = SubBank.make()
        liveSubBank = subgroup
        owner?.register(subBank: subgroup)
        owner?.voices[1].subGroup = UnsafeMutableRawPointer(subgroup.voices)
    }
    withExtendedLifetime(owner) {
        check.expect(liveProg != nil && liveSubBank != nil, message: "bank retains programmable waves and sub-banks")
    }
    guard let liveProg else { return }
    let freedProg = parityObservesFree(UnsafeRawPointer(liveProg)) { owner = nil }
    check.expect(freedProg, message: "bank destruction releases its programmable wave")
    check.expect(liveSubBank == nil, message: "bank destruction releases its sub-bank buffers")
}

public func runBankOwnershipSuite(_ report: CheckReport) {
    do {
        try withTempProjectCopy(prefix: "bank-ownership", stagedFile: "sound/direct_sound_samples/fixture_loop.bin") {
            root in
            try bankDecoderChecks(root, report)
            bankSynthChecks(report)
            bankBufferChecks(report)
            try bankLifetimeChecks(root, report)
        }
    } catch {
        report.fail("voicegroup/BankOwnershipChecks::suite", "bank ownership checks failed: \(error)")
    }
}
