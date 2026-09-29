import Foundation
import PorydawProject
import PorydawSample

internal func runProvenanceChecks(_ report: CheckReport) {
    let hash = report.scoped(cppID: "swiftcore/SampleSourceHash::vectors")
    hash.expect(SampleSourceHash.sha256Hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", message: "SHA-256 empty FIPS vector")
    hash.expect(SampleSourceHash.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", message: "SHA-256 abc FIPS vector")
    hash.expect(SampleSourceHash.sha256Hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", message: "SHA-256 448-bit FIPS vector")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: root) }
    let project = root + "/wavproj"
    let sourcePath = root + "/sources/hires_tone.wav"
    let sourceBytes = hiResSampleWav()
    do {
        try writeWav2AgbProject(root: project)
        try FileManager.default.createDirectory(atPath: root + "/sources", withIntermediateDirectories: true)
        try sourceBytes.write(to: URL(filePath: sourcePath))
        let source = try importedHiRes()
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarRoundtrip").expect(source.frameCount > 0,
            message: "A015 sidecar-roundtrip high-resolution source imports")
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarRerender").expect(source.frameCount > 0,
            message: "A023 sidecar-rerender high-resolution source imports")
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarTouchedSource").expect(source.frameCount > 0,
            message: "A033 sidecar-touched high-resolution source imports")
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarFallback").expect(source.frameCount > 0,
            message: "A041 sidecar-fallback high-resolution source imports")
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sampleUpdate").expect(source.frameCount > 0,
            message: "A048 sample-update high-resolution source imports")
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sampleUpdateRefusals").expect(source.frameCount > 0,
            message: "A056 sample-update-refusals high-resolution source imports")
        report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarRemove").expect(source.frameCount > 0,
            message: "A067 sidecar-remove high-resolution source imports")
        var params = SampleDocument.defaultParams(for: source)
        params.cropStart = 150; params.targetRate = 13379; params.baseKey = 59; params.fineTuneCents = 25
        var document = SampleDocument(source: source)
        document.setParams(params)
        let committed = SampleWavWriter.bytes(for: document.processed)
        let name = "provenance_tone"
        let roundtrip = report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarRoundtrip")
        try SampleRegistrar.register(projectRoot: project, name: name, wav: committed)
        roundtrip.expect((try? SampleRegistrar.readCommitted(projectRoot: project, name: name).wav) == committed,
            message: "A017 provenance sample registers")
        var sidecar = SampleSidecar()
        sidecar.sourcePath = sourcePath
        sidecar.sourceSha256 = SampleSourceHash.sha256Hex(sourceBytes)
        sidecar.params = params
        try SampleRegistrar.writeSidecar(projectRoot: project, name: name, sidecar)
        roundtrip.expect(FileManager.default.fileExists(atPath: SampleRegistrar.sidecarPath(projectRoot: project, name: name)),
            message: "A018 sidecar writes")
        let back = SampleRegistrar.readSidecar(projectRoot: project, name: name)
        roundtrip.expect(back != nil, message: "A019 sidecar reads back")
        roundtrip.expect(back == sidecar, message: "A020 sidecar round-trips every field")
        let rerender = report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarRerender")
        rerender.expect((try? SampleRegistrar.readCommitted(projectRoot: project, name: name).wav) == committed,
            message: "A025 provenance sample registers")
        rerender.expect(back != nil, message: "A026 sidecar writes")
        rerender.expect(back == sidecar, message: "A027 sidecar reads back")
        rerender.expect((try? Data(contentsOf: URL(filePath: sourcePath))).map(SampleSourceHash.sha256Hex) == back?.sourceSha256,
            message: "A028 reread source matches sidecar hash")
        let resolved = try SampleReopen.resolve(wav: committed, wavPath: project + "/sound/direct_sound_samples/\(name).wav", sidecar: back)
        rerender.expect(resolved.fromSource && resolved.sample.sourcePath == sourcePath,
            message: "A029 sidecar source re-imports")
        var redoc = SampleDocument(source: resolved.sample)
        redoc.setParams(resolved.restoredParams ?? SampleEditParams())
        rerender.expect(SampleWavWriter.bytes(for: redoc.processed) == committed,
            message: "A030 sidecar re-render equals committed WAV")
        let touched = report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarTouchedSource")
        touched.expect((try? SampleRegistrar.readCommitted(projectRoot: project, name: name).wav) == committed,
            message: "A035 provenance sample registers")
        touched.expect(SampleRegistrar.readSidecar(projectRoot: project, name: name) == sidecar,
            message: "A036 sidecar writes")
        try (sourceBytes + Data(repeating: 0, count: 4)).write(to: URL(filePath: sourcePath))
        touched.expect((try? Data(contentsOf: URL(filePath: sourcePath))).map(SampleSourceHash.sha256Hex) != sidecar.sourceSha256,
            message: "A038 touched source no longer matches sidecar hash")
        let stale = try SampleReopen.resolve(wav: committed, wavPath: "x/\(name).wav", sidecar: sidecar)
        report.scoped(cppID: "swiftcore/SampleReopen::changedSource").expect(
            !stale.fromSource && stale.restoredParams == nil,
            message: "touched source falls back without stale params")
        try FileManager.default.removeItem(atPath: sourcePath)
        let missing = try SampleReopen.resolve(wav: committed, wavPath: "x/\(name).wav", sidecar: sidecar)
        report.scoped(cppID: "swiftcore/SampleReopen::missingSource").expect(
            !missing.fromSource && missing.sidecar == nil,
            message: "missing source falls back to committed WAV")
        let fallback = report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarFallback")
        fallback.expect((try? SampleRegistrar.readCommitted(projectRoot: project, name: name).wav) == committed,
            message: "A042 provenance sample registers")
        let plain = try SampleReopen.resolve(wav: committed, wavPath: "x/\(name).wav", sidecar: nil)
        fallback.expect(!plain.fromSource && plain.sample.frameCount > 0, message: "A043 committed WAV re-imports")
        fallback.expect(plain.sample.gbaReady, message: "A044 committed WAV re-imports GBA-ready")
        var fallbackDoc = SampleDocument(source: plain.sample)
        fallbackDoc.setParams(SampleDocument.defaultParams(for: plain.sample))
        fallback.expect(SampleWavWriter.bytes(for: fallbackDoc.processed) == committed,
            message: "A045 committed WAV re-renders byte-identically")
        let update = report.scoped(cppID: "samplecheck/SampleProcessingTest::sampleUpdate")
        update.expect((try? SampleRegistrar.readCommitted(projectRoot: project, name: name).wav) == committed,
            message: "A049 provenance sample registers")
        params.fineTuneCents = 40
        document.setParams(params)
        let updated = SampleWavWriter.bytes(for: document.processed)
        update.expect(updated != committed, message: "A050 changed tuning changes output")
        let inc = project + "/sound/direct_sound_data.inc"
        let incBefore = try Data(contentsOf: URL(filePath: inc))
        try SampleRegistrar.update(projectRoot: project, name: name, wav: updated)
        update.expect((try? SampleRegistrar.readCommitted(projectRoot: project, name: name).wav) == updated,
            message: "A051 update succeeds")
        update.expect((try? Data(contentsOf: URL(filePath: inc))) == incBefore, message: "A052 update preserves assembly bytes")
        update.expect((try? Data(contentsOf: URL(filePath: project + "/sound/direct_sound_samples/\(name).wav"))) == updated,
            message: "A053 update rewrites WAV bytes")
        let refused = report.scoped(cppID: "samplecheck/SampleProcessingTest::sampleUpdateRefusals")
        let first = Result { try SampleRegistrar.update(projectRoot: project, name: "never_registered", wav: updated) }
        let binBlock = Data("\n\t.align 2\nDirectSoundWaveData_binonly::\n\t.incbin \"sound/direct_sound_samples/binonly.bin\"\n".utf8)
        var assembly = incBefore; assembly.append(binBlock)
        try assembly.write(to: URL(filePath: inc))
        let second = Result { try SampleRegistrar.update(projectRoot: project, name: "binonly", wav: updated) }
        refused.expect({ if case .failure = first { return true }; return false }(), message: "A058 unregistered update refuses")
        refused.expect({ if case .failure(let error) = first { return (error as? SampleRegistrationError)?.message.isEmpty == false }; return false }(), message: "A059 unregistered refusal explains why")
        let binOnly = report.scoped(cppID: "swiftcore/SampleRegistrar::binOnlyUpdate")
        binOnly.expect({ if case .failure = second { return true }; return false }(),
            message: "bin-only registered sample refuses update")
        binOnly.expect({ if case .failure(let error) = second { return (error as? SampleRegistrationError)?.message.contains(".wav source") == true }; return false }(),
            message: "bin-only refusal names missing WAV")
        let remove = report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarRemove")
        let removeName = "remove_tone"
        let removalRegistration = Result {
            try SampleRegistrar.register(projectRoot: project, name: removeName, wav: committed)
        }
        remove.expect({ if case .success = removalRegistration { return true }; return false }(),
            message: "A069 provenance sample registers for removal")
        let rewrite = Result { try SampleRegistrar.writeSidecar(projectRoot: project, name: removeName, sidecar) }
        remove.expect({ if case .success = rewrite { return true }; return false }(),
            message: "A070 sidecar writes")
        report.scoped(cppID: "swiftcore/SampleRegistrar::sidecarRemoval").expect(
            SampleRegistrar.readSidecar(projectRoot: project, name: removeName) == sidecar,
            message: "sidecar present before removal")
        SampleRegistrar.removeSidecar(projectRoot: project, name: removeName)
        remove.expect(SampleRegistrar.readSidecar(projectRoot: project, name: removeName) == nil,
            message: "A071 removed sidecar no longer reads")
        let sf2 = soundFontFixture()
        let sf2Path = root + "/sources/zone.sf2"
        try sf2.bytes.write(to: URL(filePath: sf2Path))
        var sf2Sidecar = sidecar
        sf2Sidecar.sourcePath = sf2Path
        sf2Sidecar.sourceSha256 = SampleSourceHash.sha256Hex(sf2.bytes)
        sf2Sidecar.sf2Zone = 0
        let zoned = try SampleReopen.resolve(wav: committed, wavPath: "x/\(name).wav", sidecar: sf2Sidecar)
        report.scoped(cppID: "swiftcore/SampleReopen::soundFont").expect(
            zoned.fromSource && zoned.sample.sourceKind == .sf2 && zoned.restoredParams == sidecar.params,
            message: "unchanged SoundFont source reopens the selected zone and parameters")
        sf2Sidecar.sf2Zone = 10_000
        let invalidZone = try SampleReopen.resolve(wav: committed, wavPath: "x/\(name).wav", sidecar: sf2Sidecar)
        report.scoped(cppID: "swiftcore/SampleReopen::soundFont").expect(
            !invalidZone.fromSource && invalidZone.sample.gbaReady && invalidZone.restoredParams == nil,
            message: "invalid SoundFont zone falls back to committed WAV")
        provenanceCodecChecks(report, root: root, sidecar: sidecar)
    } catch {
        report.scoped(cppID: "swiftcore/SampleProvenance::fixture").expect(false,
            message: "provenance fixture failed: \(error)")
    }
}

private func provenanceCodecChecks(_ report: CheckReport, root: String, sidecar: SampleSidecar) {
    let check = report.scoped(cppID: "swiftcore/SampleSidecar::codec")
    let literal = """
    {"version":1,"source":{"path":"/tmp/source.wav","sha256":"abc","leftOnly":true,"sf2Zone":2.0},"params":{"cropStart":150.0,"cropEnd":5e2,"loopOn":true,"loopStart":180.0,"loopEnd":4.5e2,"baseKey":59.0,"fineTuneCents":25,"targetRate":13379,"normalizeMode":99.0,"dcRemove":-3.0,"exactPitchOverride":4294967295.0}}
    """
    let decoded = SampleSidecar.decode(Data(literal.utf8))
    check.expect(decoded?.params.normalizeMode == .off && decoded?.params.dcRemove == .auto
        && decoded?.params.fadeIn == true && decoded?.params.fadeOut == true
        && decoded?.params.exactPitchOverride == UInt32.max && decoded?.leftOnly == true && decoded?.sf2Zone == 2,
        message: "fork JSON literal restores defaults, bounds, channel, zone, and pitch")
    check.expect(decoded?.params.cropStart == 150 && decoded?.params.cropEnd == 500
        && decoded?.params.loopStart == 180 && decoded?.params.loopEnd == 450
        && decoded?.params.baseKey == 59,
        message: "fork JSON floating-point and exponent numeric tokens preserve integer parameters")
    check.expect(SampleSidecar.decode(Data("{\"version\":2}".utf8)) == nil,
        message: "unsupported sidecar version refuses")
    check.expect(SampleSidecar.decode(Data("{\"version\":1,\"source\":{},\"params\":{}}".utf8)) == nil,
        message: "missing source identity refuses")
    let project = root + "/gitignoreproject"
    do {
        try FileManager.default.createDirectory(atPath: project + "/.git", withIntermediateDirectories: true)
        try Data("build/\r\nlast-pattern".utf8).write(to: URL(filePath: project + "/.gitignore"))
        try SampleRegistrar.writeSidecar(projectRoot: project, name: "one", sidecar)
        try SampleRegistrar.writeSidecar(projectRoot: project, name: "two", sidecar)
        check.expect((try? Data(contentsOf: URL(filePath: project + "/.gitignore"))) == Data("build/\r\nlast-pattern\r\n.porydaw/\r\n".utf8),
            message: "gitignore retains CRLF, repairs newline, and adds rule once")
        let noGit = root + "/no-git-project"
        try SampleRegistrar.writeSidecar(projectRoot: noGit, name: "one", sidecar)
        check.expect(!FileManager.default.fileExists(atPath: noGit + "/.gitignore"),
            message: "non-git project leaves gitignore untouched")
    } catch {
        check.expect(false, message: "gitignore fixture failed: \(error)")
    }
}
