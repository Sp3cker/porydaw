import Foundation
import PorydawCore
import PorydawSample

public struct Sf2ZonePickerModel: Equatable {
    public struct Row: Equatable {
        public let zoneIndex: Int
        public let columns: [String]
    }

    public struct Group: Equatable {
        public let title: String
        public var rows: [Row]
    }

    public static let columnTitles = ["Sample", "Key", "Rate", "Frames", "Loop", "Notes"]
    public static let title = "Import Sample — pick a SoundFont zone"
    public static let searchPlaceholder = "Search samples, instruments, presets…"

    private let zones: [Sf2Zone]
    public var filter: String = "" { didSet { rebuild() } }
    public private(set) var groups: [Group] = []
    public private(set) var selectedZone = -1
    public var canAccept: Bool { selectedZone >= 0 }

    public init(file: Sf2File) {
        zones = file.zones
        rebuild()
    }

    public mutating func select(zoneIndex: Int) {
        selectedZone = groups.contains { $0.rows.contains { $0.zoneIndex == zoneIndex } } ? zoneIndex : -1
    }

    public mutating func selectGroup(title: String) {
        selectedZone = -1
    }

    private mutating func rebuild() {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        groups = []
        for (index, zone) in zones.enumerated() {
            if !needle.isEmpty
                && ![zone.name, zone.instrument, zone.preset].contains(where: {
                    $0.range(of: needle, options: .caseInsensitive) != nil
                })
            {
                continue
            }
            var title = zone.instrument.isEmpty ? "(no instrument)" : zone.instrument
            if !zone.preset.isEmpty { title += " — \(zone.preset)" }
            var key = zone.originalPitch > 127 ? "—" : midiKeyName(zone.originalPitch)
            if zone.originalPitch <= 127 && zone.pitchCorrection != 0 {
                key += " \(zone.pitchCorrection > 0 ? "+" : "")\(zone.pitchCorrection)¢"
            }
            let loop =
                zone.hasLoop
                ? "\(zone.loopStart - zone.start)–\(zone.loopEndExclusive - zone.start - 1)" : "—"
            let row = Row(
                zoneIndex: index,
                columns: [
                    zone.name, key, "\(zone.sampleRate) Hz", "\(zone.frames)", loop,
                    zone.isStereoPair ? "stereo pair" : "",
                ])
            if let groupIndex = groups.firstIndex(where: { $0.title == title }) {
                groups[groupIndex].rows.append(row)
            } else {
                groups.append(Group(title: title, rows: [row]))
            }
        }
        if !groups.contains(where: { $0.rows.contains(where: { $0.zoneIndex == selectedZone }) }) {
            selectedZone = -1
        }
    }
}
