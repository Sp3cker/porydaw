import Foundation
import PorydawApp
import QtBridge
import PorydawCore

@MainActor
@QtBridgeable
public final class GatedVisualsProbe: QmlInstantiableStatus {
    public init() {}

    public func componentComplete() {}
    public func expectedLaneDpr() -> Int {
        ProcessInfo.processInfo.environment["QT_SCALE_FACTOR"] == "2" ? 2 : 1
    }

    private static func songURL(projectRoot: String, label: String) -> URL {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent("sound/songs/midi/\(label).mid")
    }

    private static func backupURL(projectRoot: String, label: String) -> URL {
        songURL(projectRoot: projectRoot, label: label)
            .appendingPathExtension("testbak")
    }
    private static func unsignedBackupURL(projectRoot: String, label: String) -> URL {
        songURL(projectRoot: projectRoot, label: label).appendingPathExtension("unsignedbak")
    }

    public func prepareUnsignedSong(projectRoot: String, label: String, division: Int = 24) -> Bool {
        let song = Self.songURL(projectRoot: projectRoot, label: label)
        let backup = Self.unsignedBackupURL(projectRoot: projectRoot, label: label)
        do {
            let original = try Data(contentsOf: song)
            var file = try MidiFile.decode(Array(original))
            guard file.chunks.contains(where: { $0.events.contains(where: { $0.metaType == 0x58 }) })
            else { return false }
            for index in file.chunks.indices {
                file.chunks[index].events.removeAll { $0.metaType == 0x58 }
            }
            guard division == 24 || division == 48, file.division == 24 else { return false }
            if division == 48 {
                file.division = 48
                for index in file.chunks.indices {
                    for eventIndex in file.chunks[index].events.indices {
                        file.chunks[index].events[eventIndex].tick *= 2
                    }
                    file.chunks[index].endTick *= 2
                }
            }
            try original.write(to: backup)
            try Data(file.encoded()).write(to: song)
            return true
        } catch {
            return false
        }
    }

    public func restoreUnsignedSong(projectRoot: String, label: String) -> Bool {
        let song = Self.songURL(projectRoot: projectRoot, label: label)
        let backup = Self.unsignedBackupURL(projectRoot: projectRoot, label: label)
        do {
            guard FileManager.default.fileExists(atPath: backup.path) else { return false }
            try Data(contentsOf: backup).write(to: song)
            try FileManager.default.removeItem(at: backup)
            return true
        } catch {
            return false
        }
    }

    public func moveSongAside(projectRoot: String, label: String) -> Bool {
        let song = Self.songURL(projectRoot: projectRoot, label: label)
        let backup = Self.backupURL(projectRoot: projectRoot, label: label)
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            guard FileManager.default.fileExists(atPath: song.path) else { return false }
            try FileManager.default.moveItem(at: song, to: backup)
            return true
        } catch {
            return false
        }
    }

    public func restoreSong(projectRoot: String, label: String) -> Bool {
        let song = Self.songURL(projectRoot: projectRoot, label: label)
        let backup = Self.backupURL(projectRoot: projectRoot, label: label)
        do {
            if FileManager.default.fileExists(atPath: backup.path),
               !FileManager.default.fileExists(atPath: song.path) {
                try FileManager.default.moveItem(at: backup, to: song)
            } else if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            return FileManager.default.fileExists(atPath: song.path)
        } catch {
            return false
        }
    }

    public func withRelativeAlpha(color: String, alpha: Int) -> String {
        let c = PaletteMath.channels(color)
        let a = (c.a * alpha + 127) / 255
        return PaletteMath.hex(r: c.r, g: c.g, b: c.b, a: a)
    }

    public func sourceOver(foreground: String, background: String) -> String {
        let s = PaletteMath.channels(foreground)
        let d = PaletteMath.channels(background)
        let channel = { (source: Int, destination: Int) in
            (source * s.a + destination * (255 - s.a) + 127) / 255
        }
        return PaletteMath.hex(r: channel(s.r, d.r), g: channel(s.g, d.g),
                               b: channel(s.b, d.b))
    }
}
