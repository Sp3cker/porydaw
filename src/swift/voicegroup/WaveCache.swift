import Foundation
import PorydawVoicegroupNative

/// Native byte-span format used on the first decode of an uncached path.
public enum WaveFormat { case wav, aiff, bin }

/// Identifies the source path of a hard file-read or native-decoder failure.
public struct WaveDecodeError: Error, Equatable, Sendable {
    public let path: String

    public init(path: String) { self.path = path }
}

/// Project-scoped decode cache, mutated only by its owning VoicegroupStore.
public final class WaveCache {
    private var waves: [String: WaveRef] = [:]

    public init() {}

    /// Returns a shared decoded wave, nil on a soft miss, or throws on a hard failure.
    public func wave(absolutePath: String, format: WaveFormat) throws -> WaveRef? {
        if let cached = waves[absolutePath] { return cached }
        guard let data = try read(absolutePath) else { return nil }
        var hardFailure = false
        let raw = data.withUnsafeBytes { bytes -> UnsafeMutablePointer<WaveData>? in
            let source = bytes.bindMemory(to: UInt8.self)
            return absolutePath.withCString { path in
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
        guard let raw else {
            if hardFailure { throw WaveDecodeError(path: absolutePath) }
            return nil
        }
        let wave = WaveRef(raw: raw, path: absolutePath)
        waves[absolutePath] = wave
        return wave
    }

    /// Builds the native 17-byte synth payload, shared by its symbol cache key.
    public func synth(symbol: String, descriptor: [UInt8]) -> WaveRef? {
        precondition(descriptor.count == 6, "Synth descriptor must contain six bytes")
        let path = "synth-macro:\(symbol)"
        if let cached = waves[path] { return cached }
        let headerSize = MemoryLayout<WaveData>.size
        guard let storage = calloc(1, headerSize + 17) else { return nil }
        let raw = storage.bindMemory(to: WaveData.self, capacity: 1)
        let payload = storage.advanced(by: headerSize).bindMemory(to: Int8.self, capacity: 17)
        raw.pointee.type = 0
        raw.pointee.status = 0x4000
        raw.pointee.freq = 0x0105_8920
        raw.pointee.loopStart = 0
        raw.pointee.size = 0
        raw.pointee.data = payload
        descriptor.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { preconditionFailure("Synth descriptor has no storage") }
            UnsafeMutableRawPointer(payload).copyMemory(from: source, byteCount: 6)
        }
        let wave = WaveRef(raw: raw, path: path)
        waves[path] = wave
        return wave
    }

    /// Decodes a fresh packed programmable wave without caching it.
    public func prog(absolutePath: String) throws -> ProgWaveRef? {
        guard let data = try read(absolutePath) else { return nil }
        var hardFailure = false
        let raw = data.withUnsafeBytes { bytes -> UnsafeMutablePointer<UInt32>? in
            let source = bytes.bindMemory(to: UInt8.self)
            return absolutePath.withCString { path in
                vg_asset_decode_prog(source.baseAddress, source.count, path, &hardFailure)
            }
        }
        guard let raw else {
            if hardFailure { throw WaveDecodeError(path: absolutePath) }
            return nil
        }
        return ProgWaveRef(raw: raw, path: absolutePath)
    }

    /// Drops cache ownership without invalidating references retained by live banks.
    public func removeAll() { waves.removeAll() }

    private func read(_ path: String) throws -> Data? {
        do {
            return try ProjectFileStore.read(path)
        } catch {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            throw WaveDecodeError(path: path)
        }
    }
}
