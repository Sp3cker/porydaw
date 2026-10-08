import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func duplicationAndGlobals(_ report: CheckReport) {
    let document = timeDocument()
    _ = try? document.addNotes([
        NewNote(track: 0, tick: 595, pitch: 67, duration: 30, velocity: 60),
        NewNote(track: 0, tick: 610, pitch: 64, duration: 10, velocity: 90),
    ])
    document.writeLane(
        track: 0, lane: .controller(7), from: 580, through: 610,
        points: [LaneWrite(tick: 580, value: 33), LaneWrite(tick: 610, value: 44)])
    let originalIDs = Set(document.notes(in: 0).map(\.id))
    let before = coreTimeBytes(document)
    report.expect(
        document.duplicateTime(
            TimeRange(startTick: 600, endTick: 620),
            scope: TimeScope(tracks: [0])),
        cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
        message: "time duplication commits")
    let copies = document.notes(in: 0).filter { $0.tick >= 620 && $0.tick < 640 }
    report.expect(
        copies.count == 2 && copies.allSatisfy { !originalIDs.contains($0.id) },
        cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
        message: "clipped duplicates all receive fresh identities")
    report.expect(
        document.lanePoints(track: 0, lane: .controller(7)).contains {
            $0.tick == 620 && $0.value == 33
        }, cppID: "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
        message: "duplicate seeds the effective value at its destination seam")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document),
        cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
        what: "one undo restores the duplicated range transaction")

    // timeRangeDuplicateClippingAndOrder: faithful four-note clipping port.
    do {
        let clipID = "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder"
        let clipping = try timeRangeDocument()
        report.expectEqual(
            expected: 2, actual: clipping.engineTracks.usedTrackCount, cppID: clipID,
            what: "timeRangeFile fixture loads two editable tracks")
        let start: Tick = 600
        _ = try clipping.addNotes([
            NewNote(track: 0, tick: start + 10, pitch: 64, duration: 10, velocity: 90),
            NewNote(track: 0, tick: start - 5, pitch: 65, duration: 15, velocity: 80),
            NewNote(track: 0, tick: start + 10, pitch: 66, duration: 20, velocity: 70),
            NewNote(track: 0, tick: start - 5, pitch: 67, duration: 30, velocity: 60),
        ])
        func clipNote(_ tick: Tick, _ pitch: UInt8) -> Note? {
            clipping.notes(in: 0).first { $0.tick == tick && $0.pitch == pitch }
        }
        guard let contained = clipNote(start + 10, 64),
            let leftCross = clipNote(start - 5, 65),
            let rightCross = clipNote(start + 10, 66),
            let bothCross = clipNote(start - 5, 67)
        else {
            report.fail(clipID, "pre-duplication notes missing")
            return
        }
        let original = [contained.id, leftCross.id, rightCross.id, bothCross.id]
        let clipBefore = coreTimeBytes(clipping)
        report.expect(
            clipping.duplicateTime(
                TimeRange(startTick: start, endTick: start + 20),
                scope: TimeScope(tracks: [0])),
            cppID: clipID, message: "time duplication commits")
        guard let copiedContained = clipNote(start + 30, 64),
            let copiedLeft = clipNote(start + 20, 65),
            let copiedRight = clipNote(start + 30, 66),
            let copiedBoth = clipNote(start + 20, 67)
        else {
            report.fail(clipID, "duplicated notes missing at expected ticks")
            return
        }
        report.expectEqual(
            expected: Tick(10), actual: copiedContained.duration, cppID: clipID,
            what: "contained copy keeps its duration")
        report.expectEqual(
            expected: Tick(10), actual: copiedLeft.duration, cppID: clipID,
            what: "left-crossing copy clips to the range")
        report.expectEqual(
            expected: Tick(10), actual: copiedRight.duration, cppID: clipID,
            what: "right-crossing copy clips to the range")
        report.expectEqual(
            expected: Tick(20), actual: copiedBoth.duration, cppID: clipID,
            what: "both-crossing copy clips to the range")
        let copies = [copiedContained.id, copiedLeft.id, copiedRight.id, copiedBoth.id]
        for (index, copy) in copies.enumerated() {
            for source in original {
                report.expect(
                    copy != source, cppID: clipID,
                    message: "copy \(index) receives a fresh identity")
            }
            for other in copies.dropFirst(index + 1) {
                report.expect(
                    copy != other, cppID: clipID,
                    message: "copy \(index) is unique among copies")
            }
        }
        let clipAfter = coreTimeBytes(clipping)
        _ = clipping.history.undoDocument()
        report.expectEqual(
            expected: clipBefore, actual: coreTimeBytes(clipping), cppID: clipID,
            what: "one undo restores the clipping duplication")
        _ = clipping.history.redoDocument()
        report.expectEqual(
            expected: clipAfter, actual: coreTimeBytes(clipping), cppID: clipID,
            what: "one redo restores the clipping duplication")
        guard let clipChunk = clipping.engineTracks.tracks[0].midiChunk else {
            report.fail(clipID, "engine track 0 has no MIDI chunk")
            return
        }
        clipping.insertRawEvent(
            chunk: clipChunk,
            event: .channel(
                tick: 700, status: 0x80,
                data0: 72, data1: 0))
        clipping.insertRawEvent(
            chunk: clipChunk,
            event: .channel(
                tick: 700, status: 0x90,
                data0: 72, data1: 55))
        report.expect(
            clipping.duplicateTime(
                TimeRange(startTick: 700, endTick: 720),
                scope: TimeScope(tracks: [0])),
            cppID: clipID, message: "unterminated-source duplication commits")
        report.expect(
            coreTimeNoteEndsBeforeOnsAt(clipping, track: 0, tick: 720),
            cppID: clipID,
            message: "duplicated unterminated note ends before later ons")
        clipping.insertRawEvent(
            chunk: clipChunk,
            event: .channel(
                tick: 800, status: 0x80,
                data0: 73, data1: 0))
        clipping.insertRawEvent(
            chunk: clipChunk,
            event: .channel(
                tick: 800, status: 0x90,
                data0: 73, data1: 66))
        report.expect(
            clipping.insertBlankTime(
                TimeRange(startTick: 800, endTick: 820),
                scope: TimeScope(tracks: [0])),
            cppID: clipID, message: "insertion over unterminated source commits")
        report.expect(
            coreTimeNoteEndsBeforeOnsAt(clipping, track: 0, tick: 820),
            cppID: clipID,
            message: "inserted unterminated note ends before later ons")
    } catch {
        report.fail(
            "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
            "clipping fixture failed: \(error)")
    }

    // timeRangeUnterminated: faithful port over the timeRangeFile fixture.
    do {
        let unterminated = try timeRangeDocument()
        let unterminatedID = "editcheck/EditCheckTest::timeRangeUnterminated"
        report.expectEqual(
            expected: 2, actual: unterminated.engineTracks.usedTrackCount, cppID: unterminatedID,
            what: "timeRangeFile fixture loads two editable tracks")
        guard let unterminatedChunk = unterminated.engineTracks.tracks[0].midiChunk else {
            report.fail(unterminatedID, "engine track 0 has no MIDI chunk")
            return
        }
        unterminated.insertRawEvent(
            chunk: unterminatedChunk,
            event: .channel(
                tick: 220, status: 0x90,
                data0: 68, data1: 77))
        guard
            let source = unterminated.notes(in: 0).first(where: {
                $0.tick == 220 && $0.pitch == 68
            })
        else {
            report.fail(unterminatedID, "unterminated source note missing")
            return
        }
        report.expect(
            source.isUnterminated, cppID: unterminatedID,
            message: "raw note-on without a note-off is unterminated")
        let leftID = source.id
        let unterminatedBefore = coreTimeBytes(unterminated)
        report.expect(
            unterminated.insertBlankTime(
                TimeRange(startTick: 240, endTick: 250),
                scope: TimeScope(tracks: [0])),
            cppID: unterminatedID, message: "blank insertion commits")
        guard
            let left = unterminated.notes(in: 0).first(where: {
                $0.tick == 220 && $0.pitch == 68
            }),
            let right = unterminated.notes(in: 0).first(where: {
                $0.tick == 250 && $0.pitch == 68
            })
        else {
            report.fail(unterminatedID, "split halves missing after insertion")
            return
        }
        report.expect(
            !left.isUnterminated, cppID: unterminatedID,
            message: "left half is terminated by the insertion")
        report.expectEqual(
            expected: Tick(20), actual: left.duration, cppID: unterminatedID,
            what: "left half ends at the insertion start")
        report.expectEqual(
            expected: leftID, actual: left.id, cppID: unterminatedID,
            what: "left half keeps the source identity")
        report.expect(
            right.isUnterminated, cppID: unterminatedID,
            message: "right half resumes unterminated")
        report.expect(
            right.id != left.id, cppID: unterminatedID,
            message: "right half receives a fresh identity")
        let unterminatedEvents = unterminated.rawChunks[unterminatedChunk].events
        report.expect(
            hasChannel(unterminatedEvents, tick: 220, type: 0x9, key: 68)
                && hasChannel(unterminatedEvents, tick: 240, type: 0x8, key: 68)
                && hasChannel(unterminatedEvents, tick: 250, type: 0x9, key: 68),
            cppID: unterminatedID,
            message: "insertion emits source on, generated off, and resumed on")
        let parts = unterminated.notes(in: 0).filter { $0.pitch == 68 }
        report.expect(
            parts.count == 2 && parts[0].id == leftID && parts[0].duration == 20 && parts[1].id != leftID
                && parts[1].isUnterminated,
            cppID: "editcheck/EditCheckTest::timeRangeUnterminated",
            message: "blank insertion closes and resumes an unterminated note")
        let unterminatedAfter = coreTimeBytes(unterminated)
        _ = unterminated.history.undoDocument()
        report.expectEqual(
            expected: unterminatedBefore, actual: coreTimeBytes(unterminated),
            cppID: unterminatedID,
            what: "one undo restores the unterminated insertion")
        _ = unterminated.history.redoDocument()
        report.expectEqual(
            expected: unterminatedAfter, actual: coreTimeBytes(unterminated),
            cppID: unterminatedID,
            what: "one redo restores the unterminated insertion")
    } catch {
        report.fail(
            "editcheck/EditCheckTest::timeRangeUnterminated",
            "unterminated fixture failed: \(error)")
    }

    let globals = timeDocument()
    globals.setTimeSignature(tick: 960, numerator: 3, denominatorPower: 2)
    globals.insertRawEvent(chunk: 0, event: .meta(tick: 965, type: 0x01, data: [65, 66]))
    globals.editTempo(TempoEdit(add: [TempoPoint(tick: 970, microsecondsPerQuarterNote: 333_333)]))
    _ = globals.duplicateTime(
        TimeRange(startTick: 960, endTick: 980),
        scope: TimeScope(wholeSong: true))
    report.expect(
        globals.timeSignatures.contains { $0.tick == 980 && $0.numerator == 3 }
            && globals.rawChunks[0].events.contains { $0.tick == 985 && $0.metaType == 0x01 }
            && globals.state.tempo.contains { $0.tick == 990 },
        cppID: "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
        message: "signature, opaque global and tempo duplicate with their stream rules")

    // timeRangeSignatureAndOrphans: faithful signature-insert port.
    do {
        let signature = try timeRangeDocument()
        let signatureID = "editcheck/EditCheckTest::timeRangeSignatureAndOrphans"
        report.expectEqual(
            expected: 2, actual: signature.engineTracks.usedTrackCount, cppID: signatureID,
            what: "timeRangeFile fixture loads two editable tracks")
        let seam: Tick = 960
        let bar = 3 * Tick(signature.state.file.division)
        signature.setTimeSignature(tick: 0, numerator: 4, denominatorPower: 2)
        signature.setTimeSignature(tick: seam, numerator: 3, denominatorPower: 2)
        let signatureBefore = coreTimeBytes(signature)
        report.expect(
            signature.insertBlankTime(
                TimeRange(
                    startTick: seam,
                    endTick: seam + bar),
                scope: TimeScope(wholeSong: true)),
            cppID: signatureID, message: "whole-song signature insertion commits")
        let signatures = signature.timeSignatures.filter {
            $0.numerator == 3 && $0.denominatorPower == 2
        }
        report.expect(
            signatures.contains { $0.tick == seam }, cppID: signatureID,
            message: "signature stays at the seam")
        report.expect(
            signatures.contains { $0.tick == seam + bar }, cppID: signatureID,
            message: "signature copy lands one bar later")
        let signatureAfter = coreTimeBytes(signature)
        _ = signature.history.undoDocument()
        report.expectEqual(
            expected: signatureBefore, actual: coreTimeBytes(signature), cppID: signatureID,
            what: "one undo restores the signature insertion")
        _ = signature.history.redoDocument()
        report.expectEqual(
            expected: signatureAfter, actual: coreTimeBytes(signature), cppID: signatureID,
            what: "one redo restores the signature insertion")
    } catch {
        report.fail(
            "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
            "signature fixture failed: \(error)")
    }

    // timeRangeSignatureAndOrphans: faithful orphan-removal port.
    do {
        let orphans = try timeRangeDocument()
        let orphanID = "editcheck/EditCheckTest::timeRangeSignatureAndOrphans"
        report.expectEqual(
            expected: 2, actual: orphans.engineTracks.usedTrackCount, cppID: orphanID,
            what: "timeRangeFile fixture loads two editable tracks")
        guard let orphanChunk = orphans.engineTracks.tracks[0].midiChunk else {
            report.fail(orphanID, "engine track 0 has no MIDI chunk")
            return
        }
        _ = try orphans.addNotes([
            NewNote(track: 0, tick: 40, pitch: 60, duration: 10, velocity: 90)
        ])
        orphans.insertRawEvent(
            chunk: orphanChunk,
            event: .channel(
                tick: 90, status: 0x90,
                data0: 61, data1: 11))
        orphans.insertRawEvent(
            chunk: orphanChunk,
            event: .channel(
                tick: 120, status: 0x80,
                data0: 66, data1: 13))
        orphans.insertRawEvent(
            chunk: orphanChunk,
            event: .channel(
                tick: 110, status: 0x90,
                data0: 62, data1: 22))
        orphans.insertRawEvent(
            chunk: orphanChunk,
            event: .channel(
                tick: 130, status: 0x80,
                data0: 63, data1: 12))
        orphans.insertRawEvent(
            chunk: orphanChunk,
            event: .channel(
                tick: 130, status: 0x90,
                data0: 64, data1: 33))
        orphans.insertRawEvent(
            chunk: orphanChunk,
            event: .channel(
                tick: 140, status: 0x90,
                data0: 65, data1: 44))
        let orphanBefore = coreTimeBytes(orphans)
        report.expect(
            orphans.removeTime(
                TimeRange(startTick: 100, endTick: 130),
                scope: TimeScope(tracks: [0])),
            cppID: orphanID, message: "orphan removal commits")
        let orphanEvents = orphans.rawChunks[orphanChunk].events
        report.expect(
            hasChannel(orphanEvents, tick: 90, type: 0x9, key: 61),
            cppID: orphanID, message: "note-on before the range survives")
        report.expect(
            !hasChannel(orphanEvents, tick: 110, type: 0x9, key: 62),
            cppID: orphanID, message: "note-on inside the range is removed")
        report.expect(
            !orphanEvents.contains { event in
                guard case let .channel(status, data0, _) = event.payload else { return false }
                return status == 0x80 && data0 == 66
            }, cppID: orphanID, message: "orphaned note-off inside the range is removed")
        report.expect(
            !hasChannel(orphanEvents, tick: 110, type: 0x9, key: 62)
                && hasChannel(orphanEvents, tick: 100, type: 0x8, key: 63)
                && hasChannel(orphanEvents, tick: 100, type: 0x9, key: 64)
                && hasChannel(orphanEvents, tick: 110, type: 0x9, key: 65),
            cppID: "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
            message: "orphan note bytes use half-open remove and pinned seam ordering")
        report.expect(
            coreTimeNoteEndsBeforeOnsAt(orphans, track: 0, tick: 100),
            cppID: orphanID,
            message: "every note end at the seam precedes later note-ons")
        guard
            let paired = orphans.notes(in: 0).first(where: {
                $0.tick == 40 && $0.pitch == 60
            })
        else {
            report.fail(orphanID, "paired note missing after removal")
            return
        }
        report.expect(
            !paired.isUnterminated, cppID: orphanID,
            message: "paired note stays terminated")
        report.expectEqual(
            expected: Tick(10), actual: paired.duration, cppID: orphanID,
            what: "paired note keeps its duration")
        let orphanAfter = coreTimeBytes(orphans)
        _ = orphans.history.undoDocument()
        report.expectEqual(
            expected: orphanBefore, actual: coreTimeBytes(orphans), cppID: orphanID,
            what: "one undo restores the orphan removal")
        _ = orphans.history.redoDocument()
        report.expectEqual(
            expected: orphanAfter, actual: coreTimeBytes(orphans), cppID: orphanID,
            what: "one redo restores the orphan removal")
    } catch {
        report.fail(
            "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
            "orphan fixture failed: \(error)")
    }

    // timeRangeAutomationSeamsAndDefaults: faithful seam/defaults/tempo/voice port.
    do {
        let autoID = "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults"
        let automation = try timeRangeDocument()
        report.expectEqual(
            expected: 2, actual: automation.engineTracks.usedTrackCount, cppID: autoID,
            what: "timeRangeFile fixture loads two editable tracks")
        let seam: Tick = 1000
        automation.writeLane(
            track: 0, lane: .controller(7), from: seam - 20,
            through: seam - 20,
            points: [LaneWrite(tick: seam - 20, value: 33)])
        automation.writeLane(
            track: 0, lane: .controller(7), from: seam + 10,
            through: seam + 10,
            points: [LaneWrite(tick: seam + 10, value: 44)])
        let seamBefore = coreTimeBytes(automation)
        let seamPosition = try coreEditHistoryCountAtTip(
            automation, report: report,
            cppID: autoID)
        report.expect(
            automation.duplicateTime(
                TimeRange(
                    startTick: seam,
                    endTick: seam + 40),
                scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .controller(7))])),
            cppID: autoID, message: "lane-scoped duplication commits")
        report.expectEqual(
            expected: "1040:33",
            actual: automation.lanePoints(track: 0, lane: .controller(7))
                .first(where: { $0.tick == seam + 40 }).map(coreTimePointShape),
            cppID: autoID, what: "seam copy seeds the effective value")
        report.expectEqual(
            expected: "1050:44",
            actual: automation.lanePoints(track: 0, lane: .controller(7))
                .first(where: { $0.tick == seam + 50 }).map(coreTimePointShape),
            cppID: autoID, what: "in-range point copies to its shifted tick")
        report.expectEqual(
            expected: seamPosition + 1,
            actual: try coreEditHistoryCountAtTip(
                automation, report: report,
                cppID: autoID),
            cppID: autoID, what: "lane duplication adds one history entry")
        let seamAfter = coreTimeBytes(automation)
        _ = automation.history.undoDocument()
        report.expectEqual(
            expected: seamBefore, actual: coreTimeBytes(automation), cppID: autoID,
            what: "one undo restores the seam duplication")
        _ = automation.history.redoDocument()
        report.expectEqual(
            expected: seamAfter, actual: coreTimeBytes(automation), cppID: autoID,
            what: "one redo restores the seam duplication")

        let defaults = try timeRangeDocument()
        report.expectEqual(
            expected: 2, actual: defaults.engineTracks.usedTrackCount, cppID: autoID,
            what: "timeRangeFile fixture loads two editable tracks")
        let cases: [(lane: Lane, source: Int, expected: Int)] = [
            (.controller(0x01), 11, 0),
            (.controller(0x05), 12, 0),
            (.controller(0x07), 80, 127),
            (.controller(0x0A), 81, 64),
            (.controller(0x14), 3, 2),
            (.controller(0x15), 4, 22),
            (.controller(0x17), 5, 0),
            (.controller(0x19), 6, 0),
            (.pitchBend, 500, 0),
        ]
        for index in stride(from: cases.count - 1, through: 0, by: -1) {
            let entry = cases[index]
            let start: Tick = 1100 + Tick(index) * 40
            defaults.writeLane(
                track: 0, lane: entry.lane, from: start + 10,
                through: start + 10,
                points: [LaneWrite(tick: start + 10, value: entry.source)])
            let caseBefore = coreTimeBytes(defaults)
            let casePosition = try coreEditHistoryCountAtTip(
                defaults, report: report,
                cppID: autoID)
            report.expect(
                defaults.duplicateTime(
                    TimeRange(
                        startTick: start,
                        endTick: start + 20),
                    scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: entry.lane)])),
                cppID: autoID, message: "default-seeding duplication commits")
            report.expectEqual(
                expected: "\(start + 20):\(entry.expected)",
                actual: defaults.lanePoints(track: 0, lane: entry.lane)
                    .first(where: { $0.tick == start + 20 }).map(coreTimePointShape),
                cppID: autoID, what: "destination seam seeds the lane default")
            report.expectEqual(
                expected: casePosition + 1,
                actual: try coreEditHistoryCountAtTip(
                    defaults, report: report,
                    cppID: autoID),
                cppID: autoID,
                what: "default duplication adds one history entry")
            let caseAfter = coreTimeBytes(defaults)
            _ = defaults.history.undoDocument()
            report.expectEqual(
                expected: caseBefore, actual: coreTimeBytes(defaults), cppID: autoID,
                what: "one undo restores the default duplication")
            _ = defaults.history.redoDocument()
            report.expectEqual(
                expected: caseAfter, actual: coreTimeBytes(defaults), cppID: autoID,
                what: "one redo restores the default duplication")
        }

        defaults.editTempo(
            TempoEdit(
                remove: [TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000)],
                add: [TempoPoint(tick: 1510, microsecondsPerQuarterNote: 400_000)]))
        let tempoBytesBefore = coreTimeBytes(defaults)
        let temposBefore = defaults.state.tempo
        let tempoPosition = try coreEditHistoryCountAtTip(
            defaults, report: report,
            cppID: autoID)
        report.expect(
            defaults.duplicateTime(
                TimeRange(startTick: 1500, endTick: 1520),
                scope: TimeScope(tempo: true)),
            cppID: autoID, message: "tempo-scoped duplication commits")
        report.expect(
            defaults.state.tempo.contains(
                TempoPoint(tick: 1520, microsecondsPerQuarterNote: 500_000)),
            cppID: autoID, message: "boundary tempo copies to the destination seam")
        report.expect(
            defaults.state.tempo.contains(
                TempoPoint(tick: 1530, microsecondsPerQuarterNote: 400_000)),
            cppID: autoID, message: "in-range tempo copies to its shifted tick")
        let timeline = PlaybackTimeline.build(state: defaults.state, sampleRate: 44_100)
        report.expect(
            !timeline.tempoMap.isEmpty, cppID: autoID,
            message: "tempo map is non-empty after duplication")
        report.expectEqual(
            expected: 120.0, actual: timeline.tempoMap.first?.beatsPerMinute, cppID: autoID,
            what: "tempo map starts at 120 bpm")
        report.expectEqual(
            expected: tempoPosition + 1,
            actual: try coreEditHistoryCountAtTip(
                defaults, report: report,
                cppID: autoID),
            cppID: autoID, what: "tempo duplication adds one history entry")
        let tempoBytesAfter = coreTimeBytes(defaults)
        let temposAfter = defaults.state.tempo
        _ = defaults.history.undoDocument()
        report.expectEqual(
            expected: tempoBytesBefore, actual: coreTimeBytes(defaults), cppID: autoID,
            what: "one undo restores the tempo duplication")
        report.expectEqual(
            expected: temposBefore, actual: defaults.state.tempo, cppID: autoID,
            what: "one undo restores the tempo points")
        _ = defaults.history.redoDocument()
        report.expectEqual(
            expected: tempoBytesAfter, actual: coreTimeBytes(defaults), cppID: autoID,
            what: "one redo restores the tempo duplication")
        report.expectEqual(
            expected: temposAfter, actual: defaults.state.tempo, cppID: autoID,
            what: "one redo restores the tempo points")

        defaults.writeLane(
            track: 0, lane: .voice, from: 1610, through: 1610,
            points: [LaneWrite(tick: 1610, value: 12)])
        let voiceBefore = coreTimeBytes(defaults)
        let voicePosition = try coreEditHistoryCountAtTip(
            defaults, report: report,
            cppID: autoID)
        report.expect(
            defaults.duplicateTime(
                TimeRange(startTick: 1600, endTick: 1620),
                scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .voice)])),
            cppID: autoID, message: "voice-scoped duplication commits")
        report.expectEqual(
            expected: "1620:1",
            actual: defaults.lanePoints(track: 0, lane: .voice)
                .first(where: { $0.tick == 1620 }).map(coreTimePointShape),
            cppID: autoID, what: "voice seam seeds the default program")
        report.expectEqual(
            expected: "1630:12",
            actual: defaults.lanePoints(track: 0, lane: .voice)
                .first(where: { $0.tick == 1630 }).map(coreTimePointShape),
            cppID: autoID, what: "voice point copies to its shifted tick")
        report.expectEqual(
            expected: voicePosition + 1,
            actual: try coreEditHistoryCountAtTip(
                defaults, report: report,
                cppID: autoID),
            cppID: autoID, what: "voice duplication adds one history entry")
        let voiceAfter = coreTimeBytes(defaults)
        _ = defaults.history.undoDocument()
        report.expectEqual(
            expected: voiceBefore, actual: coreTimeBytes(defaults), cppID: autoID,
            what: "one undo restores the voice duplication")
        _ = defaults.history.redoDocument()
        report.expectEqual(
            expected: voiceAfter, actual: coreTimeBytes(defaults), cppID: autoID,
            what: "one redo restores the voice duplication")

        let downstream: Tick = 1700
        defaults.writeLane(
            track: 0, lane: .controller(7), from: downstream,
            through: downstream,
            points: [LaneWrite(tick: downstream, value: 11)])
        defaults.writeLane(
            track: 0, lane: .controller(7), from: downstream + 20,
            through: downstream + 20,
            points: [LaneWrite(tick: downstream + 20, value: 99)])
        let downstreamBefore = coreTimeBytes(defaults)
        let downstreamPosition = try coreEditHistoryCountAtTip(
            defaults, report: report,
            cppID: autoID)
        report.expect(
            defaults.duplicateTime(
                TimeRange(
                    startTick: downstream,
                    endTick: downstream + 20),
                scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .controller(7))])),
            cppID: autoID, message: "downstream lane duplication commits")
        report.expectEqual(
            expected: "1720:11",
            actual: defaults.lanePoints(track: 0, lane: .controller(7))
                .first(where: { $0.tick == downstream + 20 }).map(coreTimePointShape),
            cppID: autoID, what: "downstream seam seeds the effective value")
        report.expectEqual(
            expected: "1740:99",
            actual: defaults.lanePoints(track: 0, lane: .controller(7))
                .first(where: { $0.tick == downstream + 40 }).map(coreTimePointShape),
            cppID: autoID, what: "downstream point copies to its shifted tick")
        report.expectEqual(
            expected: downstreamPosition + 1,
            actual: try coreEditHistoryCountAtTip(
                defaults, report: report,
                cppID: autoID),
            cppID: autoID,
            what: "downstream duplication adds one history entry")
        let downstreamAfter = coreTimeBytes(defaults)
        _ = defaults.history.undoDocument()
        report.expectEqual(
            expected: downstreamBefore, actual: coreTimeBytes(defaults), cppID: autoID,
            what: "one undo restores the downstream duplication")
        _ = defaults.history.redoDocument()
        report.expectEqual(
            expected: downstreamAfter, actual: coreTimeBytes(defaults), cppID: autoID,
            what: "one redo restores the downstream duplication")
    } catch {
        report.fail(
            "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
            "automation fixture failed: \(error)")
    }

    // timeRangeWholeSong: faithful whole-song duplication port.
    do {
        let wholeID = "editcheck/EditCheckTest::timeRangeWholeSong"
        let wholeDuplicate = try timeRangeDocument()
        report.expectEqual(
            expected: 2, actual: wholeDuplicate.engineTracks.usedTrackCount, cppID: wholeID,
            what: "timeRangeFile fixture loads two editable tracks")
        let start: Tick = 1800
        _ = try wholeDuplicate.addNotes([
            NewNote(track: 0, tick: 1900, pitch: 70, duration: 5, velocity: 50)
        ])
        wholeDuplicate.setTimeSignature(
            tick: start + 10, numerator: 3,
            denominatorPower: 2)
        wholeDuplicate.editTempo(
            TempoEdit(
                add: [
                    TempoPoint(
                        tick: start + 10,
                        microsecondsPerQuarterNote: 333_333)
                ]))
        wholeDuplicate.insertRawEvent(
            chunk: 0,
            event: .meta(
                tick: start + 15, type: 0x01,
                data: Array("global".utf8)))
        let wholeDuplicateBefore = coreTimeBytes(wholeDuplicate)
        report.expect(
            wholeDuplicate.duplicateTime(
                TimeRange(
                    startTick: start,
                    endTick: start + 20),
                scope: TimeScope(wholeSong: true)),
            cppID: wholeID, message: "whole-song duplication commits")
        report.expect(
            wholeDuplicate.rawChunks[0].events.contains { event in
                event.tick == start + 35 && event.metaType == 0x01 && event.blob == Array("global".utf8)
            }, cppID: wholeID, message: "text meta copies to the duplicated seam")
        report.expect(
            wholeDuplicate.timeSignatures.contains {
                $0.tick == start + 30 && $0.numerator == 3
            }, cppID: wholeID, message: "signature copies to the duplicated seam")
        report.expect(
            wholeDuplicate.state.tempo.contains(
                TempoPoint(tick: start + 20, microsecondsPerQuarterNote: 500_000)),
            cppID: wholeID, message: "default tempo copies to the seam")
        report.expect(
            wholeDuplicate.state.tempo.contains(
                TempoPoint(tick: start + 30, microsecondsPerQuarterNote: 333_333)),
            cppID: wholeID, message: "in-range tempo copies to its shifted tick")
        guard
            let shifted = wholeDuplicate.notes(in: 0).first(where: {
                $0.tick == 1920 && $0.pitch == 70
            })
        else {
            report.fail(wholeID, "shifted note missing after duplication")
            return
        }
        guard let wholeChunk = wholeDuplicate.engineTracks.tracks[0].midiChunk else {
            report.fail(wholeID, "engine track 0 has no MIDI chunk")
            return
        }
        report.expect(
            wholeDuplicate.rawChunks[wholeChunk].endTick >= UInt64(shifted.tick) + UInt64(shifted.duration),
            cppID: wholeID,
            message: "chunk end tick covers the duplicated note")
        let wholeDuplicateAfter = coreTimeBytes(wholeDuplicate)
        _ = wholeDuplicate.history.undoDocument()
        report.expectEqual(
            expected: wholeDuplicateBefore, actual: coreTimeBytes(wholeDuplicate),
            cppID: wholeID,
            what: "one undo restores the whole-song duplication")
        _ = wholeDuplicate.history.redoDocument()
        report.expectEqual(
            expected: wholeDuplicateAfter, actual: coreTimeBytes(wholeDuplicate),
            cppID: wholeID,
            what: "one redo restores the whole-song duplication")
    } catch {
        report.fail(
            "editcheck/EditCheckTest::timeRangeWholeSong",
            "whole-song duplication fixture failed: \(error)")
    }
    duplicateSeamOrder(report)
}

/// Seeds at a duplicate's seam keep their source order; stream grouping is hash-ordered.
@MainActor
private func duplicateSeamOrder(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults"
    let document = timeDocument()
    for controller: UInt8 in [91, 1, 10, 7, 11] {
        document.writeLane(
            track: 0, lane: .controller(controller), from: 580, through: 580,
            points: [LaneWrite(tick: 580, value: 40)])
    }
    guard let chunk = document.engineTracks.tracks[0].midiChunk else {
        report.fail(id, "track 0 has no MIDI chunk")
        return
    }
    func controllers(at tick: Tick) -> [UInt8] {
        document.rawChunks[chunk].events.compactMap { event in
            guard event.tick == tick, event.typeNibble == 0xB, case let .channel(_, first, _) = event.payload
            else { return nil }
            return first
        }
    }
    let source = controllers(at: 580)
    // Hash order changes per process and table address, so several rounds catch a regression.
    for _ in 0..<4 {
        report.expect(
            document.duplicateTime(TimeRange(startTick: 590, endTick: 610), scope: TimeScope(tracks: [0])),
            cppID: id, message: "seam-order duplication commits")
        report.expect(
            source.count == 5 && controllers(at: 610) == source,
            cppID: id, message: "duplicate seeds its seam controllers in source order")
        report.expect(document.history.undoDocument(), cppID: id, message: "seam-order duplication undoes")
    }
}
