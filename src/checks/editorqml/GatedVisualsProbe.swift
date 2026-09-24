import Foundation
import PorydawApp
import QtBridge

@MainActor
@QtBridgeable
public final class GatedVisualsProbe: QmlInstantiableStatus {
    public init() {}

    public func componentComplete() {}

    private static func songURL(projectRoot: String, label: String) -> URL {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent("sound/songs/midi/\(label).mid")
    }

    private static func backupURL(projectRoot: String, label: String) -> URL {
        songURL(projectRoot: projectRoot, label: label)
            .appendingPathExtension("testbak")
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

    public func noteFace(track: Int, velocity: Int, zeroColor: String) -> String {
        PaletteMath.noteFill(track: track, velocity: velocity, zeroColor: zeroColor)
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
