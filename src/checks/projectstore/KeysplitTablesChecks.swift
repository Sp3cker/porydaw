import Foundation
import PorydawVoicegroup

public func runKeysplitTablesSuite(_ report: CheckReport) {
    let id = "projectstore-keysplits"
    do {
        try withTempProjectCopy(prefix: "keysplits", stagedFile: "sound/keysplit_tables.inc") { root in
            let path = root.appendingPathComponent("sound/keysplit_tables.inc").path
            let fixture = try KeysplitTables.parse(files: [path])
            report.expectEqual(
                expected: ["keysplit_fixture", "keysplit_fixture_bass"],
                actual: fixture.tables.map(\.name), cppID: id, what: "fixture order")
            let treble =
                [UInt8](repeating: 0, count: 48)
                + [UInt8](repeating: 1, count: 48) + [UInt8](repeating: 2, count: 32)
            let bass = [UInt8](repeating: 0, count: 64) + [UInt8](repeating: 1, count: 64)
            report.expectEqual(
                expected: treble, actual: fixture.table(named: "keysplit_fixture")?.table ?? [],
                cppID: id, what: "fixture exact 128 bytes")
            report.expectEqual(
                expected: bass, actual: fixture.table(named: "keysplit_fixture_bass")?.table ?? [],
                cppID: id, what: "bass exact 128 bytes")

            func parse(_ text: String) throws -> KeysplitTables {
                try ProjectFileStore.write(path, data: Data(text.utf8))
                return try KeysplitTables.parse(files: [path])
            }
            let byteList = treble.map(String.init).joined(separator: ",")
            let bytes = try parse(".set keysplit_fixture, . - 0\n.byte \(byteList)\n")
            report.expectEqual(
                expected: treble, actual: bytes.tables.first?.table ?? [],
                cppID: id, what: "set byte form matches macro contents")
            report.expectEqual(
                expected: 127, actual: bytes.tables.first?.maxNote ?? -1,
                cppID: id, what: "byte maxNote is last written index")
            report.expectEqual(
                expected: 128, actual: fixture.tables.first?.maxNote ?? -1,
                cppID: id, what: "split maxNote is exclusive end")

            let duplicate = try parse(
                "split invalid\n.byte 200\nkeysplit same, 2\nsplit 3, 4\n.align 2\nunknown words\nkeysplit same, 0\nsplit 9, 128\n"
            )
            report.expectEqual(expected: 2, actual: duplicate.tables.count, cppID: id, what: "duplicates preserved")
            var first = [UInt8](repeating: 0, count: 128)
            first[2] = 3
            first[3] = 3
            report.expectEqual(
                expected: first, actual: duplicate.table(named: "keysplit_same")?.table ?? [],
                cppID: id, what: "first wins and unwritten bytes zero")
            report.expectEqual(
                expected: 2, actual: duplicate.tables.first?.startingNote ?? -1,
                cppID: id, what: "starting note preserved")

            let baseZero = try parse("keysplit  numeric , 010 @ comment\nsplit 0x7f, 0x0a // comment\n.byte , 1,, 2,\n")
            report.expectEqual(
                expected: "keysplit_numeric", actual: baseZero.tables.first?.name ?? "",
                cppID: id, what: "symbol trimming and comments")
            var numeric = [UInt8](repeating: 0, count: 128)
            numeric[8] = 127
            numeric[9] = 127
            numeric[10] = 1
            numeric[11] = 2
            report.expectEqual(
                expected: numeric, actual: baseZero.tables.first?.table ?? [],
                cppID: id, what: "base zero integers and byte separators")

            let invalid: [(String, Int)] = [
                ("keysplit bad, 60\nsplit 0, 59\n", 2),
                ("keysplit bad, 0\n.byte 200\n", 2),
                ("keysplit bad, 128\n", 1),
                ("keysplit bad, 0 trailing\n", 1),
                ("keysplit bad, 0\nsplit 128, 128\n", 2),
                ("keysplit bad, 0\nsplit 0, 129\n", 2),
                ("keysplit bad, 127\n.byte 1, 2\n", 2),
                (".set bad, 0\n", 1),
                ("keysplit \(String(repeating: "x", count: 247)), 0\n", 1),
            ]
            for (index, entry) in invalid.enumerated() {
                do {
                    _ = try parse(entry.0)
                    report.fail(id, "invalid case \(index) accepted")
                } catch let error as KeysplitParseError {
                    report.expectEqual(
                        expected: entry.1, actual: error.line, cppID: id,
                        what: "invalid case \(index) line")
                    report.expectEqual(
                        expected: path, actual: error.file, cppID: id,
                        what: "invalid case \(index) file")
                    report.expect(!error.reason.isEmpty, cppID: id, message: "invalid case reason")
                }
            }
            let ignored = try parse("keysplit\tignored, 0\nsplit\t0, 128\n.global unused\n")
            report.expect(ignored.tables.isEmpty, cppID: id, message: "literal space prefixes required")
            let other = root.appendingPathComponent("sound/keysplits-other.inc").path
            try ProjectFileStore.write(other, data: Data(".byte 200\nkeysplit next, 0\n".utf8))
            _ = try parse("keysplit first, 0\nsplit 0, 128\n")
            let files = try KeysplitTables.parse(files: [path, other])
            report.expectEqual(
                expected: ["keysplit_first", "keysplit_next"], actual: files.tables.map(\.name),
                cppID: id, what: "file order and per-file current reset")
            do {
                _ = try KeysplitTables.parse(files: [path + ".missing"])
                report.fail(id, "unreadable file accepted")
            } catch let error as KeysplitParseError {
                report.expectEqual(expected: 0, actual: error.line, cppID: id, what: "unreadable file line")
            }
        }
    } catch {
        report.fail(id, "keysplit checks: \(error)")
    }
}
