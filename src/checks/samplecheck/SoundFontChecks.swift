import Foundation
import PorydawApp
import PorydawSample

struct SoundFontFixture {
    let pool: [Int16]
    let bytes: Data
    let romOnlyBytes: Data
}

func soundFontFixture() -> SoundFontFixture {
    var pool: [Int16] = []
    for i in 0..<400 {
        pool.append(Int16((16383 * sin(2 * .pi * 441 * Double(i) / 22050)).rounded()))
    }
    for i in 0..<200 { pool.append(Int16(i * 100 - 10000)) }
    func u16(_ value: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)] }
    func u32(_ value: Int) -> [UInt8] { u16(value) + u16(value >> 16) }
    func name(_ text: String) -> [UInt8] {
        let chars = Array(text.utf8.prefix(19))
        return chars + [UInt8](repeating: 0, count: 20 - chars.count)
    }
    func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] {
        Array(id.utf8) + u32(payload.count) + payload + (payload.count & 1 == 0 ? [] : [0])
    }
    func list(_ id: String, _ payload: [UInt8]) -> [UInt8] { chunk("LIST", Array(id.utf8) + payload) }
    func header(
        _ label: String, _ start: Int, _ end: Int, _ loopStart: Int, _ loopEnd: Int,
        _ rate: Int, _ pitch: Int, _ correction: Int, _ type: Int
    ) -> [UInt8] {
        var bytes = name(label)
        bytes.reserveCapacity(46)
        bytes.append(contentsOf: u32(start))
        bytes.append(contentsOf: u32(end))
        bytes.append(contentsOf: u32(loopStart))
        bytes.append(contentsOf: u32(loopEnd))
        bytes.append(contentsOf: u32(rate))
        bytes.append(UInt8(truncatingIfNeeded: pitch))
        bytes.append(UInt8(truncatingIfNeeded: correction))
        bytes.append(contentsOf: u16(0))
        bytes.append(contentsOf: u16(type))
        return bytes
    }
    let pcm = pool.flatMap { u16(Int(UInt16(bitPattern: $0))) }
    func font(_ headers: [UInt8]) -> Data {
        var phdr = name("TestPreset")
        phdr.reserveCapacity(76)
        phdr.append(contentsOf: u16(0))
        phdr.append(contentsOf: u16(0))
        phdr.append(contentsOf: u16(0))
        phdr.append(contentsOf: u32(0))
        phdr.append(contentsOf: u32(0))
        phdr.append(contentsOf: u32(0))
        phdr.append(contentsOf: name("EOP"))
        phdr.append(contentsOf: u16(0))
        phdr.append(contentsOf: u16(0))
        phdr.append(contentsOf: u16(1))
        phdr.append(contentsOf: u32(0))
        phdr.append(contentsOf: u32(0))
        phdr.append(contentsOf: u32(0))
        let inst = name("TestInst") + u16(0) + name("EOI") + u16(1)
        let pbag: [UInt8] = u16(0) + u16(0) + u16(1) + u16(0)
        let pgen: [UInt8] = u16(41) + u16(0) + u16(0) + u16(0)
        let igen: [UInt8] = u16(53) + u16(0) + u16(0) + u16(0)
        var pdta = chunk("phdr", phdr)
        pdta.append(contentsOf: chunk("pbag", pbag))
        pdta.append(contentsOf: chunk("pgen", pgen))
        pdta.append(contentsOf: chunk("inst", inst))
        pdta.append(contentsOf: chunk("ibag", pbag))
        pdta.append(contentsOf: chunk("igen", igen))
        pdta.append(contentsOf: chunk("shdr", headers))
        var body = Array("sfbk".utf8)
        body.append(contentsOf: list("INFO", chunk("ifil", u16(2) + u16(1))))
        body.append(contentsOf: list("sdta", chunk("smpl", pcm)))
        body.append(contentsOf: list("pdta", pdta))
        return Data(Array("RIFF".utf8) + u32(body.count) + body)
    }
    let eos = header("EOS", 0, 0, 0, 0, 0, 0, 0, 0)
    let rom = header("RomTone", 0, 400, 0, 0, 22050, 60, 0, 0x8001)
    let headers =
        header("Test Tone", 0, 400, 100, 300, 22050, 69, -20, 1)
        + header("PadL", 400, 600, 400, 400, 32000, 60, 50, 4)
        + rom + header("Unpitched", 400, 600, 0, 0, 22050, 255, 0, 1) + eos
    return SoundFontFixture(pool: pool, bytes: font(headers), romOnlyBytes: font(rom + eos))
}

internal func runSoundFontChecks(_ report: CheckReport) {
    soundFontExtraction(report)
    soundFontRefusals(report)
    soundFontPicker(report)
}

private func soundFontExtraction(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::soundFontExtraction")
    let fixture = soundFontFixture()
    check.expect(Sf2Reader.isSoundFont(fixture.bytes), message: "sf2 magic sniffs")
    do {
        let file = try Sf2Reader.read(fixture.bytes, sourcePath: "f/test.sf2")
        check.expect(
            file.sourcePath == "f/test.sf2" && file.pool.count == fixture.pool.count * 2,
            message: "sf2 fixture reads")
        check.expect(file.zones.count == 3, message: "ROM and EOS omitted from three zones")
        let tone = file.zones[0]
        check.expect(
            tone.name == "Test Tone" && tone.instrument == "TestInst" && tone.preset == "TestPreset",
            message: "grouping labels resolve through the pdta index arrays")
        check.expect(
            file.zones[1].name == "PadL" && file.zones[1].isStereoPair && file.zones[1].instrument.isEmpty,
            message: "left-linked zone flags as a stereo pair, ungrouped")
        let z0 = try Sf2Reader.extractZone(file, index: 0)
        check.expect(z0.sourcePath == "f/test.sf2", message: "zone 0 extracts")
        check.expect(
            z0.sourceKind == .sf2 && z0.sourceChannels == 1 && z0.sourceBits == 16
                && !z0.gbaReady && z0.warnings.isEmpty, message: "zone 0 structure")
        check.expect(
            z0.frameCount == 400 && z0.playLength == 400 && z0.sampleRate == 22050,
            message: "zone 0 pool segment bounds")
        check.expect(
            z0.hasPitchMetadata && z0.baseKey == 68 && abs(z0.fracSemitone - 0.8) < 1e-9,
            message: "negative pitchCorrection renormalizes below the unity key")
        check.expect(
            z0.hasLoop && z0.loopStart == 100 && z0.loopEndInclusive == 299,
            message: "sf2 exclusive loop end converts to inclusive")
        check.expect(z0.suggestedName == "test_tone", message: "zone name sanitizes into the suggested name")
        check.expect(
            z0.buffer.indices.allSatisfy { z0.buffer[$0] == Float(Double(fixture.pool[$0]) / 32768) },
            message: "zone 0 entire pool converts to canonical PCM")
        let z1 = try Sf2Reader.extractZone(file, index: 1)
        check.expect(z1.sampleRate == 32000, message: "zone 1 extracts")
        check.expect(
            z1.warnings.count == 1, message: "stereo-pair extraction reports its one-channel conversion")
        check.expect(
            z1.frameCount == 200 && !z1.hasLoop && z1.hasPitchMetadata && z1.baseKey == 60
                && abs(z1.fracSemitone - 0.5) < 1e-9
                && z1.buffer[0] == Float(Double(fixture.pool[400]) / 32768),
            message: "positive pitchCorrection becomes the semitone fraction")
        let z2 = try Sf2Reader.extractZone(file, index: 2)
        check.expect(z2.frameCount == 200, message: "zone 2 extracts")
        check.expect(
            !z2.hasPitchMetadata && z2.baseKey == 60,
            message: "unpitched (255) zone defers to pitch detection")
    } catch {
        report.scoped(cppID: "samplecheck/SoundFontSwift::extraction").expect(
            false, message: "SoundFont fixture extraction failed: \(error)")
    }
}

private func soundFontRefusals(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::soundFontRefusals")
    let fixture = soundFontFixture()
    let multiRejected: Bool
    do {
        _ = try SampleImport.decode(fixture.bytes, sourcePath: "f/test.sf2")
        multiRejected = false
    } catch {
        multiRejected = true
    }
    check.expect(multiRejected, message: "multi-sample SoundFont ingress rejected with domain error")
    let truncatedRejected: Bool
    do {
        _ = try Sf2Reader.read(Data(fixture.bytes.prefix(200)), sourcePath: "f/test.sf2")
        truncatedRejected = false
    } catch {
        truncatedRejected = true
    }
    check.expect(truncatedRejected, message: "truncated SoundFont rejected with domain error")
    let romOnlyRejected: Bool
    do {
        _ = try Sf2Reader.read(fixture.romOnlyBytes, sourcePath: "f/test.sf2")
        romOnlyRejected = false
    } catch {
        romOnlyRejected = true
    }
    check.expect(romOnlyRejected, message: "ROM-only SoundFont rejected with domain error")
    let zoneRejected: Bool
    do {
        _ = try Sf2Reader.extractZone(Sf2Reader.read(fixture.bytes, sourcePath: "f/test.sf2"), index: -1)
        zoneRejected = false
    } catch {
        zoneRejected = true
    }
    report.scoped(cppID: "samplecheck/SoundFontSwift::zoneBoundaries").expect(
        zoneRejected, message: "invalid zone index is rejected with domain error")
}

private func soundFontPicker(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::soundFontPicker")
    let supplement = report.scoped(cppID: "samplecheck/SoundFontSwift::pickerDetails")
    do {
        let file = try Sf2Reader.read(soundFontFixture().bytes, sourcePath: "f/test.sf2")
        check.expect(file.sourcePath == "f/test.sf2", message: "picker sf2 fixture reads")
        var picker = Sf2ZonePickerModel(file: file)
        check.expect(picker.groups.count == 2, message: "picker has two groups")
        check.expect(
            picker.groups[0].title == "TestInst — TestPreset" && picker.groups[0].rows.count == 1,
            message: "instrument/preset zones form one picker group")
        check.expect(
            picker.groups[1].title == "(no instrument)" && picker.groups[1].rows.count == 2,
            message: "unreferenced zones fall under (no instrument)")
        check.expect(
            !picker.canAccept && picker.selectedZone == -1, message: "nothing picked until a zone row is chosen")
        picker.select(zoneIndex: 0)
        check.expect(picker.selectedZone == 0 && picker.canAccept, message: "selecting a zone row arms OK")
        picker.selectGroup(title: picker.groups[0].title)
        check.expect(picker.selectedZone == -1 && !picker.canAccept, message: "group rows are not pickable")
        picker.filter = "pad"
        check.expect(picker.groups.count == 1, message: "search filters picker groups")
        check.expect(picker.groups[0].rows.count == 1, message: "search filters picker rows")
        picker.select(zoneIndex: 1)
        check.expect(picker.selectedZone == 1, message: "filtered zone row selects source index")
        picker.filter = ""
        check.expect(picker.groups.count == 2, message: "cleared filter restores groups")
        picker.select(zoneIndex: 0)
        supplement.expect(picker.canAccept && picker.selectedZone == 0, message: "picked zone stays armed")
        supplement.expect(
            picker.groups[0].rows[0].columns == ["Test Tone", "A4 -20¢", "22050 Hz", "400", "100–299", ""],
            message: "picker displays source key, rate, frames and relative loop")
        supplement.expect(picker.groups[1].rows[0].columns[5] == "stereo pair", message: "picker marks stereo pair")
        picker.filter = "unpitched"
        supplement.expect(
            !picker.canAccept && picker.groups[0].rows[0].columns[1] == "—",
            message: "filter drops hidden selection and unpitched row has no key")
    } catch { supplement.expect(false, message: "SoundFont picker setup failed: \(error)") }
}
