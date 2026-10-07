import Foundation
import PorydawVoicegroupNative
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

public enum WaveFormat { case wav, aiff, bin }
public struct WaveDecodeError: Error, Equatable, Sendable {
    public let path: String
    public init(path: String) { self.path = path }
}

/// Owns decoder allocations; banks borrow them until their last release.
public final class WaveCache {
    private struct Entry {
        var refs: Int
        var evicted: Bool
    }
    private struct PathEntry {
        let path: String
        let raw: UnsafeMutablePointer<WaveData>
        let next: Int?
    }
    private var waves: [UInt64: Int] = [:]
    private var paths: [PathEntry] = []
    private var synths: [SymbolKey: UnsafeMutablePointer<WaveData>] = [:]
    private var entries: [UnsafeMutablePointer<WaveData>: Entry] = [:]
    public init() {
        waves.reserveCapacity(32)
        paths.reserveCapacity(32)
        synths.reserveCapacity(8)
        entries.reserveCapacity(32)
    }

    deinit {
        // Decoder allocations are released at the C ownership boundary.
        for raw in entries.keys { free(raw) }
    }

    public func wave(absolutePath: String, format: WaveFormat) throws -> UnsafeMutablePointer<WaveData>? {
        let pathBytes = absolutePath.utf8
        let hash = SymbolKey.byteHash(pathBytes.span)
        var cursor = waves[hash]
        while let index = cursor {
            let entry = paths[index]
            if entry.path == absolutePath { return entry.raw }
            cursor = entry.next
        }
        guard let bytes = try read(absolutePath) else { return nil }
        var hardFailure = false
        let raw = bytes.withUnsafeBufferPointer { source in
            absolutePath.withCString { path in
                switch format {
                case .wav: vg_asset_decode_wav(source.baseAddress, source.count, path, &hardFailure)
                case .aiff: vg_asset_decode_aiff(source.baseAddress, source.count, path, &hardFailure)
                case .bin: vg_asset_decode_bin(source.baseAddress, source.count, path, &hardFailure)
                }
            }
        }
        guard let raw else {
            if hardFailure { throw WaveDecodeError(path: absolutePath) }
            return nil
        }
        paths.append(PathEntry(path: absolutePath, raw: raw, next: waves[hash]))
        waves[hash] = paths.count - 1
        entries[raw] = Entry(refs: 0, evicted: false)
        return raw
    }

    func wave(
        directory: String, relativePath: borrowing Span<UInt8>, format: WaveFormat,
        suffix: String = "", removingLast: Int = 0, truncate: Bool = false
    ) throws -> UnsafeMutablePointer<WaveData>? {
        let directoryBytes = directory.utf8
        let directorySpan = directoryBytes.span
        let suffixBytes = suffix.utf8
        let suffixSpan = suffixBytes.span
        let nameCount = relativePath.count - removingLast
        let requested = directorySpan.count + 1 + nameCount + suffixSpan.count
        guard truncate || requested < 512 else {
            throw BankBuildError.hardFailure("Asset path is too long")
        }
        var storage = InlineArray<512, UInt8>(repeating: 0)
        let count = min(requested, 511)
        do {
            var path = storage.mutableSpan
            var index = 0
            while index < count {
                let byte: UInt8
                if index < directorySpan.count {
                    byte = directorySpan[index]
                } else if index == directorySpan.count {
                    byte = 47
                } else if index - directorySpan.count - 1 < nameCount {
                    byte = relativePath[index - directorySpan.count - 1]
                } else {
                    byte = suffixSpan[index - directorySpan.count - 1 - nameCount]
                }
                path[index] = byte == 92 ? 47 : byte
                index += 1
            }
        }
        let path = storage.span
        let bytes = path.extracting(0..<count)
        if let cached = cachedWave(bytes) { return cached }
        // POSIX access borrows the bounded, NUL-terminated path only for the syscall.
        let exists = path.withUnsafeBufferPointer {
            guard let base = $0.baseAddress else { preconditionFailure("Inline path is nonempty") }
            return access(UnsafeRawPointer(base).assumingMemoryBound(to: CChar.self), F_OK) == 0
        }
        guard exists else { return nil }
        return try wave(absolutePath: AsmLine.text(bytes), format: format)
    }

    private func cachedWave(_ path: borrowing Span<UInt8>) -> UnsafeMutablePointer<WaveData>? {
        var cursor = waves[SymbolKey.byteHash(path)]
        while let cached = cursor {
            let entry = paths[cached]
            let keyBytes = entry.path.utf8
            let key = keyBytes.span
            if key.count == path.count {
                var index = path.count
                while index > 0 && key[index - 1] == path[index - 1] { index -= 1 }
                if index == 0 { return entry.raw }
            }
            cursor = entry.next
        }
        return nil
    }

    public func synth(symbol: ArraySlice<UInt8>, descriptor: [UInt8]) -> UnsafeMutablePointer<WaveData>? {
        precondition(descriptor.count == 6, "Synth descriptor must contain six bytes")
        if let raw = synths[SymbolKey(symbol)] { return raw }
        let headerSize = MemoryLayout<WaveData>.size
        guard let storage = calloc(1, headerSize + 17) else { return nil }
        let raw = storage.bindMemory(to: WaveData.self, capacity: 1)
        let payload = storage.advanced(by: headerSize).bindMemory(to: Int8.self, capacity: 17)
        var header = WaveData()
        header.status = 0x4000
        header.freq = 0x0105_8920
        header.data = payload
        var headers = MutableSpan(_unsafeStart: raw, count: 1)
        headers[0] = header
        let source = descriptor.span
        var destination = MutableSpan(_unsafeStart: payload, count: 17)
        var index = 0
        while index < 6 { destination[index] = Int8(bitPattern: source[index]); index += 1 }
        synths[SymbolKey(symbol)] = raw
        entries[raw] = Entry(refs: 0, evicted: false)
        return raw
    }

    public func prog(absolutePath: String) throws -> UnsafeMutablePointer<UInt32>? {
        guard let bytes = try read(absolutePath) else { return nil }
        var hardFailure = false
        let raw = bytes.withUnsafeBufferPointer { source in
            absolutePath.withCString { path in
                vg_asset_decode_prog(source.baseAddress, source.count, path, &hardFailure)
            }
        }
        if raw == nil && hardFailure { throw WaveDecodeError(path: absolutePath) }
        return raw
    }

    func retain(_ raw: UnsafeMutablePointer<WaveData>) {
        guard var entry = entries[raw] else { preconditionFailure("Wave does not belong to this cache") }
        entry.refs += 1
        entries[raw] = entry
    }

    func references(to raw: UnsafeMutablePointer<WaveData>) -> Int? { entries[raw]?.refs }

    public func release(_ raw: UnsafeMutablePointer<WaveData>) {
        guard var entry = entries[raw] else { preconditionFailure("Wave does not belong to this cache") }
        precondition(entry.refs > 0)
        entry.refs -= 1
        if entry.refs == 0 && entry.evicted {
            entries.removeValue(forKey: raw)
            free(raw)
        } else {
            entries[raw] = entry
        }
    }

    public func removeAll() {
        for (raw, entry) in entries {
            if entry.refs == 0 {
                entries.removeValue(forKey: raw)
                free(raw)
            } else {
                entries[raw] = Entry(refs: entry.refs, evicted: true)
            }
        }
        waves.removeAll(keepingCapacity: true)
        paths.removeAll(keepingCapacity: true)
        synths.removeAll(keepingCapacity: true)
    }

    private func read(_ path: String) throws -> [UInt8]? {
        if path.withCString({ access($0, F_OK) }) != 0 { return nil }
        do { return try VoicegroupText.read(path) } catch { throw WaveDecodeError(path: path) }
    }
}
