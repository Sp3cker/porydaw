import Foundation
import PorydawProject

private struct ParallelState: Sendable {
    var completed = 0
    var succeeded = true
}

private final class ParallelActorResults: Sendable {
    private let box = ConditionBox(ParallelState())
    private let count: Int

    init(count: Int) {
        self.count = count
    }

    func record(_ outcome: Result<Void, Error>?) {
        box.update { state in
            switch outcome {
            case .some(.success):
                break
            case .some(.failure), .none:
                state.succeeded = false
            }
            state.completed += 1
        }
    }

    func wait() -> Bool {
        let state = box.wait(while: { $0.completed < count }, timeout: 60)
        return state.completed == count && state.succeeded
    }
}

internal func runProjectStoreActorSuite(_ report: CheckReport) {
    let projectRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("projectstore-actor-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: projectRoot) }
    let store = ProjectStore(projectRoot: projectRoot)
    let id = "projectstore-actor"
    let file = projectRoot.appendingPathComponent("song.mid")
    let payload = Data([0, 255, 1, 0, 127])

    do {
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    } catch {
        for site in 1...5 {
            report.fail("\(id)/A0\(site)", "could not create scratch project: \(error)")
        }
        return
    }

    let roundTrip = awaitValue {
        try await store.writeFile(file.path, data: payload)
        return try await store.readFile(file.path)
    }
    report.expect(roundTrip?.success == payload, cppID: "\(id)/A01",
                  message: "actor file write and read preserve binary bytes")

    let missing = projectRoot.appendingPathComponent("missing.mid").path
    let unreadable = awaitValue { try await store.readFile(missing) }
    if case .some(.failure(let error)) = unreadable,
       let fileError = error as? ProjectFileStoreError,
       fileError == .cannotRead(path: missing) {
        report.pass("\(id)/A02", row: "read returns the missing file path in its error")
    } else {
        report.fail("\(id)/A02", "missing file did not produce cannotRead for its path")
    }

    let count = 32
    let parallel = ParallelActorResults(count: count)
    let competing = projectRoot.appendingPathComponent("competing.mid").path
    let candidates = (0..<count).map { Data(repeating: UInt8($0), count: 262_144) }
    for candidate in candidates {
        Thread.detachNewThread {
            parallel.record(awaitValue { try await store.writeFile(competing, data: candidate) })
        }
    }
    let writesSucceeded = parallel.wait()
    let final = awaitValue { try await store.readFile(competing) }
    report.expect(writesSucceeded && final?.success.map(candidates.contains) == true,
                  cppID: "\(id)/A03",
                  message: "concurrent atomic writes leave one complete payload")

    let missingParent = projectRoot.appendingPathComponent("absent/song.mid").path
    let unwritable = awaitValue { try await store.writeFile(missingParent, data: payload) }
    if case .some(.failure(let error)) = unwritable,
       let fileError = error as? ProjectFileStoreError,
       fileError == .cannotWrite(path: missingParent),
       !FileManager.default.fileExists(atPath: missingParent) {
        report.pass("\(id)/A04", row: "write returns the destination path when its parent is missing")
    } else {
        report.fail("\(id)/A04", "missing parent did not produce cannotWrite without a file")
    }

    let sound = projectRoot.appendingPathComponent("sound", isDirectory: true)
    let groups = sound.appendingPathComponent("voicegroups", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: groups, withIntermediateDirectories: true)
        let sampleLines = """
            DirectSoundWaveData_actor::
            \t.incbin "sound/direct_sound_samples/actor.bin"
            """
        let scanned = awaitValue {
            try await store.writeFile(groups.appendingPathComponent("actor.inc").path,
                                      data: Data("voicegroup_actor::\n".utf8))
            try await store.writeFile(sound.appendingPathComponent("direct_sound_data.inc").path,
                                      data: Data(sampleLines.utf8))
            return await store.voicegroupCatalog()
        }
        report.expect(scanned?.success?.groups.groupArgs == ["_actor"]
                          && scanned?.success?.direct.directSound == ["DirectSoundWaveData_actor"],
                      cppID: "\(id)/A05",
                      message: "actor catalog scans its project root for groups and samples")
    } catch {
        report.fail("\(id)/A05", "could not create catalog fixture: \(error)")
    }
}

private extension Result {
    var success: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
