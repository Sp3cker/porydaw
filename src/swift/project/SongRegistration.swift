import Foundation

public enum SongRegistrationError: Error, LocalizedError, Sendable {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

public struct RegistrationStatus: Sendable {
    public var inSongTable = false
    public var inSongsH = false
    public var inLdScript = false
    public var inCharmap = false
    public var inDebugMenu = false
    public var ldApplicable = false
    public var charmapApplicable = false
    public var debugApplicable = false

    public var missingFiles: [String] {
        var missing: [String] = []
        if !inSongTable { missing.append("song_table.inc") }
        if !inSongsH { missing.append("songs.h") }
        if ldApplicable && !inLdScript { missing.append("ld_script.ld") }
        if charmapApplicable && !inCharmap { missing.append("charmap.txt") }
        if debugApplicable && !inDebugMenu { missing.append("src/debug.c") }
        return missing
    }
}

public struct RegistrationPlan: Sendable {
    public var label: String
    public var constant: String
    public var player: String
    public var songId: Int
    public var tableInsertIndex = -1
    public var tableReplaceIndex = -1
    public var migrateFromIndex = -1
    public var renumberFrom = -1
    public var renumberBelow = -1
    public var repointEndMus = false
    public var repointEndSe = false
    public var debugUseBgmList = false
    public var songTableLine = ""
    public var songsHLine = ""
    public var ldLine = ""
    public var charmapLine = ""
    public var ldApplicable = false
    public var charmapApplicable = false
    public var debugApplicable = false
}

public struct RemovalPlan: Sendable {
    public var tableIndex = -1
    public var tableCount = 0
    public var lastEntry = false
    public var inSongsH = false
    public var inLdScript = false
    public var inCharmap = false
    public var inDebugMenu = false
}

struct RegistrationLines {
    var lines: [Data]
    let newline: Bool
    let crlf: Bool
    var dirty = false

    init(path: String) throws {
        let split = ProjectFileStore.splitLines(try ProjectFileStore.read(path))
        lines = split.lines
        newline = split.endsWithNewline
        crlf = split.crlf
    }

    func text(_ index: Int) -> String {
        let raw = lines[index]
        return String(decoding: raw.last == 13 ? raw.dropLast() : raw[...], as: UTF8.self)
    }

    var texts: [String] { lines.indices.map(text) }

    mutating func insert(_ index: Int, _ text: String) {
        var line = Data(text.utf8)
        if crlf { line.append(13) }
        lines.insert(line, at: index)
        dirty = true
    }

    mutating func replace(_ index: Int, _ text: String) {
        var line = Data(text.utf8)
        if lines[index].last == 13 { line.append(13) }
        lines[index] = line
        dirty = true
    }

    mutating func remove(_ index: Int) {
        lines.remove(at: index)
        dirty = true
    }

    func save(_ path: String) throws {
        guard dirty else { return }
        var bytes = Data()
        for index in lines.indices {
            if index > 0 { bytes.append(10) }
            bytes.append(lines[index])
        }
        if newline { bytes.append(10) }
        try ProjectFileStore.write(path, data: bytes)
    }
}

struct RegistrationMatch {
    let source: String
    let result: NSTextCheckingResult

    func group(_ index: Int) -> String {
        let range = result.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return (source as NSString).substring(with: range)
    }

    func start(_ index: Int) -> Int { result.range(at: index).location }
    func end(_ index: Int) -> Int { NSMaxRange(result.range(at: index)) }
    func prefix(_ index: Int) -> String { (source as NSString).substring(to: start(index)) }
}

enum RegistrationText {
    static func match(_ pattern: String, _ line: String) -> RegistrationMatch? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: line, range: NSRange(location: 0,
                                                                          length: (line as NSString).length))
        else { return nil }
        return RegistrationMatch(source: line, result: result)
    }

    static func matches(_ pattern: String, _ line: String) -> [RegistrationMatch] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: line, range: NSRange(location: 0,
                                                           length: (line as NSString).length))
            .map { RegistrationMatch(source: line, result: $0) }
    }

    static func lines(_ root: String, _ relative: String) -> [String] {
        guard let file = try? RegistrationLines(path: root + "/" + relative) else { return [] }
        return file.texts
    }

    static func bytes(_ id: Int) -> String {
        String(format: "%02X %02X", id & 255, (id >> 8) & 255)
    }

    static let song = #"^(\s*)song\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+)"#
    static let define = #"^(\s*#define\s+(\w+)\s+)(\d+)\b(.*)$"#
    static let charmap = #"^(\w+)( *)= *([0-9A-Fa-f]{2}) ([0-9A-Fa-f]{2})\s*$"#
    static let marker = #"^(\s*#define\s+(END_SE|END_MUS)\s+)([A-Za-z_]\w*|\d+)(.*)$"#

    static func charmapValue(_ match: RegistrationMatch) -> Int {
        (Int(match.group(3), radix: 16) ?? 0) | ((Int(match.group(4), radix: 16) ?? 0) << 8)
    }

    static func constantNames(_ root: String) -> Set<String> {
        Set(lines(root, "include/constants/songs.h").compactMap {
            match(#"^\s*#define\s+(\w+)\s+\d"#, $0)?.group(1)
        })
    }

    static func isMarker(_ name: String) -> Bool {
        name == "END_SE" || name == "END_MUS" || name == "START_MUS"
    }
}

struct SongTableScan {
    var count = 0
    var labelIndex = -1
    var labelLine = -1
    var labelIndices: [Int] = []
    var labelIndent = ""
    var freeIndices: [Int] = []
    var entryLines: [Int] = []
    var entryLabels: [String] = []
    var lastSongLine = -1
    var lastSongLabel = ""
    var indent = ""
    var firstLabel = ""
    var firstPlayer = ""
    var firstPlayerNum = ""

    init(_ lines: [String], label: String) {
        for (lineIndex, line) in lines.enumerated() {
            guard let match = RegistrationText.match(RegistrationText.song, line) else { continue }
            let name = match.group(2)
            if count == 0 {
                firstLabel = name
                firstPlayer = match.group(3)
                firstPlayerNum = match.group(4)
            }
            if count > 0 && name == firstLabel {
                freeIndices.append(count)
            } else if name == label {
                labelIndex = count
                labelLine = lineIndex
                labelIndices.append(count)
                labelIndent = match.group(1)
            }
            indent = match.group(1)
            lastSongLine = lineIndex
            lastSongLabel = name
            entryLines.append(lineIndex)
            entryLabels.append(name)
            count += 1
        }
    }
}

struct RegistrationRegions {
    struct Marker {
        var line = -1
        var referent = ""
        var value = -1
        var valid: Bool { line >= 0 && value >= 0 }
    }

    var endSe = Marker()
    var endMus = Marker()
    var startMus = -1
    var separateDebugArrays = false
    var regioned: Bool { endMus.valid }

    init(_ songsH: [String], debug: [String]) {
        var values: [String: Int] = [:]
        for (index, line) in songsH.enumerated() {
            if let value = RegistrationText.match(#"^\s*#define\s+(\w+)\s+(\d+)\b"#, line),
               values[value.group(1)] == nil {
                values[value.group(1)] = Int(value.group(2))
            }
            guard let marker = RegistrationText.match(
                #"^\s*#define\s+(END_SE|END_MUS)\s+([A-Za-z_]\w*|\d+)\s*(//.*)?$"#, line)
            else { continue }
            var item = marker.group(1) == "END_SE" ? endSe : endMus
            guard item.line < 0 else { continue }
            item.line = index
            if let value = Int(marker.group(2)) { item.value = value }
            else { item.referent = marker.group(2) }
            if marker.group(1) == "END_SE" { endSe = item } else { endMus = item }
        }
        if !endSe.referent.isEmpty { endSe.value = values[endSe.referent] ?? -1 }
        if !endMus.referent.isEmpty { endMus.value = values[endMus.referent] ?? -1 }
        startMus = values["START_MUS"] ?? -1
        separateDebugArrays = regioned && debug.contains {
            RegistrationText.match(#"\bEND_MUS\b"#, $0) != nil
        }
    }
}

public enum SongRegistration {
    public static func status(root: String, label: String, constant: String) -> RegistrationStatus {
        statuses(root: root, entries: [(label, constant)])[label] ?? RegistrationStatus()
    }

    public static func statuses(root: String, entries: [(String, String)])
        -> [String: RegistrationStatus] {
        let table = RegistrationText.lines(root, "sound/song_table.inc")
        var tableIndices: [String: [Int]] = [:]
        var firstLabel = ""
        var count = 0
        for line in table {
            guard let match = RegistrationText.match(RegistrationText.song, line) else { continue }
            let label = match.group(2)
            if count == 0 { firstLabel = label }
            if count == 0 || label != firstLabel { tableIndices[label, default: []].append(count) }
            count += 1
        }
        let songsH = RegistrationText.lines(root, "include/constants/songs.h")
        var defines: [String: Int] = [:]
        for line in songsH {
            guard let entry = RegistrationText.match(#"^\s*#define\s+(\w+)\s+(\d+)"#, line)
            else { continue }
            if defines[entry.group(1)] == nil { defines[entry.group(1)] = Int(entry.group(2)) }
        }
        let ld = RegistrationText.lines(root, "ld_script.ld")
        let ldApplicable = ld.contains { $0.contains("sound/songs/midi/") }
        var ldLabels: Set<String> = []
        for line in ld {
            for match in RegistrationText.matches(#"sound/songs/midi/(\w+)\.o"#, line) {
                ldLabels.insert(match.group(1))
            }
        }
        var mappings: [String: Int] = [:]
        var charmapApplicable = false
        for line in RegistrationText.lines(root, "charmap.txt") {
            guard let entry = RegistrationText.match(RegistrationText.charmap, line) else { continue }
            if defines[entry.group(1)] != nil { charmapApplicable = true }
            if mappings[entry.group(1)] == nil {
                mappings[entry.group(1)] = RegistrationText.charmapValue(entry)
            }
        }
        let debug = RegistrationText.lines(root, "src/debug.c")
        let soundLists = DebugSoundLists(debug)
        let debugNames = Set(soundLists.lists.flatMap(\.names))
        let regions = RegistrationRegions(songsH, debug: debug)
        var statuses: [String: RegistrationStatus] = [:]
        statuses.reserveCapacity(entries.count)
        for (label, rawConstant) in entries {
            let constant = rawConstant.isEmpty ? label.uppercased() : rawConstant
            let indices = tableIndices[label] ?? []
            var status = RegistrationStatus()
            status.inSongTable = !indices.isEmpty
            if let define = defines[constant] {
                status.inSongsH = (indices.isEmpty || indices.contains(define))
                    && (!regions.regioned || define <= regions.endMus.value)
            }
            status.ldApplicable = ldApplicable
            status.inLdScript = ldLabels.contains(label)
            status.charmapApplicable = charmapApplicable
            if let value = mappings[constant] {
                status.inCharmap = indices.isEmpty || indices.contains(value)
            }
            status.debugApplicable = !soundLists.lists.isEmpty
            status.inDebugMenu = debugNames.contains(constant)
            statuses[label] = status
        }
        return statuses
    }

    public static func plan(root: String, label: String, constant: String,
                            player: String) -> RegistrationPlan {
        let table = SongTableScan(RegistrationText.lines(root, "sound/song_table.inc"), label: label)
        let songsH = RegistrationText.lines(root, "include/constants/songs.h")
        let debug = RegistrationText.lines(root, "src/debug.c")
        let regions = RegistrationRegions(songsH, debug: debug)
        var plan = RegistrationPlan(label: label, constant: constant, player: player, songId: -1)
        let playerNumber = songCatalogPlayerNumber(root: root, name: player)
        plan.songTableLine = "\(table.count > 0 ? table.indent : "\t")song \(label), \(player), \(playerNumber)"
        var valueColumn = 0
        var ownValue = -1
        var used: Set<Int> = []
        for line in songsH {
            guard let entry = RegistrationText.match(#"^#define\s+([A-Z0-9_]+)(\s+)(\d+)"#, line),
                  let id = Int(entry.group(3)) else { continue }
            valueColumn = entry.end(2)
            if entry.group(1) == constant && ownValue < 0 { ownValue = id }
            if !RegistrationText.isMarker(entry.group(1)) { used.insert(id) }
        }
        let settled = table.labelIndices.contains(ownValue) ? ownValue : table.labelIndices.first ?? -1
        let seRouted = constant.hasPrefix("SE_")
        if settled >= 0 && (!regions.regioned || settled <= regions.endMus.value) {
            plan.songId = settled
        } else {
            plan.migrateFromIndex = settled
            var seLast = regions.endSe.valid ? regions.endSe.value : -1
            if seLast < 0 && regions.regioned && regions.startMus >= 0 {
                seLast = used.filter { $0 < regions.startMus }.max() ?? -1
            }
            let seRegioned = seRouted && seLast >= 0
            let musFloor = regions.startMus >= 0 ? regions.startMus : seLast >= 0 ? seLast + 1 : 0
            var free = -1
            var freeInSe = false
            for index in table.freeIndices {
                if !regions.regioned {
                    free = index
                    break
                }
                if seRegioned && index >= 1 && index <= seLast + 1
                    && (regions.startMus < 0 || index < regions.startMus) {
                    free = index
                    freeInSe = true
                    break
                }
                if !seRegioned && index >= musFloor && index <= regions.endMus.value + 1 {
                    free = index
                    break
                }
            }
            var seRegion = false
            let placeholder = seLast + 1
            let canReplace = placeholder > 0 && placeholder < table.count
                && (regions.startMus < 0 || placeholder < regions.startMus)
                && !used.contains(placeholder)
                && (table.entryLabels[placeholder].contains("dummy")
                    || (placeholder + 1 < table.count
                        && table.entryLabels[placeholder + 1] == table.entryLabels[placeholder]))
            if free >= 0 {
                plan.songId = free
                seRegion = freeInSe
            } else if regions.regioned && seRegioned && canReplace {
                plan.songId = placeholder
                plan.tableReplaceIndex = placeholder
                seRegion = true
            } else if regions.regioned {
                plan.songId = regions.endMus.value + 1
                plan.tableInsertIndex = plan.songId
            } else {
                plan.songId = table.count
            }
            if regions.regioned {
                if plan.migrateFromIndex == plan.songId {
                    plan.migrateFromIndex = -1
                    plan.tableInsertIndex = -1
                    plan.tableReplaceIndex = -1
                }
                plan.repointEndSe = seRegion && regions.endSe.valid && plan.songId > regions.endSe.value
                plan.repointEndMus = !seRegion && plan.songId > regions.endMus.value
                plan.debugUseBgmList = seRouted && !seRegion && regions.separateDebugArrays
                if plan.tableInsertIndex >= 0 && plan.tableInsertIndex < table.count {
                    plan.renumberFrom = plan.songId
                    plan.renumberBelow = plan.migrateFromIndex >= 0 ? plan.migrateFromIndex : Int.max
                }
            }
        }
        let stem = "#define " + constant
        plan.songsHLine = stem + String(repeating: " ", count: max(1, valueColumn - stem.utf16.count))
            + String(plan.songId)
        let ld = RegistrationText.lines(root, "ld_script.ld")
        let ldSample = ld.last { $0.contains("sound/songs/midi/") }
        plan.ldApplicable = ldSample != nil
        if let ldSample, let range = ldSample.range(of: "sound/songs/midi/") {
            plan.ldLine = String(ldSample[..<range.lowerBound]) + "sound/songs/midi/\(label).o(.rodata);"
        }
        let names = RegistrationText.constantNames(root)
        var equalsColumn = -1
        var aligned = true
        for line in RegistrationText.lines(root, "charmap.txt") {
            guard let value = RegistrationText.match(RegistrationText.charmap, line),
                  names.contains(value.group(1)) else { continue }
            plan.charmapApplicable = true
            if equalsColumn < 0 { equalsColumn = value.end(2) }
            else if value.end(2) != equalsColumn { aligned = false }
        }
        if plan.charmapApplicable {
            plan.charmapLine = constant + String(repeating: " ", count: aligned
                ? max(1, equalsColumn - constant.utf16.count) : 1) + "= " + RegistrationText.bytes(plan.songId)
        }
        plan.debugApplicable = !DebugSoundLists(debug).lists.isEmpty
        return plan
    }
}

private func songCatalogPlayerNumber(root: String, name: String) -> Int {
    var result = 0
    for line in RegistrationText.lines(root, "sound/song_table.inc") {
        guard let entry = RegistrationText.match(#"^\s*\.equiv\s+(\w+)\s*,\s*(\d+)"#, line),
              entry.group(1) == name else { continue }
        result = Int(entry.group(2)) ?? 0
    }
    return result
}
