import Foundation
import PorydawBackups
import Testing

private func withBackupRoot(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "midi-backups-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
}

private func backupContents(in root: URL, songName: String) throws -> [String: Data] {
    let folder = root.appendingPathComponent(songName, isDirectory: true)
    guard FileManager.default.fileExists(atPath: folder.path) else { return [:] }
    let files = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    var contents: [String: Data] = [:]
    for file in files {
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else { continue }
        contents[file.lastPathComponent] = try Data(contentsOf: file)
    }
    return contents
}

@Suite("MIDI backup storage")
struct MidiBackupStoreTests {
    @Test
    func unicodeSongNamesShareOneFlatFolderAndImmutableOriginal() async throws {
        try await withBackupRoot { root in
            let store = MidiBackupStore(root: root)
            let other = MidiBackupStore(root: root)
            let songName = "Même chanson 雪"
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            let original: [UInt8] = [0, 255, 77, 84, 104, 100, 0, 1]
            let directory = try await store.directory()
            #expect(directory == root)
            try await store.preserveOriginal(songName: songName, bytes: original, at: epoch)
            try await other.preserveOriginal(songName: songName, bytes: [99], at: epoch)
            try await other.record(songName: songName, bytes: [42], at: epoch)
            let restarted = MidiBackupStore(root: root)
            try await restarted.preserveOriginal(songName: songName, bytes: [98], at: epoch)
            let folders = try FileManager.default.contentsOfDirectory(atPath: root.path)
            let contents = try backupContents(in: root, songName: songName)
            #expect(folders == [songName])
            #expect(contents == ["\(songName)1.mid": Data(original), "\(songName)2.mid": Data([42])])
        }
    }

    @Test
    func retentionUsesRecentIncrementsAndActiveUTCDaysAcrossRestartAndClockRollback() async throws {
        try await withBackupRoot { root in
            let store = MidiBackupStore(root: root)
            let songName = "Même chanson 雪"
            let originalName = "\(songName)1.mid"
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            let original: [UInt8] = [0, 255, 77, 84, 104, 100, 0, 1]
            try await store.preserveOriginal(songName: songName, bytes: original, at: epoch)
            try await store.record(songName: songName, bytes: [42], at: epoch)
            for day in 0..<35 {
                for slot in 0..<2 {
                    let index = day * 2 + slot
                    let at = epoch.addingTimeInterval(Double(day * 86_400 + slot * 3_600))
                    try await store.record(songName: songName, bytes: [UInt8(index)], at: at)
                }
            }
            var expected = [originalName: Data(original)]
            let retainedIndices = Set((5..<35).map { $0 * 2 }).union(60..<70)
            for index in retainedIndices { expected["\(songName)\(index + 3).mid"] = Data([UInt8(index)]) }
            let retained = try backupContents(in: root, songName: songName)
            #expect(retained == expected)

            let farFuture = epoch.addingTimeInterval(1_000 * 86_400)
            let restarted = MidiBackupStore(root: root)
            try await restarted.preserveOriginal(songName: songName, bytes: [99], at: farFuture)
            try await restarted.record(songName: songName, bytes: [69], at: farFuture)
            let afterDuplicate = try backupContents(in: root, songName: songName)
            #expect(afterDuplicate == retained)
            try await restarted.record(songName: songName, bytes: [70], at: farFuture)
            expected = [originalName: Data(original), "\(songName)73.mid": Data([70])]
            let gapIndices = Set((6..<35).map { $0 * 2 }).union(61..<70)
            for index in gapIndices { expected["\(songName)\(index + 3).mid"] = Data([UInt8(index)]) }
            let afterGap = try backupContents(in: root, songName: songName)
            #expect(afterGap == expected)

            try await restarted.record(songName: songName, bytes: [71], at: farFuture.addingTimeInterval(3_600))
            expected = [originalName: Data(original), "\(songName)73.mid": Data([70]), "\(songName)74.mid": Data([71])]
            let finalIndices = Set((6..<35).map { $0 * 2 }).union(62..<70)
            for index in finalIndices { expected["\(songName)\(index + 3).mid"] = Data([UInt8(index)]) }
            let final = try backupContents(in: root, songName: songName)
            #expect(final == expected)
            try await restarted.record(songName: songName, bytes: [72], at: epoch)
            var expectedRollback = expected
            expectedRollback["\(songName)75.mid"] = Data([72])
            let afterClockRollback = try backupContents(in: root, songName: songName)
            #expect(afterClockRollback == expectedRollback)
        }
    }

    @Test
    func failedCreationAndOccupiedDestinationLeaveEveryPreviousFileIntact() async throws {
        try await withBackupRoot { fixture in
            let root = fixture.appendingPathComponent("storage", isDirectory: true)
            let store = MidiBackupStore(root: root)
            let songName = "failed creation"
            let folder = root.appendingPathComponent(songName, isDirectory: true)
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // An over-retention filesystem fixture makes any pruning on failure observable.
            var expected: [String: Data] = [:]
            for increment in 1...35 {
                let name = "\(songName)\(increment).mid"
                let bytes = Data([UInt8(increment)])
                let url = folder.appendingPathComponent(name)
                try bytes.write(to: url)
                try FileManager.default.setAttributes([.modificationDate: epoch], ofItemAtPath: url.path)
                expected[name] = bytes
            }
            let parked = fixture.appendingPathComponent("parked", isDirectory: true)
            try FileManager.default.moveItem(at: root, to: parked)
            try Data([1]).write(to: root)
            var failed = false
            do { try await store.record(songName: songName, bytes: [99], at: epoch) } catch { failed = true }
            #expect(failed)
            #expect(try Data(contentsOf: root) == Data([1]))
            let parkedContents = try backupContents(in: parked, songName: songName)
            #expect(parkedContents == expected)
            try FileManager.default.removeItem(at: root)
            try FileManager.default.moveItem(at: parked, to: root)

            let occupied = folder.appendingPathComponent("\(songName)36.mid", isDirectory: true)
            try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
            let sentinel = Data("occupied destination".utf8)
            try sentinel.write(to: occupied.appendingPathComponent("backup.mid"))
            failed = false
            do { try await store.record(songName: songName, bytes: [99], at: epoch) } catch { failed = true }
            #expect(failed)
            let contents = try backupContents(in: root, songName: songName)
            #expect(contents == expected)
            #expect(try Data(contentsOf: occupied.appendingPathComponent("backup.mid")) == sentinel)
            var expectedNames = Set(expected.keys)
            expectedNames.insert("\(songName)36.mid")
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(Set(names) == expectedNames)
        }
    }

    @Test
    func pruningIgnoresForeignDirectoriesSymlinksAndNoncanonicalNames() async throws {
        try await withBackupRoot { root in
            let store = MidiBackupStore(root: root)
            let songName = "foreign entries 雪"
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            let original = Data([0, 255])
            let sentinel = Data("unrelated MIDI 雪".utf8)
            try await store.preserveOriginal(songName: songName, bytes: Array(original), at: epoch)
            let folder = root.appendingPathComponent(songName, isDirectory: true)
            let foreign = folder.appendingPathComponent("snapshot-old", isDirectory: true)
            let nonregular = folder.appendingPathComponent("\(songName)2.mid", isDirectory: true)
            for directory in [foreign, nonregular] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try sentinel.write(to: directory.appendingPathComponent("backup.mid"))
            }
            let foreignNames = [
                "\(songName)004.mid", "\(songName)0.mid", "\(songName)-1.mid", "\(songName)+4.mid", ".DS_Store",
            ]
            var expected = ["\(songName)1.mid": original, "\(songName)4.mid": sentinel]
            for name in foreignNames {
                try sentinel.write(to: folder.appendingPathComponent(name))
                expected[name] = sentinel
            }
            let symlink = folder.appendingPathComponent("\(songName)3.mid")
            let target = folder.appendingPathComponent("\(songName)004.mid")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
            let firstDaily = folder.appendingPathComponent("\(songName)4.mid")
            try sentinel.write(to: firstDaily)
            try FileManager.default.setAttributes([.modificationDate: epoch], ofItemAtPath: firstDaily.path)
            for increment in 5...45 {
                try await store.record(
                    songName: songName, bytes: [UInt8(increment)],
                    at: epoch.addingTimeInterval(Double(increment * 60)))
            }
            for increment in 36...45 { expected["\(songName)\(increment).mid"] = Data([UInt8(increment)]) }
            let contents = try backupContents(in: root, songName: songName)
            #expect(contents == expected)
            #expect(try Data(contentsOf: foreign.appendingPathComponent("backup.mid")) == sentinel)
            #expect(try Data(contentsOf: nonregular.appendingPathComponent("backup.mid")) == sentinel)
            let properties = try symlink.resourceValues(forKeys: [.isSymbolicLinkKey])
            #expect(properties.isSymbolicLink == true)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path) == target.path)
            var expectedNames = Set(expected.keys)
            expectedNames.formUnion(["snapshot-old", "\(songName)2.mid", "\(songName)3.mid"])
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(Set(names) == expectedNames)
        }
    }

    @Test(arguments: ["", ".", "..", "..."])
    func invalidSongNamesRefuseBothWritesWithoutChangingPreviousFiles(songName: String) async throws {
        try await withBackupRoot { root in
            let store = MidiBackupStore(root: root)
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            try await store.record(songName: "valid", bytes: [1], at: epoch)
            for preserveOriginal in [true, false] {
                var failed = false
                do {
                    if preserveOriginal {
                        try await store.preserveOriginal(songName: songName, bytes: [2], at: epoch)
                    } else {
                        try await store.record(songName: songName, bytes: [2], at: epoch)
                    }
                } catch { failed = true }
                #expect(failed)
                let contents = try backupContents(in: root, songName: "valid")
                let folders = try FileManager.default.contentsOfDirectory(atPath: root.path)
                #expect(contents == ["valid1.mid": Data([1])])
                #expect(folders == ["valid"])
            }
        }
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func invalidTimestampsRefuseWritesAndDoNotSuppressValidationForDuplicates(timestamp: Double) async throws {
        try await withBackupRoot { root in
            let store = MidiBackupStore(root: root)
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            let invalid = Date(timeIntervalSince1970: timestamp)
            try await store.record(songName: "valid", bytes: [1], at: epoch)
            var originalFailed = false
            do { try await store.preserveOriginal(songName: "invalid timestamp", bytes: [2], at: invalid) } catch {
                originalFailed = true
            }
            #expect(originalFailed)
            let inputs: [[UInt8]] = [[1], [2]]
            for bytes in inputs {
                var failed = false
                do { try await store.record(songName: "valid", bytes: bytes, at: invalid) } catch { failed = true }
                #expect(failed)
            }
            let contents = try backupContents(in: root, songName: "valid")
            let invalidContents = try backupContents(in: root, songName: "invalid timestamp")
            #expect(contents == ["valid1.mid": Data([1])])
            #expect(invalidContents.isEmpty)
            let names = try FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent("valid").path)
            #expect(names == ["valid1.mid"])
            let invalidFolder = root.appendingPathComponent("invalid timestamp", isDirectory: true)
            if FileManager.default.fileExists(atPath: invalidFolder.path) {
                #expect(try FileManager.default.contentsOfDirectory(atPath: invalidFolder.path).isEmpty)
            }
        }
    }

    @Test(arguments: [false, true])
    func occupiedOriginalDestinationIsNotReplaced(symbolicLink: Bool) async throws {
        try await withBackupRoot { root in
            let songName = "occupied original"
            let folder = root.appendingPathComponent(songName, isDirectory: true)
            let destination = folder.appendingPathComponent("\(songName)1.mid")
            let sentinel = Data("occupied original bytes".utf8)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = root.appendingPathComponent("sentinel.mid")
            if symbolicLink {
                try sentinel.write(to: target)
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
            } else {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try sentinel.write(to: destination.appendingPathComponent("backup.mid"))
            }
            let store = MidiBackupStore(root: root)
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            var failed = false
            do { try await store.preserveOriginal(songName: songName, bytes: [99], at: epoch) } catch { failed = true }
            #expect(failed)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(names == ["\(songName)1.mid"])
            if symbolicLink {
                #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == target.path)
                #expect(try Data(contentsOf: target) == sentinel)
            } else {
                #expect(try Data(contentsOf: destination.appendingPathComponent("backup.mid")) == sentinel)
            }
        }
    }

    @Test
    func forbiddenCharactersAreReplacedWhileUnicodeAndSpacesRemain() async throws {
        try await withBackupRoot { root in
            let store = MidiBackupStore(root: root)
            let epoch = Date(timeIntervalSince1970: 1_704_067_200)
            try await store.record(songName: "Même/chanson 雪:?", bytes: [0, 255], at: epoch)
            let folders = try FileManager.default.contentsOfDirectory(atPath: root.path)
            let contents = try backupContents(in: root, songName: "Même_chanson 雪__")
            #expect(folders == ["Même_chanson 雪__"])
            #expect(contents == ["Même_chanson 雪__1.mid": Data([0, 255])])
        }
    }

    #if os(macOS) || os(Linux)
        @Test
        func unreadablePreviousBytesDoNotSuppressAnIdenticalSnapshot() async throws {
            try await withBackupRoot { root in
                let store = MidiBackupStore(root: root)
                let songName = "unreadable snapshot"
                let bytes: [UInt8] = [77, 84, 104, 100]
                let epoch = Date(timeIntervalSince1970: 1_704_067_200)
                try await store.record(songName: songName, bytes: bytes, at: epoch)
                let midi = root.appendingPathComponent(songName).appendingPathComponent("\(songName)1.mid")
                let attributes = try FileManager.default.attributesOfItem(atPath: midi.path)
                let permissions = try #require(attributes[.posixPermissions])
                defer {
                    try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: midi.path)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: midi.path)
                let wasUnreadable = (try? Data(contentsOf: midi)) == nil
                try #require(wasUnreadable)
                try await store.record(songName: songName, bytes: bytes, at: epoch.addingTimeInterval(3_600))
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: midi.path)
                let contents = try backupContents(in: root, songName: songName)
                #expect(contents == ["\(songName)1.mid": Data(bytes), "\(songName)2.mid": Data(bytes)])
            }
        }
    #endif
}
