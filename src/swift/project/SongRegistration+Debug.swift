import Foundation

struct DebugSoundLists {
    struct List {
        var name: String
        var defineLine: Int
        var indices: [Int] = []
        var names: [String] = []
        var indent = "    "
        var named = false
        var commaColumn = -1
        var parenColumn = -1
        var slashColumn = -1
    }

    var lists: [List] = []

    init(_ lines: [String]) {
        var index = 0
        while index < lines.count {
            guard let define = RegistrationText.match(RegistrationText.soundList, lines[index])
            else {
                index += 1
                continue
            }
            var list = List(name: define.group(1), defineLine: index)
            var commaAligned = true
            var parenAligned = true
            var slashAligned = true
            var previousComma = -1
            var previousParen = -1
            var previousSlash = -1
            while index + 1 < lines.count && Self.continues(lines[index]) {
                index += 1
                guard let entry = RegistrationText.match(RegistrationText.soundListEntry, lines[index])
                else { continue }
                list.indices.append(index)
                list.names.append(entry.group(2))
                list.indent = entry.group(1)
                if entry.start(3) != NSNotFound {
                    list.named = true
                    let comma = entry.start(3)
                    let paren = entry.end(3)
                    if previousComma >= 0 && previousComma != comma { commaAligned = false }
                    if previousParen >= 0 && previousParen != paren { parenAligned = false }
                    previousComma = comma
                    previousParen = paren
                }
                if !entry.group(4).isEmpty {
                    let slash = (lines[index] as NSString).range(of: "\\", options: .backwards).location
                    if previousSlash >= 0 && previousSlash != slash { slashAligned = false }
                    previousSlash = slash
                }
            }
            list.commaColumn = commaAligned ? previousComma : -1
            list.parenColumn = parenAligned ? previousParen : -1
            list.slashColumn = slashAligned ? previousSlash : -1
            lists.append(list)
            index += 1
        }
    }

    static func continues(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("\\")
    }

    static func stripContinuation(_ line: String) -> String {
        guard let slash = line.lastIndex(of: "\\") else { return line }
        var text = String(line[..<slash])
        while text.last == " " { text.removeLast() }
        return text
    }

    static func continuation(_ text: String, column: Int) -> String {
        text + String(repeating: " ", count: max(1, column - text.utf16.count)) + "\\"
    }

    func target(constant: String, forceBgm: Bool) -> List? {
        let name = !forceBgm && constant.hasPrefix("SE_") ? "SOUND_LIST_SE" : "SOUND_LIST_BGM"
        return lists.last(where: { $0.name == name }) ?? lists.first
    }

    func entry(constant: String, style: List) -> String {
        var text = style.indent + "X(" + constant
        if style.named {
            let display = constant.replacingOccurrences(of: "_", with: "-")
            text += String(repeating: " ", count: max(0, style.commaColumn - text.utf16.count))
            text += ", \"" + display + "\""
            text += String(repeating: " ", count: max(0, style.parenColumn - text.utf16.count))
        }
        return text + ")"
    }

    static func insert(root: String, constant: String, plan: RegistrationPlan) throws {
        let path = root + "/src/debug.c"
        var file = try RegistrationLines(path: path)
        let scan = DebugSoundLists(file.texts)
        guard !scan.lists.contains(where: { $0.names.contains(constant) }),
              let target = scan.target(constant: constant, forceBgm: plan.debugUseBgmList)
        else { return }
        let style = target.names.isEmpty
            ? scan.lists.first(where: { !$0.names.isEmpty }) ?? target : target
        let ids = Dictionary(RegistrationText.lines(root, "include/constants/songs.h").compactMap { line
            -> (String, Int)? in
            guard let match = RegistrationText.match(RegistrationText.define, line),
                  let id = Int(match.group(3)) else { return nil }
            return (match.group(2), id)
        }, uniquingKeysWith: { first, _ in first })
        var after = -1
        for index in target.names.indices where (ids[target.names[index]] ?? Int.max) < plan.songId {
            after = index
        }
        let at = after >= 0 ? target.indices[after] + 1 : target.indices.first ?? target.defineLine + 1
        let bare = scan.entry(constant: constant, style: style)
        if Self.continues(file.text(at - 1)) {
            file.insert(at, continuation(bare, column: style.slashColumn))
        } else {
            file.replace(at - 1, continuation(file.text(at - 1), column: style.slashColumn))
            file.insert(at, bare)
        }
        try file.save(path)
    }

    static func remove(root: String, constant: String) throws {
        let path = root + "/src/debug.c"
        guard var file = try? RegistrationLines(path: path) else { return }
        let scan = DebugSoundLists(file.texts)
        for list in scan.lists {
            guard let entry = list.names.firstIndex(of: constant) else { continue }
            let line = list.indices[entry]
            if !continues(file.text(line)) {
                file.replace(line - 1, stripContinuation(file.text(line - 1)))
            }
            file.remove(line)
            try file.save(path)
            return
        }
    }
}
