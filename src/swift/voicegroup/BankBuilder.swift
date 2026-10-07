import Foundation
import PorydawVoicegroupNative

/// Project-scoped resolution inputs shared by bank loads and picker previews.
public struct BankBuildInputs {
    public var layout: ProjectLayout
    public var soundMap: SoundDataMap
    public var progMap: ProgWaveMap
    public var keysplits: KeysplitTables
    public var cache: WaveCache
    public var locator: VoicegroupLocator
    public var textProvider: (VoicegroupLocation, _ contiguousFill: Bool, _ noSubRecurse: Bool) throws -> VoicegroupText

    public init(
        layout: ProjectLayout, soundMap: SoundDataMap, progMap: ProgWaveMap,
        keysplits: KeysplitTables, cache: WaveCache, locator: VoicegroupLocator,
        textProvider:
            @escaping (VoicegroupLocation, _ contiguousFill: Bool, _ noSubRecurse: Bool) throws -> VoicegroupText
    ) {
        _ = layout.ensuringDeepScan()
        self.layout = layout
        self.soundMap = soundMap
        self.progMap = progMap
        self.keysplits = keysplits
        self.cache = cache
        self.locator = locator
        self.textProvider = textProvider
    }
}

public enum BankBuildError: Error {
    case hardFailure(String)
    case cycle(VoicegroupLocation)
    case unreadable(String)
}

/// Resolves parsed slots into one owning bank using the native loader's rules.
public struct BankBuilder {
    private let inputs: BankBuildInputs

    public init(inputs: BankBuildInputs) { self.inputs = inputs }

    /// Builds and retains every pointed-to allocation before publishing the bank.
    /// - Throws: `BankBuildError` on a hard asset, text, table, or cycle failure.
    public func build(_ text: borrowing VoicegroupText, at location: VoicegroupLocation) throws -> Bank {
        var state = BuildState(bank: Bank.make(cache: inputs.cache), keysplits: inputs.keysplits)
        state.activeLocations[0] = location
        state.activeCount = 1
        do {
            try fill(text, at: location, voices: state.bank.voices, names: state.bank.names, state: &state)
            return state.bank
        } catch let error as WaveDecodeError {
            throw BankBuildError.hardFailure(error.path)
        } catch let error as KeysplitParseError {
            throw BankBuildError.hardFailure("\(error.file):\(error.line): \(error.reason)")
        }
    }

    /// Resolves synths, mapped WAV/AIF/BIN candidates, then the serial directory fallback.
    /// - Throws: `BankBuildError.hardFailure` for decoder or path failures.
    // Successful decode-to-register paths are infallible; the cache owns the allocation until registration.
    public func resolveSample(symbol: ArraySlice<UInt8>) throws -> UnsafeMutablePointer<WaveData>? {
        do {
            switch inputs.soundMap[symbol] {
            case .synth(let descriptor):
                guard let wave = inputs.cache.synth(symbol: symbol, descriptor: descriptor) else {
                    throw BankBuildError.hardFailure("Unable to allocate synth \(symbol)")
                }
                return wave
            case .sample(let relativePath):
                let pathBytes = relativePath.utf8
                let path = pathBytes.span
                if relativePath.hasSuffix(".bin") {
                    if let wave = try inputs.cache.wave(
                        directory: inputs.layout.projectRoot, relativePath: path, format: .wav,
                        suffix: ".wav", removingLast: 4)
                    {
                        return wave
                    }
                    if let wave = try inputs.cache.wave(
                        directory: inputs.layout.projectRoot, relativePath: path, format: .aiff,
                        suffix: ".aif", removingLast: 4)
                    {
                        return wave
                    }
                }
                return try inputs.cache.wave(directory: inputs.layout.projectRoot, relativePath: path, format: .bin)
            case nil:
                for directory in inputs.layout.ensuringDeepScan().sampleDirectories {
                    if let wave = try inputs.cache.wave(
                        directory: directory, relativePath: symbol.span, format: .wav,
                        suffix: ".wav", truncate: true)
                    {
                        return wave
                    }
                    if let wave = try inputs.cache.wave(
                        directory: directory, relativePath: symbol.span, format: .aiff,
                        suffix: ".aif", truncate: true)
                    {
                        return wave
                    }
                }
                return nil
            }
        } catch let error as WaveDecodeError {
            throw BankBuildError.hardFailure(error.path)
        }
    }

    /// Resolves a fresh programmable-wave allocation, with mapped misses remaining soft.
    /// - Throws: `BankBuildError.hardFailure` for decoder or path failures.
    public func resolveProgWave(symbol: ArraySlice<UInt8>) throws -> UnsafeMutablePointer<UInt32>? {
        guard let relativePath = inputs.progMap[symbol] else { return nil }
        do {
            return try inputs.cache.prog(absolutePath: absolutePath(relativePath))
        } catch let error as WaveDecodeError {
            throw BankBuildError.hardFailure(error.path)
        }
    }

    private func resolveCry(symbol: ArraySlice<UInt8>) throws -> UnsafeMutablePointer<WaveData>? {
        guard case .sample(let relativePath) = inputs.soundMap[symbol] else { return nil }
        let pathBytes = relativePath.utf8
        return try inputs.cache.wave(directory: inputs.layout.projectRoot, relativePath: pathBytes.span, format: .bin)
    }

    private struct BuildState {
        let bank: Bank
        var keysplits: KeysplitTables
        var scannedKeysplits = false
        var activeLocations = InlineArray<32, VoicegroupLocation?>(repeating: nil)
        var activeCount = 0
    }

    private func fill(
        _ text: borrowing VoicegroupText, at location: VoicegroupLocation,
        voices: UnsafeMutablePointer<ToneData>, names: UnsafeMutablePointer<CChar>, state: inout BuildState
    ) throws {
        var endIndex = try write(text, voices: voices, names: names, startIndex: 0, state: &state)
        guard text.continuesIntoIncludedFile, endIndex > 0 else { return }
        var path = location.filePath
        for _ in 0..<128 {
            guard endIndex < 128, let nextPath = inputs.locator.nextIncludedFile(after: path) else { break }
            let nextLocation = VoicegroupLocation(filePath: nextPath, sectionLabel: "")
            // C parses only the remaining capacity; an overlong symbol past it would throw here.
            let successor = try providedText(at: nextLocation, contiguousFill: false, noSubRecurse: true)
            let nextIndex = try write(successor, voices: voices, names: names, startIndex: endIndex, state: &state)
            guard nextIndex > endIndex else { break }
            endIndex = nextIndex
            path = nextPath
        }
    }

    private func write(
        _ text: borrowing VoicegroupText, voices: UnsafeMutablePointer<ToneData>, names: UnsafeMutablePointer<CChar>,
        startIndex: Int, state: inout BuildState
    ) throws -> Int {
        let slots = text.voices.span
        for index in 0..<(128 - startIndex) {
            guard let descriptor = slots[index] else { continue }
            let slot = startIndex + index
            var tone = ToneData()
            tone.type = descriptor.type
            tone.key = descriptor.key
            tone.panSweep = descriptor.panSweep
            tone.attack = descriptor.attack
            tone.decay = descriptor.decay
            tone.sustain = descriptor.sustain
            tone.release = descriptor.release
            copyName(descriptor.displayName, to: names.advanced(by: slot * Int(VG_VOICE_NAME_LEN)))
            switch descriptor.type {
            case UInt8(VOICE_KEYSPLIT), UInt8(VOICE_KEYSPLIT_ALL):
                if !descriptor.suppressSubgroup {
                    let subgroup = try resolveSubgroup(symbol: descriptor.symbol, state: &state)
                    tone.subGroup = subgroup.map { UnsafeMutableRawPointer($0.voices) }
                }
                if descriptor.type == UInt8(VOICE_KEYSPLIT),
                    let table = try keysplitTable(named: descriptor.tableSymbol, state: &state)
                {
                    tone.keySplitTable = state.bank.registerTable(table.table.span)
                }
            case UInt8(VOICE_CRY), UInt8(VOICE_CRY_REVERSE):
                if let wave = try resolveCry(symbol: descriptor.symbol) {
                    state.bank.register(wave: wave)
                    tone.wav = wave
                }
            case UInt8(VOICE_DIRECTSOUND), UInt8(VOICE_DIRECTSOUND_NO_RESAMPLE), UInt8(VOICE_DIRECTSOUND_ALT):
                if let wave = try resolveSample(symbol: descriptor.symbol) {
                    state.bank.register(wave: wave)
                    tone.wav = wave
                }
            case UInt8(VOICE_PROGRAMMABLE_WAVE), UInt8(VOICE_PROGRAMMABLE_WAVE_ALT):
                if let wave = try resolveProgWave(symbol: descriptor.symbol) {
                    state.bank.register(prog: wave)
                    tone.wavePointer = wave
                }
            default:
                tone.wavePointer = UnsafeMutablePointer<UInt32>(bitPattern: Int(descriptor.wavePointerBits))
            }
            var destination = MutableSpan(_unsafeStart: voices, count: 128)
            destination[slot] = tone
        }
        return min(128, startIndex + text.endIndex)
    }

    private func resolveSubgroup(symbol: ArraySlice<UInt8>, state: inout BuildState) throws -> SubBank? {
        guard let location = inputs.locator.locateSubgroup(symbol: symbol) else { return nil }
        for index in 0..<state.activeCount {
            guard state.activeLocations[index] != location else { throw BankBuildError.cycle(location) }
        }
        guard state.activeCount < 32 else {
            throw BankBuildError.hardFailure("Active voicegroup location stack is full")
        }
        state.activeLocations[state.activeCount] = location
        state.activeCount += 1
        defer {
            state.activeCount -= 1
            state.activeLocations[state.activeCount] = nil
        }
        let text = try providedText(at: location, contiguousFill: true, noSubRecurse: false)
        let subgroup = SubBank.make()
        state.bank.register(subBank: subgroup)
        try fill(text, at: location, voices: subgroup.voices, names: subgroup.names, state: &state)
        return subgroup
    }

    private func keysplitTable(named symbol: ArraySlice<UInt8>, state: inout BuildState) throws -> KeysplitTable? {
        if let table = state.keysplits.table(named: symbol) { return table }
        if !state.scannedKeysplits {
            let files = inputs.layout.ensuringDeepScan().keysplitTableFiles
            let additionalFiles = files.filter { !inputs.layout.keysplitTableFiles.contains($0) }
            let additional = try KeysplitTables.parse(files: additionalFiles)
            state.keysplits = KeysplitTables(tables: state.keysplits.tables + additional.tables)
            state.scannedKeysplits = true
        }
        return state.keysplits.table(named: symbol)
    }

    private func providedText(
        at location: VoicegroupLocation, contiguousFill: Bool, noSubRecurse: Bool
    ) throws -> VoicegroupText {
        do {
            return try inputs.textProvider(location, contiguousFill, noSubRecurse)
        } catch let error as BankBuildError {
            throw error
        } catch VoicegroupTextError.hardFailure(let line, let reason) {
            throw BankBuildError.hardFailure("\(location.filePath):\(line): \(reason)")
        } catch {
            throw BankBuildError.unreadable(location.filePath)
        }
    }

    private func absolutePath(_ relativePath: String) throws -> String {
        let root = inputs.layout.projectRoot
        guard root.utf8.count + 1 + relativePath.utf8.count < 512 else {
            throw BankBuildError.hardFailure("Asset path is too long: \(relativePath)")
        }
        let path = root + "/" + relativePath
        for byte in relativePath.utf8 {
            if byte == 92 { return path.replacingOccurrences(of: "\\", with: "/") }
        }
        return path
    }

    private func copyName(_ name: ArraySlice<UInt8>, to destination: UnsafeMutablePointer<CChar>) {
        let count = min(name.count, Int(VG_VOICE_NAME_LEN) - 1)
        let source = name.span
        var target = MutableSpan(_unsafeStart: destination, count: Int(VG_VOICE_NAME_LEN))
        var index = 0
        while index < count { target[index] = CChar(bitPattern: source[index]); index += 1 }
        target[count] = 0
    }
}
