import Foundation
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

    public func fileExists(path: String) -> Bool {
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
}
