import Foundation

extension SongRegistration {
    public static func removalPlan(root: String, label: String, constant: String) -> RemovalPlan {
        let table = SongTableScan(RegistrationText.lines(root, "sound/song_table.inc"), label: label)
        var result = RemovalPlan()
        result.tableIndex = table.labelIndex
        result.tableCount = table.count
        result.lastEntry = table.labelLine >= 0 && table.labelLine == table.lastSongLine
        let ownDefine = RegistrationText.dynamic(#"^\s*#define\s+\#(constant)\s+\d"#)
        result.inSongsH = RegistrationText.lines(root, "include/constants/songs.h").contains {
            RegistrationText.match(ownDefine, $0) != nil
        }
        result.inLdScript = RegistrationText.lines(root, "ld_script.ld").contains {
            $0.contains("sound/songs/midi/\(label).o")
        }
        result.inCharmap = RegistrationText.lines(root, "charmap.txt").contains {
            RegistrationText.match(RegistrationText.charmap, $0)?.group(1) == constant
        }
        result.inDebugMenu = DebugSoundLists(RegistrationText.lines(root, "src/debug.c"))
            .lists.contains { $0.names.contains(constant) }
        return result
    }

    public static func unregister(root: String, label: String, constant: String) throws {
        let tablePath = root + "/sound/song_table.inc"
        if var file = try? RegistrationLines(path: tablePath) {
            let scan = SongTableScan(file.texts, label: label)
            if scan.labelIndex == 0 {
                throw SongRegistrationError.failed("\(label) is the first song_table.inc entry (song ID 0), the engine's fallback song — it cannot be deleted.")
            }
            if scan.labelLine >= 0 && scan.labelLine == scan.lastSongLine {
                file.remove(scan.labelLine)
                while true {
                    let tail = SongTableScan(file.texts, label: label)
                    if tail.count <= 1 || tail.lastSongLabel != tail.firstLabel { break }
                    file.remove(tail.lastSongLine)
                }
            } else if scan.labelLine >= 0 {
                file.replace(scan.labelLine, "\(scan.labelIndent)song \(scan.firstLabel), \(scan.firstPlayer), \(scan.firstPlayerNum)")
            }
            try file.save(tablePath)
        }

        let songsPath = root + "/include/constants/songs.h"
        if var file = try? RegistrationLines(path: songsPath) {
            var own = -1
            var ownValue = -1
            var markerLines: [Int] = []
            var definitions: [(String, Int)] = []
            let ownDefine = RegistrationText.dynamic(#"^\s*#define\s+\#(constant)\s+(\d+)\b"#)
            for index in file.lines.indices {
                let text = file.text(index)
                if own < 0, let match = RegistrationText.match(ownDefine, text) {
                    own = index
                    ownValue = Int(match.group(1)) ?? -1
                    continue
                }
                if RegistrationText.match(RegistrationText.marker, text) != nil {
                    markerLines.append(index)
                    continue
                }
                if let match = RegistrationText.match(RegistrationText.define, text),
                   match.group(2) != constant && !RegistrationText.isMarker(match.group(2)),
                   let value = Int(match.group(3)) {
                    definitions.append((match.group(2), value))
                }
            }
            if own >= 0 {
                let preceding = definitions.filter { $0.1 < ownValue }.max { $0.1 < $1.1 }
                for index in markerLines {
                    guard let marker = RegistrationText.match(RegistrationText.marker, file.text(index))
                    else { continue }
                    let isNumeric = Int(marker.group(3)) != nil
                    if isNumeric && Int(marker.group(3)) != ownValue { continue }
                    if !isNumeric && marker.group(3) != constant { continue }
                    guard let preceding else { continue }
                    file.replace(index, marker.group(1) + (isNumeric
                        ? String(preceding.1) : preceding.0) + marker.group(4))
                }
                file.remove(own)
            }
            try file.save(songsPath)
        }

        let ldPath = root + "/ld_script.ld"
        if var file = try? RegistrationLines(path: ldPath) {
            if let index = file.lines.indices.first(where: {
                file.text($0).contains("sound/songs/midi/\(label).o")
            }) { file.remove(index) }
            try file.save(ldPath)
        }
        let charmapPath = root + "/charmap.txt"
        if var file = try? RegistrationLines(path: charmapPath) {
            if let index = file.lines.indices.first(where: {
                RegistrationText.match(RegistrationText.charmap, file.text($0))?.group(1) == constant
            }) { file.remove(index) }
            try file.save(charmapPath)
        }
        try DebugSoundLists.remove(root: root, constant: constant)
    }

    public static func removeFlags(root: String, label: String) throws {
        let cfgPath = root + "/sound/songs/midi/midi.cfg"
        if var file = try? RegistrationLines(path: cfgPath) {
            if let index = file.lines.indices.first(where: {
                let line = file.text($0)
                guard let colon = line.firstIndex(of: ":") else { return false }
                return line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines) == "\(label).mid"
            }) { file.remove(index) }
            try file.save(cfgPath)
        }
        let mkPath = root + "/songs.mk"
        if var file = try? RegistrationLines(path: mkPath) {
            let rule = RegistrationText.dynamic(#"^(?:\$\(MID_SUBDIR\)|sound/songs/midi)/\#(label)\.s\s*:"#)
            if let index = file.lines.indices.first(where: {
                RegistrationText.match(rule, file.text($0)) != nil
            }) {
                var last = index + 1
                while last < file.lines.count && file.text(last).hasPrefix("\t") { last += 1 }
                for _ in index..<last { file.remove(index) }
                if index > 0 && file.text(index - 1).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (index >= file.lines.count
                        || file.text(index).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    file.remove(index - 1)
                }
            }
            try file.save(mkPath)
        }
    }
}
