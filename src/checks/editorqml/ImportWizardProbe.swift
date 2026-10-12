import Foundation
import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class ImportWizardProbe: QmlInstantiableStatus {
    public init() {}
    public func componentComplete() {}

    public func midiDivision(path: String) -> Int {
        guard let handle = FileHandle(forReadingAtPath: path) else { return -1 }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 14), header.count == 14,
            header.prefix(4).elementsEqual("MThd".utf8)
        else { return -1 }
        return Int(header[12]) << 8 | Int(header[13])
    }

    public func midiCfgFlags(projectRoot: String, label: String) -> String {
        let path = projectRoot + "/sound/songs/midi/midi.cfg"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        let prefix = label + ".mid:"
        return text.components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) ?? ""
    }

    public func songTablePlayer(projectRoot: String, label: String) -> String {
        let path = projectRoot + "/sound/song_table.inc"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        for line in text.components(separatedBy: .newlines) {
            let fields = line.trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," })
            if fields.count >= 3, fields[0] == "song", fields[1] == label {
                return String(fields[2])
            }
        }
        return ""
    }

    public func exists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func fingerprint(path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "\(data.count):\(String(hash, radix: 16))"
    }

    public func blankSongFingerprint() -> String {
        guard let bytes = try? MidiFile.blankSong().encoded() else { return "" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "\(bytes.count):\(String(hash, radix: 16))"
    }
    public func fileContains(path: String, text: String) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return contents.contains(text)
    }
    public func writeTextFile(path: String, text: String) -> Bool {
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }

    public func makeDirectory(path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return true
        } catch { return false }
    }

    public func makeSymbolicLink(linkPath: String, targetPath: String) -> Bool {
        do {
            try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: targetPath)
            return true
        } catch { return false }
    }

    public func writePhaseCancellingWav(path: String) -> Bool {
        // Stereo 16-bit PCM, 200 frames: the right channel negates the left.
        // Keep the sample pattern aligned with decoderStereo's anti-phase fixture.
        var samples: [UInt8] = []
        samples.reserveCapacity(200 * 4)
        for index in 0..<200 {
            let value = Int16((16_000 * sin(2 * Double.pi * Double(index) / 50)).rounded())
            for channel in [value, -value] {
                let bits = UInt16(bitPattern: channel)
                samples.append(UInt8(truncatingIfNeeded: bits))
                samples.append(UInt8(truncatingIfNeeded: bits >> 8))
            }
        }
        var bytes = Array("RIFF".utf8) + [UInt8](repeating: 0, count: 4) + Array("WAVEfmt ".utf8)
        func append16(_ value: UInt16) {
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func append32(_ value: UInt32) {
            append16(UInt16(truncatingIfNeeded: value))
            append16(UInt16(truncatingIfNeeded: value >> 16))
        }
        append32(16)
        append16(1)
        append16(2)
        append32(22_050)
        append32(88_200)
        append16(4)
        append16(16)
        bytes += Array("data".utf8)
        append32(UInt32(samples.count))
        bytes += samples
        let size = UInt32(bytes.count - 8)
        for index in 0..<4 {
            bytes[4 + index] = UInt8(truncatingIfNeeded: size >> (index * 8))
        }
        do {
            try Data(bytes).write(to: URL(fileURLWithPath: path))
            return true
        } catch { return false }
    }

    public func writeOverflowSource(path: String) -> Bool {
        let tick = TimeDefaults.maxTick
        let maximumDelta: Tick = 0x0FFF_FFFF
        var events: [MidiEvent] = []
        var cursor: Tick = maximumDelta
        while cursor < tick {
            events.append(.meta(tick: cursor, type: 0x01, data: []))
            cursor += min(maximumDelta, tick - cursor)
        }
        events.append(.channel(tick: tick, status: 0x90, data0: 60, data1: 100))
        let file = MidiFile(
            division: 12,
            chunks: [
                MidiChunk(events: events, endTick: tick)
            ])
        guard let bytes = try? file.encoded() else { return false }
        do {
            try Data(bytes).write(to: URL(fileURLWithPath: path))
            return true
        } catch { return false }
    }

    public func setWritable(path: String, writable: Bool) -> Bool {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: writable ? 0o644 : 0o444], ofItemAtPath: path)
            return true
        } catch { return false }
    }

    public func copyFile(from: String, to: String) -> Bool {
        do {
            try FileManager.default.copyItem(atPath: from, toPath: to)
            return true
        } catch { return false }
    }

    public func removeFlag(projectRoot: String, label: String, flag: String) -> Bool {
        let url = URL(fileURLWithPath: projectRoot + "/sound/songs/midi/midi.cfg")
        guard let original = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let prefix = label + ".mid:"
        var lines = original.components(separatedBy: "\n")
        guard
            let index = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
            })
        else { return false }
        let line = lines[index]
        guard let range = line.range(of: flag, options: [], range: line.startIndex..<line.endIndex),
            range.lowerBound == line.startIndex || line[line.index(before: range.lowerBound)].isWhitespace,
            range.upperBound == line.endIndex || line[range.upperBound].isWhitespace
        else { return false }
        lines[index].removeSubrange(range)
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }

    public func chunkCount(path: String) -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let file = try? MidiFile.decode(Array(data))
        else { return -1 }
        return file.chunks.count
    }

    public func controllerCount(path: String, chunk: Int, controller: Int) -> Int {
        guard let events = chunkEvents(path: path, chunk: chunk) else { return -1 }
        return events.filter {
            if case .channel(let status, let data0, _) = $0.payload {
                return status >> 4 == 0xB && Int(data0) == controller
            }
            return false
        }.count
    }

    public func programCount(path: String, chunk: Int) -> Int {
        guard let events = chunkEvents(path: path, chunk: chunk) else { return -1 }
        return events.filter { $0.typeNibble == 0xC && $0.isChannel }.count
    }

    private func chunkEvents(path: String, chunk: Int) -> [MidiEvent]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let file = try? MidiFile.decode(Array(data)),
            file.chunks.indices.contains(chunk)
        else { return nil }
        return file.chunks[chunk].events
    }
}
