import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawProjectNative
import PorydawPlayback

// New Voicegroup at the service/file level: the per-file copy loads with the source voices,
// the hub grows one include line, and collisions refuse without touching bytes.

@MainActor
internal func runVoicegroupCreationChecks(_ report: CheckReport, fixtureRoot: String) {
    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-voicegroup-create")
    let seedRelative = "sound/voicegroups/seed_src.inc"
    let seedBytes = Data(
        """
        .align 2
        voice_group seed_src
        \tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0
        \tvoice_square_2 60, 0, 1, 3, 2, 11, 4
        \tvoice_noise 60, 0, 1, 2, 2, 10, 3

        """.utf8)
    do {
        try seedBytes.write(to: URL(fileURLWithPath: projectDir).appendingPathComponent(seedRelative))
    } catch {
        report.fail("voicegroupsourceediting/fixture", "copy-source seed failed: \(error)")
        return
    }
    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: projectDir) }
    } catch {
        report.fail("voicegroupsourceediting/fixture", "project open failed: \(error)")
        return
    }
    let hubURL = URL(fileURLWithPath: projectDir).appendingPathComponent("sound/voice_groups.inc")
    let hubBefore: Data
    do {
        hubBefore = try Data(contentsOf: hubURL)
    } catch {
        report.fail("voicegroupsourceediting/fixture", "hub read failed: \(error)")
        return
    }
    let createdURL = URL(fileURLWithPath: projectDir)
        .appendingPathComponent("sound/voicegroups/qtest_copy.inc")
    do {
        try runBlocking {
            try await service.createVoicegroup(
                name: "qtest_copy", copyFromFile: seedRelative,
                copySectionLabel: "")
        }
    } catch {
        report.fail("voicegroupsourceediting/A086", "creation failed: \(error)")
        return
    }
    var expectedCreated = Data("voice_group qtest_copy\n".utf8)
    expectedCreated += seedBytes.dropFirst("voice_group seed_src\n".utf8.count + ".align 2\n".utf8.count)
    let createdBytes = (try? Data(contentsOf: createdURL)) ?? Data()
    report.expect(
        createdBytes == expectedCreated, cppID: "voicegroupsourceediting/A086",
        message: "A086: createVoicegroup writes the per-file copy with the source voices")
    let hubAfterCreate = (try? Data(contentsOf: hubURL)) ?? Data()
    let includeLine = Data(".include \"sound/voicegroups/qtest_copy.inc\"".utf8)
    let includeCount = hubAfterCreate.split(separator: 10).filter {
        $0.contains(includeLine)
    }.count
    report.expect(
        includeCount == 1, cppID: "voicegroupsourceediting/A087",
        message: "A087: appendIncludeLine adds exactly one hub include for the created group")
    guard let created = creationLoad(root: projectDir, name: "qtest_copy"),
        let source = creationLoad(root: projectDir, name: "seed_src")
    else {
        report.fail("voicegroupsourceediting/A088", "native loader did not resolve the created group")
        return
    }
    defer {
        voicegroup_free(created)
        voicegroup_free(source)
    }
    let namesMatch = (0..<3).allSatisfy {
        creationVoiceName(created, $0) == creationVoiceName(source, $0)
    }
    let typesMatch =
        creationTone(created, 0).type == creationTone(source, 0).type
        && creationTone(created, 0).type != 0
    report.expect(
        namesMatch && typesMatch, cppID: "voicegroupsourceediting/A089",
        message: "A089: the created slots keep the source voices with their parsed names")
    let tonesMatch = (0..<3).allSatisfy {
        creationSameTone(creationTone(created, $0), creationTone(source, $0))
    }
    report.expect(
        tonesMatch, cppID: "voicegroupsourceediting/A090",
        message: "A090: the created tones equal the source bank's resolved tones")
    do {
        let args = try runBlocking { try await service.voicegroupArgs() }
        report.expect(
            args.contains("_qtest_copy"), cppID: "voicegroupsourceediting/A091",
            message: "A091: voicegroupArgs publishes the created _qtest_copy arg")
    } catch {
        report.fail("voicegroupsourceediting/A091", "voicegroupArgs failed: \(error)")
    }
    report.expect(
        creationLineCount(hubAfterCreate) == creationLineCount(hubBefore) + 1,
        cppID: "voicegroupsourceediting/A092",
        message: "A092: the hub gains exactly one line for the created group")

    let strayRelative = "sound/voicegroups/qtest_stray.inc"
    let strayBytes = Data("do not overwrite this voicegroup stray".utf8)
    let strayURL = URL(fileURLWithPath: projectDir).appendingPathComponent(strayRelative)
    do {
        try strayBytes.write(to: strayURL)
    } catch {
        report.fail("voicegroupsourceediting/fixture", "stray seed failed: \(error)")
        return
    }
    let argsBeforeCollision = (try? runBlocking { try await service.voicegroupArgs() }) ?? []
    var refusal: ProjectServiceError?
    do {
        try runBlocking {
            try await service.createVoicegroup(name: "qtest_stray", copyFromFile: "", copySectionLabel: "")
        }
    } catch {
        refusal = error as? ProjectServiceError
    }
    let collisionID = "swiftcore/VoicegroupCreation::collisionRefusesLeavingStray"
    let typedRefusal: Bool
    if case .operationFailed? = refusal { typedRefusal = true } else { typedRefusal = false }
    report.expect(
        typedRefusal, cppID: collisionID,
        message: "the colliding create returns a typed project command failure")
    let refusalMessage: String
    if case let .operationFailed(message)? = refusal { refusalMessage = message } else { refusalMessage = "" }
    report.expect(
        !refusalMessage.isEmpty && refusalMessage.contains("qtest_stray"), cppID: collisionID,
        message: "the collision failure names its voicegroup in a nonempty message")
    let preservedStray = (try? Data(contentsOf: strayURL)) ?? Data()
    report.expect(
        preservedStray == strayBytes, cppID: collisionID,
        message: "the refusal preserves every byte of the independently seeded stray")
    let hubAfterCollision = (try? Data(contentsOf: hubURL)) ?? Data()
    report.expect(
        hubAfterCollision == hubAfterCreate, cppID: collisionID,
        message: "the refusal leaves the hub bytes untouched")
    let argsAfterCollision = (try? runBlocking { try await service.voicegroupArgs() }) ?? []
    report.expect(
        argsAfterCollision == argsBeforeCollision, cppID: collisionID,
        message: "the refusal leaves the voicegroup catalog unchanged")
}

private func creationLoad(root: String, name: String) -> UnsafeMutablePointer<LoadedVoiceGroup>? {
    root.withCString { rootPath in
        name.withCString { loadName in voicegroup_load(rootPath, loadName, nil) }
    }
}

private func creationTone(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ slot: Int) -> ToneData {
    withUnsafePointer(to: &bank.pointee.voices) {
        $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[slot] }
    }
}

private func creationVoiceName(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ slot: Int) -> String {
    withUnsafePointer(to: &bank.pointee.voiceNames) {
        $0.withMemoryRebound(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN)) {
            String(cString: $0.advanced(by: slot * Int(VG_VOICE_NAME_LEN)))
        }
    }
}

private func creationSameTone(_ actual: ToneData, _ expected: ToneData) -> Bool {
    actual.type == expected.type && actual.key == expected.key
        && actual.length == expected.length && actual.panSweep == expected.panSweep
        && actual.attack == expected.attack && actual.decay == expected.decay
        && actual.sustain == expected.sustain && actual.release == expected.release
}

private func creationLineCount(_ bytes: Data) -> Int {
    bytes.split(separator: 10, omittingEmptySubsequences: false).count
}
