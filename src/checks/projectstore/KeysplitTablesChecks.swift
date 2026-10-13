import Foundation
import PorydawVoicegroup
import PorydawProject

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
    keysplitWriterChecks(report)
    kitUsageScannerChecks(report)
    sampleUsageScannerChecks(report)
}

private func keysplitWriterChecks(_ report: CheckReport) {
    let id = "swiftcore/KeysplitTableWriter::"
    do {
        try withTempProjectCopy(prefix: "keysplits-writer", stagedFile: "sound/keysplit_tables.inc") { root in
            let path = root.appendingPathComponent("sound/keysplit_tables.inc").path
            let original = try ProjectFileStore.read(path)
            let fixture = try KeysplitTables.parse(files: [path])
            guard let table = fixture.table(named: "keysplit_fixture") else {
                report.fail(id + "fixture", "fixture table is missing")
                return
            }
            try KeysplitTableWriter.replace(table: table, inFile: path)
            let roundTrip = try KeysplitTables.parse(files: [path]).table(named: table.name)?.table
            report.expectEqual(
                expected: table.table, actual: roundTrip,
                cppID: id + "round-trip", what: "fixture round-trips all 128 bytes")
            let prefix = Data("\t.align 2\n".utf8)
            let siblingMarker = Data("\n\t.align 2\nkeysplit fixture_bass".utf8)
            guard let siblingStart = original.range(of: siblingMarker)?.lowerBound else {
                report.fail(id + "fixture", "sibling block is missing")
                return
            }
            let sibling = Data(original[siblingStart...])
            let values = (0..<128).map { (note: Int) -> UInt8 in UInt8((note / 16) % 3) }
            let edited = KeysplitTable(name: table.name, startingNote: 0, maxNote: 128, table: values)
            try KeysplitTableWriter.replace(table: edited, inFile: path)
            let replaced = try ProjectFileStore.read(path)
            report.expect(
                replaced.starts(with: prefix) && replaced.suffix(sibling.count) == sibling,
                cppID: id + "siblings", message: "replacement preserves prefix alignment and sibling bytes")
            let replacementTable = try KeysplitTables.parse(files: [path]).table(named: table.name)?.table
            report.expectEqual(
                expected: values, actual: replacementTable,
                cppID: id + "replace", what: "edited maximal runs round-trip")
            let appended = KeysplitTable(name: "keysplit_writer_new", startingNote: 0, maxNote: 128, table: values)
            try KeysplitTableWriter.replace(table: appended, inFile: path)
            let appendedBytes = try ProjectFileStore.read(path)
            report.expect(
                appendedBytes.starts(with: replaced), cppID: id + "append-preserves",
                message: "append preserves every existing byte")
            let appendedTable = try KeysplitTables.parse(files: [path]).table(named: appended.name)?.table
            report.expectEqual(
                expected: values, actual: appendedTable,
                cppID: id + "append", what: "appended table parses")
            let crlf = Data(
                String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8)
            try ProjectFileStore.write(path, data: crlf)
            try KeysplitTableWriter.replace(table: edited, inFile: path)
            let crlfText = String(decoding: try ProjectFileStore.read(path), as: UTF8.self)
            report.expect(
                !crlfText.replacingOccurrences(of: "\r\n", with: "").contains("\n"),
                cppID: id + "crlf", message: "replaced directives retain CRLF")
            try ProjectFileStore.write(path, data: Data(crlf.dropLast(2)))
            try KeysplitTableWriter.replace(table: appended, inFile: path)
            let unterminated = try ProjectFileStore.read(path)
            report.expectEqual(
                expected: false, actual: unterminated.last == 10,
                cppID: id + "trailing-newline", what: "append preserves a missing trailing newline")
            let setText =
                "before::\n\t.align 2\n.set keysplit_fixture, . - 12\n\t.byte 1, 1\n\nafter::\n\t.align 2\nkeysplit sibling, 0\n\tsplit 2, 128\n"
            try ProjectFileStore.write(path, data: Data(setText.utf8))
            var truncated = [UInt8](repeating: 0, count: 128)
            for note in 12..<32 { truncated[note] = 4 }
            let short = KeysplitTable(name: table.name, startingNote: 12, maxNote: 32, table: truncated)
            try KeysplitTableWriter.replace(table: short, inFile: path)
            let shortBytes = try ProjectFileStore.read(path)
            let shortTable = try KeysplitTables.parse(files: [path]).table(named: short.name)?.table
            report.expectEqual(
                expected: truncated, actual: shortTable,
                cppID: id + "truncation", what: "notes above maxNote remain zero")
            let shortText = String(decoding: shortBytes, as: UTF8.self)
            report.expect(
                shortText.hasPrefix("before::\n\t.align 2\nkeysplit fixture, 12\n\tsplit 4, 32\n")
                    && shortText.hasSuffix("\nafter::\n\t.align 2\nkeysplit sibling, 0\n\tsplit 2, 128\n")
                    && !shortText.contains(".byte"),
                cppID: id + "set-replace",
                message: "set definition becomes run form without altering labels or siblings")
            do {
                try KeysplitTableWriter.replace(table: table, inFile: path + ".missing")
                report.fail(id + "missing", "missing file was accepted")
            } catch let error as KeysplitWriteError {
                report.expect(
                    error.message.contains(path + ".missing"), cppID: id + "missing", message: "refusal names file")
            }
        }
    } catch {
        report.fail(id + "fixture", "writer checks: \(error)")
    }
}

private func kitUsageScannerChecks(_ report: CheckReport) {
    let id = "swiftcore/KitUsageScanner::"
    do {
        try withTempProjectCopy(prefix: "kit-usage") { root in
            func usage(_ symbol: String, table: String? = nil, excluding: String = "") -> [String] {
                KitUsageScanner.usage(
                    projectRoot: root.path, subgroupSymbol: symbol, tableName: table, excludingSection: excluding)
            }
            report.expectEqual(
                expected: ["voicegroup_fixture_rich"], actual: usage("fixture_drums_a"),
                cppID: id + "subgroup", what: "fixture parent references drumkit")
            report.expectEqual(
                expected: [], actual: usage("fixture_drums_a", excluding: "voicegroup_fixture_rich"),
                cppID: id + "exclude", what: "scanner excludes own canonical parent section")
            report.expectEqual(
                expected: ["voicegroup_fixture_rich"], actual: usage("not_a_subgroup", table: "keysplit_fixture"),
                cppID: id + "table", what: "keysplit table argument matches independently of subgroup")
            report.expectEqual(
                expected: ["voicegroup_fixture_rich"], actual: usage("fixture_keys"),
                cppID: id + "keysplit-symbol", what: "keysplit subgroup argument is detected")
            let scratch = root.appendingPathComponent("sound/nested/kit_usage.inc").path
            try ProjectFileStore.mkpath(root.appendingPathComponent("sound/nested").path)
            let text = """
                @ voice_keysplit_all fixture_drums_a
                // voice_keysplit fixture_keys, keysplit_fixture
                alpha_section::
                    voice_keysplit_all fixture_drums_a @ real reference
                    voice_keysplit_all fixture_drums_a
                partial_section::
                    voice_keysplit_all fixture_drums_ab
                    voice_keysplit_all fixture_drums_b
                    voice_keysplit fixture_keys_extra, keysplit_fixture_extra
                    @ voice_keysplit_all comment_only
                    // voice_keysplit_all comment_only
                zeta_section::
                    voice_keysplit unrelated_subgroup, keysplit_fixture // real table reference
                """
            try ProjectFileStore.write(scratch, data: Data(text.utf8))
            report.expectEqual(
                expected: ["alpha_section"], actual: usage("fixture_drums_a", excluding: "voicegroup_fixture_rich"),
                cppID: id + "second-section", what: "deep scan finds scratch section and deduplicates its lines")
            report.expectEqual(
                expected: ["alpha_section", "voicegroup_fixture_rich", "zeta_section"],
                actual: usage("fixture_drums_a", table: "keysplit_fixture"),
                cppID: id + "sorted-union", what: "symbol and table references form a sorted section union")
            report.expectEqual(
                expected: ["zeta_section"],
                actual: usage("not_a_subgroup", table: "keysplit_fixture", excluding: "voicegroup_fixture_rich"),
                cppID: id + "table-boundary", what: "partial table names do not match")
            report.expectEqual(
                expected: [], actual: usage("comment_only"),
                cppID: id + "comments", what: "commented macros never reference a kit")
            report.expectEqual(
                expected: ["partial_section"], actual: usage("fixture_drums_b", excluding: "voicegroup_fixture_rich"),
                cppID: id + "symbol-boundary", what: "drums_b is distinct from drums_a and drums_ab")
            report.expectEqual(
                expected: "voicegroup_fixture_rich",
                actual: try KitUsageScanner.canonicalSection(
                    projectRoot: root.path, sourceRelativePath: "sound/voicegroups/fixture_rich.inc", sectionLabel: ""),
                cppID: id + "canonical-per-file",
                what: "per-file identity resolves its sole declaration, not a filename alias")
            var ambiguousRefused = false
            do {
                _ = try KitUsageScanner.canonicalSection(
                    projectRoot: root.path, sourceRelativePath: "sound/nested/kit_usage.inc", sectionLabel: "")
            } catch let error as KitUsageScanError {
                ambiguousRefused = error.file == scratch
            }
            report.expectEqual(
                expected: true, actual: ambiguousRefused, cppID: id + "canonical-ambiguous",
                what: "a multi-declaration source refuses ambiguous parent identity and names the file")
            let labeled = """
                raw_parent::
                    voice_group raw_parent
                    voice_keysplit_all labeled_child
                """
            let labeledPath = root.appendingPathComponent("sound/nested/labeled_kit.inc").path
            try ProjectFileStore.write(labeledPath, data: Data(labeled.utf8))
            report.expectEqual(
                expected: ["raw_parent"], actual: usage("labeled_child"),
                cppID: id + "labeled-usage", what: "usage scanner attributes a labeled macro to that same section")
        }
    } catch {
        report.fail(id + "fixture", "usage scanner checks: \(error)")
    }
}

private func sampleUsageScannerChecks(_ report: CheckReport) {
    let id = "swiftcore/SampleUsageScanner::staged-references"
    do {
        try withTempProjectCopy(prefix: "sample-usage") { root in
            try VoicegroupSource.createVoicegroup(
                projectRoot: root.path, name: "usage_created", copyFromFile: "", copySectionLabel: "")
            let subgroup = "voicegroup_usage_created"
            let candidates: Set<String> = ["usage_kept", "usage_free"]
            let child = VgVoice(macro: .directSound, symbol: "DirectSoundWaveData_usage_kept")
            let parent = VgVoice(macro: .keysplitAll, symbol: subgroup)
            var overlay: [String: [VgVoice?]] = [
                "voicegroup_usage_parent": [parent], subgroup: [child],
            ]
            let referenced = try SampleUsageScanner.referenced(
                projectRoot: root.path, candidates: candidates, overlay: overlay, createdSubgroups: [subgroup])
            overlay["voicegroup_usage_parent"] = [nil]
            let undone = try SampleUsageScanner.referenced(
                projectRoot: root.path, candidates: candidates, overlay: overlay, createdSubgroups: [subgroup])
            overlay.removeValue(forKey: "voicegroup_usage_parent")
            let noRoot = try SampleUsageScanner.referenced(
                projectRoot: root.path, candidates: candidates, overlay: overlay, createdSubgroups: [subgroup])
            report.expectEqual(
                expected: [["usage_kept"], [], []],
                actual: [referenced.sorted(), undone.sorted(), noRoot.sorted()], cppID: id,
                what: "staged references count; undo and an unreachable created subgroup do not")
        }
    } catch {
        report.fail(id, "sample reference scan: \(error)")
    }
}
