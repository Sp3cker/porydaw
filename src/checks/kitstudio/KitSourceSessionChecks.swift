import PorydawKitStudio
import PorydawSample
import PorydawVoicegroup

@MainActor
func runKitSourceSessionChecks(_ report: CheckReport) {
    checkSourceMarkers(report)
    checkSourceSelection(report)
    checkSourceSnap(report)
    checkSourceNames(report)
    checkSourceExhaustion(report)
    checkSourceRenderAndRates(report)
    checkSourceClose(report)
    checkSourceSnapshot(report)
    checkSourceAutoPlaceAndZoneRemoval(report)
    checkCommittedKitSamples(report)
}

private func sessionSample(
    name: String = "src", rate: Double = 13379, count: Int = 512, gbaReady: Bool = false
) -> ImportedSample {
    ImportedSample(
        buffer: [Float](repeating: 0.5, count: count), sampleRate: rate,
        playLength: count, suggestedName: name, gbaReady: gbaReady)
}

@MainActor
private func checkSourceMarkers(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::markerOrdering")
    let session = KitSourceSession()
    session.addSource(sessionSample())
    let id = session.sources[0].id
    r.expect(
        session.sources[0].markers.isEmpty && session.sources[0].slices.isEmpty, message: "new source starts empty")
    session.setMarker(source: id, frame: 100, snap: false)
    r.expect(session.sources[0].slices.isEmpty, message: "one marker creates no slice")
    session.setMarker(source: id, frame: 300, snap: false)
    let first = session.sources[0].slices[0]
    r.expect(!first.fadeIn && first.fadeOut, message: "slice declick defaults preserve attacks")
    session.setSliceFades(source: id, slice: 0, fadeIn: true, fadeOut: false)
    session.setMarker(source: id, frame: 200, snap: false)
    r.expectEqual(
        expected: [100, 200, 300], actual: session.sources[0].markers, what: "out-of-order insertion is sorted")
    r.expectEqual(
        expected: [100, 200], actual: session.sources[0].slices.map(\.startFrame), what: "adjacent-pair starts")
    r.expectEqual(expected: [200, 300], actual: session.sources[0].slices.map(\.endFrame), what: "adjacent-pair ends")
    r.expectEqual(
        expected: ["src_00", "src_01"], actual: session.sources[0].slices.map(\.name),
        what: "split mints only the right name")
    r.expect(
        session.sources[0].slices[0].fadeIn && !session.sources[0].slices[0].fadeOut,
        message: "split retains left fade overrides")
    let beforeDuplicate = session.sources
    session.setMarker(source: id, frame: 200, snap: false)
    r.expectEqual(expected: beforeDuplicate, actual: session.sources, what: "duplicate boundary is a no-op")
    let beforeMove = session.sources[0].slices
    session.moveMarker(source: id, from: 200, to: 250, snap: false)
    r.expectEqual(
        expected: [100, 250, 300], actual: session.sources[0].markers,
        what: "move keeps ordered markers")
    r.expectEqual(
        expected: beforeMove.map(\.name), actual: session.sources[0].slices.map(\.name),
        what: "move retains adjacent names")
    r.expectEqual(
        expected: [250, 300], actual: session.sources[0].slices.map(\.endFrame), what: "move updates adjacent bounds")
    let beforeCollision = session.sources
    session.moveMarker(source: id, from: 250, to: 300, snap: false)
    r.expectEqual(expected: beforeCollision, actual: session.sources, what: "move collision leaves state unchanged")
    session.removeMarker(source: id, frame: 250)
    r.expectEqual(expected: [100, 300], actual: session.sources[0].markers, what: "interior boundary removed")
    r.expectEqual(expected: "src_00", actual: session.sources[0].slices[0].name, what: "merge keeps left name")
    r.expect(
        session.sources[0].slices[0].fadeIn && !session.sources[0].slices[0].fadeOut,
        message: "merge keeps left fade overrides")
    session.removeMarker(source: id, frame: 100)
    r.expectEqual(expected: [300], actual: session.sources[0].markers, what: "endpoint removal leaves neighbor")
    r.expect(session.sources[0].slices.isEmpty, message: "endpoint removal deletes its adjacent slice")
    session.removeMarker(source: id, frame: 300)
    r.expect(session.sources[0].markers.isEmpty, message: "last marker can be removed")
}

@MainActor
private func checkSourceSelection(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::selectionAndDeletion")
    let session = KitSourceSession()
    session.addSource(sessionSample(count: 400))
    let id = session.sources[0].id
    session.createFirstSlice(source: id)
    r.expectEqual(expected: 1, actual: session.sources[0].slices.count, what: "first slice spans the full buffer")
    session.setMarker(source: id, frame: 100, snap: false)
    session.setMarker(source: id, frame: 300, snap: false)
    r.expectEqual(expected: [100, 300], actual: session.sources[0].markers, what: "markers bound each split")
    r.expectEqual(expected: 3, actual: session.sources[0].slices.count, what: "each split adds one slice")
    session.removeSlice(source: id, slice: 0)
    r.expectEqual(
        expected: [100, 300], actual: session.sources[0].markers, what: "delete keeps marker boundaries")
    session.setMarker(source: id, frame: 50, snap: false)
    r.expectEqual(
        expected: ["src_00", "src_01", "src_02"], actual: session.sources[0].slices.map(\.name),
        what: "gap slice reuses the freed suffix")
    session.moveMarker(source: id, from: 300, to: 250, snap: false)
    r.expectEqual(
        expected: [100, 250, 400], actual: session.sources[0].slices.map(\.endFrame),
        what: "move updates adjacent bounds")
    session.removeMarker(source: id, frame: 50)
    r.expectEqual(
        expected: [100, 250], actual: session.sources[0].slices.map(\.startFrame),
        what: "endpoint marker removal deletes only its adjacent slice")
    session.setMarker(source: id, frame: 50, snap: false)
    r.expectEqual(
        expected: 3, actual: session.sources[0].slices.count, what: "marker recreates a deleted gap slice")
    let beforeRefusal = session.sources
    session.validateName = { (_: String) in "reserved" }
    session.setMarker(source: id, frame: 150, snap: false)
    r.expectEqual(
        expected: beforeRefusal, actual: session.sources, what: "split refusal preserves markers and slices atomically")
}

@MainActor
private func checkSourceSnap(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::snapWindow")
    for (rate, window) in [(13379.0, 40), (44100.0, 132)] {
        for distance in [window, window + 1] {
            var sample = sessionSample(rate: rate)
            sample.buffer = (0..<512).map { (frame: Int) -> Float in frame < 200 + distance ? -0.5 : 0.5 }
            let session = KitSourceSession()
            session.addSource(sample)
            let id = session.sources[0].id
            session.setMarker(source: id, frame: 200, snap: true)
            let expected = distance == window ? 200 + distance : 200
            r.expectEqual(
                expected: [expected], actual: session.sources[0].markers, what: "snap \(distance) frames at \(rate) Hz")
            session.removeMarker(source: id, frame: expected)
            session.setMarker(source: id, frame: 200, snap: false)
            r.expectEqual(expected: [200], actual: session.sources[0].markers, what: "snap off leaves cursor frame")
            session.moveMarker(source: id, from: 200, to: 199, snap: true)
            r.expectEqual(
                expected: [199], actual: session.sources[0].markers,
                what: "move outside snap bound leaves requested frame")
            session.moveMarker(source: id, from: 199, to: 201, snap: true)
            r.expectEqual(
                expected: [200 + distance], actual: session.sources[0].markers,
                what: "move uses the shared crossing search")
        }
    }
}

@MainActor
private func checkSourceNames(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::mintAndRename")
    let session = KitSourceSession()
    session.addSource(sessionSample(name: "Src!"))
    let id = session.sources[0].id
    r.expectEqual(
        expected: "src_00", actual: session.mintSliceName(source: id),
        what: "source prefix sanitized and suffix two digits")
    for frame in [0, 100, 200] { session.setMarker(source: id, frame: frame, snap: false) }
    r.expectEqual(
        expected: ["src_00", "src_01"], actual: session.sources[0].slices.map(\.name),
        what: "mint sequence starts at 00")
    session.removeSlice(source: id, slice: 0)
    r.expectEqual(expected: "src_00", actual: session.mintSliceName(source: id), what: "delete frees first suffix")
    session.addSource(sessionSample(name: "SRC"))
    let other = session.sources[1].id
    session.createFirstSlice(source: other)
    r.expectEqual(
        expected: "src_00", actual: session.sources[1].slices[0].name, what: "second source reuses globally free suffix"
    )
    r.expectEqual(
        expected: "src_02", actual: session.mintSliceName(source: id), what: "mint skips every source's names")
    session.validateName = { (name: String) in name == "src_02" || name == "blocked" ? "reserved" : nil }
    r.expectEqual(
        expected: "src_03", actual: session.mintSliceName(source: id), what: "mint respects outward name validator")
    let old = session.sources[0].slices[0]
    r.expect(
        !session.renameSlice(source: id, slice: 0, to: "Blocked!"),
        message: "sanitized name is refused by injected validator")
    r.expectEqual(expected: old, actual: session.sources[0].slices[0], what: "rename refusal keeps full old slice")
    r.expect(
        !session.renameSlice(source: id, slice: 0, to: "src_00"), message: "rename cannot collide with another source")
    r.expect(!session.renameSlice(source: id, slice: 0, to: "!!!"), message: "rename rejects empty sanitized name")
    r.expect(session.renameSlice(source: id, slice: 0, to: "New Name!"), message: "valid rename accepted")
    r.expectEqual(
        expected: "new_name", actual: session.sources[0].slices[0].name, what: "accepted rename stores sanitized name")
    r.expect(session.renameSlice(source: id, slice: 0, to: "new_name"), message: "unchanged rename is a no-op")
    session.validateName = { (_: String) in "reserved" }
    r.expect(
        !session.renameSlice(source: id, slice: 0, to: "new_name"),
        message: "even unchanged rename requires validator acceptance")
}

@MainActor
private func checkSourceExhaustion(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::nameExhaustion")
    let session = KitSourceSession()
    session.addSource(sessionSample(count: 102))
    let id = session.sources[0].id
    for frame in 0...100 { session.setMarker(source: id, frame: frame, snap: false) }
    r.expectEqual(expected: 100, actual: session.sources[0].slices.count, what: "all 00–99 names are usable")
    r.expectEqual(expected: "src_99", actual: session.sources[0].slices.last?.name, what: "last legal suffix is 99")
    r.expectEqual(expected: "", actual: session.mintSliceName(source: id), what: "exhausted namespace returns empty")
    let full = session.sources
    session.setMarker(source: id, frame: 101, snap: false)
    r.expectEqual(expected: full, actual: session.sources, what: "exhausted append is atomic")
    session.removeSlice(source: id, slice: 0)
    session.setMarker(source: id, frame: 101, snap: false)
    r.expectEqual(
        expected: "src_00", actual: session.sources[0].slices.last?.name,
        what: "first freed suffix reused without a three-digit name")
}

@MainActor
private func checkSourceRenderAndRates(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::renderAndRates")
    let session = KitSourceSession()
    for (rate, ready) in [(44100.0, true), (44100.0, false), (8000.0, false)] {
        var sample = sessionSample(rate: rate, count: 96, gbaReady: ready)
        sample.baseKey = 67
        sample.fracSemitone = 0.25
        sample.hasLoop = true
        sample.loopStart = 24
        sample.loopEndInclusive = 90
        sample.exactPitch = 12_345_678
        sample.buffer = (0..<96).map { (frame: Int) -> Float in Float(frame % 17 - 8) / 16 }
        session.addSource(sample)
        let index = session.sources.count - 1
        let id = session.sources[index].id
        session.setMarker(source: id, frame: 12, snap: false)
        session.setMarker(source: id, frame: 84, snap: false)
        for (fadeIn, fadeOut) in [(false, true), (true, false), (false, false), (true, true)] {
            session.setSliceFades(source: id, slice: 0, fadeIn: fadeIn, fadeOut: fadeOut)
            var params = SampleDocument.defaultParams(for: sample)
            params.cropStart = 12
            params.cropEnd = 84
            params.targetRate = session.sources[index].targetRate
            params.loopOn = false
            params.fadeIn = false
            params.fadeOut = false
            if params.targetRate != sample.sampleRate { params.exactPitchOverride = 0 }
            let direct = SampleSlice.render(source: sample, params: params, fadeIn: fadeIn, fadeOut: fadeOut)
            let before = session.sources
            let rendered = session.renderSlice(source: id, slice: 0)
            r.expectEqual(expected: direct, actual: rendered, what: "render metadata matches direct pipeline")
            r.expectEqual(expected: before, actual: session.sources, what: "render is a pure query")
            r.expect(!rendered.looped, message: "slices are one-shot even for looped imports")
            if ready {
                r.expectEqual(
                    expected: sample.exactPitch, actual: rendered.freq,
                    what: "unchanged GBA source rate retains exact pitch")
            }
        }
        let oldRate = session.sources[index].targetRate
        r.expect(!session.setSourceRate(source: id, rate: 12345), message: "rate outside shared options rejected")
        r.expectEqual(
            expected: oldRate, actual: session.sources[index].targetRate, what: "invalid selection preserves rate")
        r.expect(session.setSourceRate(source: id, rate: 7884), message: "shared table rate selected by Hz")
        r.expectEqual(expected: 7884.0, actual: session.sources[index].targetRate, what: "source stores selected Hz")
        let resampled = session.renderSlice(source: id, slice: 0)
        r.expectEqual(expected: 7884.0, actual: resampled.outputRate, what: "render uses selected source rate")
        if ready {
            r.expect(
                resampled.freq != sample.exactPitch, message: "changed GBA source rate clears exact pitch override")
        }
        r.expect(session.setSourceRate(source: id, rate: Int(rate)), message: "source rate option accepted")
        r.expectEqual(expected: rate, actual: session.sources[index].targetRate, what: "source-rate option stored")
        if ready {
            r.expectEqual(
                expected: sample.exactPitch, actual: session.renderSlice(source: id, slice: 0).freq,
                what: "returning to the original rate restores exact pitch")
        }
    }
    r.expectEqual(
        expected: 44100.0, actual: session.sources[0].targetRate,
        what: "later sources' rate edits leave first source unchanged")
}

@MainActor
private func checkSourceClose(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::closabilityAndIdentity")
    let session = KitSourceSession()
    session.addSource(sessionSample())
    session.addSource(sessionSample(name: "other"))
    let first = session.sources[0].id
    let second = session.sources[1].id
    session.setMarker(source: first, frame: 0, snap: false)
    session.setMarker(source: first, frame: 100, snap: false)
    r.expect(session.removeSource(source: first), message: "sliced source closes without zone gating")
    r.expectEqual(
        expected: [second], actual: session.sources.map(\.id), what: "closing another source retains identity")
    session.setMarker(source: second, frame: 10, snap: false)
    r.expectEqual(
        expected: [10], actual: session.sources[0].markers, what: "source arguments are ids, not current array indices")
    session.addSource(sessionSample())
    r.expect(session.sources[1].id > second, message: "closed source identity is never reused")
    r.expect(!session.removeSource(source: first), message: "closed id is absent")
    r.expect(session.removeSource(source: second), message: "marker-only source is closable")
}

@MainActor
private func checkSourceSnapshot(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::snapshotRestore")
    let session = KitSourceSession()
    session.addSource(sessionSample())
    let id = session.sources[0].id
    session.setMarker(source: id, frame: 0, snap: false)
    session.setMarker(source: id, frame: 100, snap: false)
    let prior = session.snapshot()
    session.setMarker(source: id, frame: 50, snap: false)
    let afterSplit = session.snapshot()
    session.addSource(sessionSample(name: "second"))
    let nextSource = session.sources[1].id
    session.setSliceFades(source: id, slice: 0, fadeIn: true, fadeOut: false)
    _ = session.renameSlice(source: id, slice: 0, to: "renamed")
    _ = session.setSourceRate(source: id, rate: 7884)
    r.expect(session.snapshot() != prior, message: "mutations change the captured value")
    session.restore(prior)
    r.expectEqual(expected: prior, actual: session.snapshot(), what: "restore replaces full state exactly")
    session.setMarker(source: id, frame: 50, snap: false)
    r.expectEqual(expected: afterSplit, actual: session.snapshot(), what: "restore includes slice identity counter")
    session.addSource(sessionSample(name: "second"))
    r.expectEqual(expected: nextSource, actual: session.sources[1].id, what: "restore includes source identity counter")
}

@MainActor
private func checkSourceAutoPlaceAndZoneRemoval(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::autoPlaceAndZoneVanishing")
    let p = KitStudioPresenter()
    p.open()
    p.dropSample(name: "occupied", onKey: 36)
    p.setMode(index: 1)
    // A keysplit drop at 36 would extend to 127 and cover every key, so the one-key blocker goes in directly.
    p.draft.setZones(
        [
            KitZone(startKey: 36, endKey: 36, sampleName: "occupied", rootKey: 60, pan: 0, adsr: (255, 0, 255, 0))
        ], mode: .keysplit)
    p.setMode(index: 0)

    let sample = sessionSample(name: "sample", count: 200)
    p.addSource(sample, autoPlaceFirstSlice: true)
    let slice1 = p.sliceName(id: p.sliceId(row: 0))
    r.expectEqual(
        expected: 37,
        actual: p.draft.drumkitZones.first(where: { $0.sampleName == slice1 })?.startKey,
        what: "auto-place picks next free key 37 in drumkit skipping occupied 36")
    r.expectEqual(
        expected: 37,
        actual: p.draft.keysplitZones.first(where: { $0.sampleName == slice1 })?.startKey,
        what: "auto-place picks next free key 37 in keysplit skipping occupied 36")

    p.insertMarker(frame: 100)
    let slice2 = p.sliceName(id: p.sliceId(row: 1))
    r.expectEqual(
        expected: 38,
        actual: p.draft.drumkitZones.first(where: { $0.sampleName == slice2 })?.startKey,
        what: "marker add auto-places new slice onto next free key 38")
    r.expectEqual(
        expected: 38,
        actual: p.draft.keysplitZones.first(where: { $0.sampleName == slice2 })?.startKey,
        what: "marker add auto-places new slice onto next free key 38 in keysplit")

    let marker = p.markerId(row: 0)
    p.removeMarker(id: marker)
    r.expect(
        p.draft.drumkitZones.first(where: { $0.sampleName == slice2 }) == nil,
        message: "drumkit zone vanishes when slice is merged away")
    r.expect(
        p.draft.keysplitZones.first(where: { $0.sampleName == slice2 }) == nil,
        message: "keysplit zone vanishes when slice is merged away")
    r.expectEqual(
        expected: 37,
        actual: p.draft.drumkitZones.first(where: { $0.sampleName == slice1 })?.startKey,
        what: "surviving slice keeps its zone")

    p.validateName = { $0 == "sample_02" ? "taken in project" : nil }
    p.insertMarker(frame: 120)
    p.insertMarker(frame: 150)
    let slice3 = p.sliceName(id: p.sliceId(row: 2))
    r.expectEqual(expected: "sample_03", actual: slice3, what: "minted name skips validator-rejected sample_02")

    let beforeRename = slice3
    r.expect(
        p.isSliceNameInvalid(sliceId: p.sliceId(row: 2), name: "sample_02"),
        message: "rejected name is reported invalid")
    p.renameSlice(id: p.sliceId(row: 2), name: "sample_02")
    r.expectEqual(
        expected: beforeRename, actual: p.sliceName(id: p.sliceId(row: 2)), what: "invalid rename leaves name unchanged"
    )
}

@MainActor
private func checkCommittedKitSamples(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitSourceSession::committedKitSamples")
    func committed(_ count: Int, looped: Bool) -> ProcessedSample {
        var sample = ProcessedSample()
        sample.s8 = (0..<count).map { (index: Int) -> Int8 in Int8(truncatingIfNeeded: index % 64 - 32) }
        sample.freq = 13379 * 1024
        sample.size = UInt32(count)
        sample.looped = looped
        sample.loopStart = looped ? 100 : 0
        return sample
    }
    func zone(_ key: Int, _ symbol: String) -> KitZone {
        KitZone(startKey: key, endKey: key, sampleName: symbol, rootKey: 60, pan: 0, adsr: (255, 0, 255, 0))
    }
    let p = KitStudioPresenter()
    p.load(
        zones: [
            zone(36, "DirectSoundWaveData_kick"), zone(38, "DirectSoundWaveData_kick"),
            zone(40, "DirectSoundWaveData_snare"),
        ],
        mode: .drumkit, name: "kit",
        samples: [
            "DirectSoundWaveData_kick": committed(400, looped: true),
            "DirectSoundWaveData_snare": committed(300, looped: false),
        ],
        progWaves: [:])
    r.expectEqual(
        expected: ["kick", "kick", "snare"], actual: p.draft.drumkitZones.map(\.sampleName),
        what: "keys reference one slice per committed sample")
    r.expectEqual(expected: 2, actual: p.sliceCount, what: "a sample on two keys is one slice")
    r.expectEqual(
        expected: [1, 1, 2], actual: (0..<3).map { (row: Int) -> Int in p.zoneBadge(row: row) },
        what: "keys badge their committed slice numbers")
    r.expectEqual(expected: 2, actual: p.sourceRows[0].committedCount, what: "one kit tab groups the samples")
    r.expect(!p.dirty, message: "loading the kit is not an unsaved change")
    let kick = p.sliceId(row: 0)
    r.expect(p.sliceIsCommitted(id: kick), message: "an untouched kit sample is committed")
    p.renameSlice(id: kick, name: "renamed")
    r.expectEqual(expected: "kick", actual: p.sliceName(id: kick), what: "a kit sample's name is read-only")

    p.selectSource(row: 0)
    guard let rate = SampleRatePolicy.rates.first(where: { $0 != 13379 }) else {
        r.expect(false, message: "the rate table offers another rate")
        return
    }
    p.setSourceRate(rate: rate)
    r.expectEqual(expected: "kick_00", actual: p.sliceName(id: kick), what: "an edited kit sample forks a new name")
    r.expectEqual(
        expected: ["kick_00", "kick_00", "snare"], actual: p.draft.drumkitZones.map(\.sampleName),
        what: "both keys follow the forked sample")
    r.expect(!p.sliceIsCommitted(id: kick) && p.dirty, message: "the fork saves as new audio")
    let forked = p.session.sources[0]
    r.expect(
        p.session.renderSlice(source: forked.id, slice: 0).looped,
        message: "a fork covering the whole sample keeps its loop")
    p.undo()
    r.expect(
        p.sliceName(id: kick) == "kick" && p.sliceIsCommitted(id: kick) && !p.dirty,
        message: "undo restores the untouched kit sample")

    p.removeSlice(id: p.sliceId(row: 1))
    r.expect(
        p.session.sources.count == 1 && p.draft.drumkitZones.map(\.sampleName) == ["kick", "kick"],
        message: "removing a kit sample drops its source and keys only")
}
