import Foundation

extension SongRegistration {
    public static func register(root: String, label: String, constant: String,
                                player: String) throws -> Int {
        let plan = plan(root: root, label: label, constant: constant, player: player)
        let tablePath = root + "/sound/song_table.inc"
        var table = try RegistrationLines(path: tablePath)
        let scan = SongTableScan(table.texts, label: label)
        if scan.labelLine < 0 || plan.migrateFromIndex >= 0 {
            guard scan.lastSongLine >= 0 else {
                throw SongRegistrationError.failed("\(tablePath) has no song entries")
            }
            if plan.migrateFromIndex >= 0 && plan.migrateFromIndex < scan.count {
                table.remove(scan.entryLines[plan.migrateFromIndex])
            }
            if plan.tableReplaceIndex >= 0 && plan.tableReplaceIndex < scan.count {
                table.replace(scan.entryLines[plan.tableReplaceIndex], plan.songTableLine)
            } else if plan.tableInsertIndex >= 0 && plan.tableInsertIndex < scan.count {
                table.insert(scan.entryLines[plan.tableInsertIndex], plan.songTableLine)
            } else if plan.tableInsertIndex < 0 && plan.songId >= 0 && plan.songId < scan.count {
                table.replace(scan.entryLines[plan.songId], plan.songTableLine)
            } else {
                let appendAt = scan.lastSongLine + 1
                table.insert(min(appendAt, table.lines.count), plan.songTableLine)
            }
        }
        try table.save(tablePath)

        let songsPath = root + "/include/constants/songs.h"
        var songsH = try RegistrationLines(path: songsPath)
        var own = -1
        var ownMatch: RegistrationMatch?
        var insertAfter = -1
        var firstDefine = -1
        var firstEndif = -1
        for index in songsH.lines.indices {
            let text = songsH.text(index)
            if own < 0, let match = RegistrationText.match(
                #"^(\s*#define\s+\#(constant)\s+)(\d+)(.*)$"#, text) {
                own = index
                ownMatch = match
            }
            if let marker = RegistrationText.match(RegistrationText.marker, text),
               (plan.repointEndSe && marker.group(2) == "END_SE"
                || plan.repointEndMus && marker.group(2) == "END_MUS") {
                let follow = Int(marker.group(3)) == nil ? constant : String(plan.songId)
                if marker.group(3) != follow {
                    songsH.replace(index, marker.group(1) + follow + marker.group(4))
                }
                continue
            }
            guard let entry = RegistrationText.match(RegistrationText.define, text),
                  !RegistrationText.isMarker(entry.group(2)),
                  let id = Int(entry.group(3)) else {
                if firstEndif < 0 && RegistrationText.match(#"^\s*#endif\b"#, text) != nil {
                    firstEndif = index
                }
                continue
            }
            if firstDefine < 0 { firstDefine = index }
            if id < plan.songId { insertAfter = index }
            if plan.renumberFrom >= 0 && index != own && id >= plan.renumberFrom
                && id < plan.renumberBelow {
                songsH.replace(index, entry.group(1) + String(id + 1) + entry.group(4))
            }
        }
        let moveOwn = own >= 0 && plan.migrateFromIndex >= 0
            && Int(ownMatch?.group(2) ?? "") != plan.songId
        if own >= 0 && !moveOwn, let old = ownMatch {
            if Int(old.group(2)) != plan.songId {
                songsH.replace(own, old.group(1) + String(plan.songId) + old.group(3))
            }
        } else {
            var at = insertAfter >= 0 ? insertAfter + 1
                : firstDefine >= 0 ? firstDefine : firstEndif >= 0 ? firstEndif : songsH.lines.count
            if moveOwn {
                songsH.remove(own)
                if own < at { at -= 1 }
            }
            songsH.insert(at, plan.songsHLine)
        }
        try songsH.save(songsPath)

        if plan.ldApplicable {
            let path = root + "/ld_script.ld"
            var file = try RegistrationLines(path: path)
            let needle = "sound/songs/midi/\(label).o"
            let last = file.lines.indices.last { file.text($0).contains("sound/songs/midi/") }
            if !file.lines.indices.contains(where: { file.text($0).contains(needle) }) {
                file.insert((last ?? -1) + 1, plan.ldLine)
            }
            try file.save(path)
        }
        if plan.charmapApplicable {
            let path = root + "/charmap.txt"
            var file = try RegistrationLines(path: path)
            let names = RegistrationText.constantNames(root)
            var own = -1
            var ownMatch: RegistrationMatch?
            var ownAnyForm = false
            var insertAfter = -1
            var firstEntry = -1
            for index in file.lines.indices {
                let text = file.text(index)
                if RegistrationText.match(#"^\s*\#(constant)\s*="# , text) != nil {
                    ownAnyForm = true
                }
                guard let entry = RegistrationText.match(RegistrationText.charmap, text),
                      names.contains(entry.group(1)) else { continue }
                if own < 0 && entry.group(1) == constant {
                    own = index
                    ownMatch = entry
                }
                if firstEntry < 0 { firstEntry = index }
                let value = RegistrationText.charmapValue(entry)
                if value < plan.songId { insertAfter = index }
                if plan.renumberFrom >= 0 && entry.group(1) != constant
                    && value >= plan.renumberFrom && value < plan.renumberBelow {
                    file.replace(index, entry.prefix(3) + RegistrationText.bytes(value + 1))
                }
            }
            let moveOwn = own >= 0 && plan.migrateFromIndex >= 0
            if own >= 0 && !moveOwn, let old = ownMatch {
                if RegistrationText.charmapValue(old) != plan.songId {
                    file.replace(own, old.prefix(3) + RegistrationText.bytes(plan.songId))
                }
            } else if moveOwn || !ownAnyForm {
                var at = insertAfter >= 0 ? insertAfter + 1 : firstEntry
                if moveOwn {
                    file.remove(own)
                    if at > own { at -= 1 }
                }
                if at >= 0 { file.insert(at, plan.charmapLine) }
            }
            try file.save(path)
        }
        if plan.debugApplicable {
            try DebugSoundLists.insert(root: root, constant: constant, plan: plan)
        }
        return plan.songId
    }
}
