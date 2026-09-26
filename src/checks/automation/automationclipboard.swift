import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawBankLease

// Existing scenarios paired with automationclipboard.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationRangeEditAndClipboard(_ report: CheckReport, suite: DocumentSession,
                                   service: ProjectService) {
    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    _ = pd_clipboard_write(nil, 0)
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    fixture.activate(fixture.panLane)
    func pasteRowEnabled() -> Bool? {
        let x = fixture.x(80)
        let y = fixture.y(fixture.panLane, 80)
        _ = fixture.page.pointerPress(x: x, y: y, surface: AutomationInputSurface.plot.rawValue,
                                      button: AutomationQtButton.right, modifiers: 0)
        _ = fixture.page.pointerRelease(x: x, y: y, button: AutomationQtButton.right, modifiers: 0)
        defer { fixture.page.dismissMenu() }
        return fixture.page.publishedMenuRows.first {
            $0.actionId == AutomationMenuAction.rangePaste.rawValue
        }?.enabled
    }
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 130), scope: .lanes,
        lanes: [fixture.panLane], tempo: true))
    report.expect(pasteRowEnabled() == false, cppID: drawerAutomationRangeID,
                  message: "the range menu refuses Paste when the system clipboard is empty")
    report.expect(!fixture.page.selectionCommandAvailable(command: .paste), cppID: drawerAutomationRangeID,
                  message: "the window Paste command is unavailable for an empty clipboard")
    report.expect(fixture.page.copyTimeSelection(), cppID: drawerAutomationRangeID,
                  message: "the selection copies into the semantic clipboard")
    report.expect(fixture.page.hasClipboard, cppID: drawerAutomationRangeID,
                  message: "the clipboard publishes its semantic payload")
    report.expect(pasteRowEnabled() == true, cppID: drawerAutomationRangeID,
                  message: "the range menu enables Paste for a copied system selection")
    report.expect(fixture.page.selectionCommandAvailable(command: .paste), cppID: drawerAutomationRangeID,
                  message: "the window Paste command becomes available for the copied selection")
    let beforePaste = fixture.snapshot
    report.expectEqual(expected: 310, actual: fixture.page.pasteTimeSelection(at: 200).map(Int.init) ?? -1,
                       cppID: drawerAutomationRangeID,
                       what: "the paste cursor lands one span after the destination")
    report.expectEqual(expected: ["24:30", "120:40", "204:30", "300:40"], actual: fixture.values(fixture.panLane),
                       cppID: drawerAutomationRangeID,
                       what: "the pasted lane writes its relative points at the destination")
    report.expectEqual(expected: ["0:120", "48:150", "228:150"], actual: fixture.tempoValues, cppID: drawerAutomationRangeID,
                       what: "the pasted tempo point merges at its destination tick")
    report.expectEqual(expected: beforePaste.revision + 1, actual: fixture.document.revision, cppID: drawerAutomationRangeID,
                       what: "one paste is one document revision")
    report.expect(fixture.undo(), cppID: drawerAutomationRangeID, message: "the paste is undoable")
    report.expectEqual(expected: ["24:30", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationRangeID,
                       what: "one undo removes the pasted lane points")
    report.expectEqual(expected: ["0:120", "48:150"], actual: fixture.tempoValues, cppID: drawerAutomationRangeID,
                       what: "one undo removes the pasted tempo point")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationRangeID,
                  message: "one undo consumes the paste's single history entry")

    let cut = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 30), (120, 40)])
    cut.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 100), scope: .lanes, lanes: [cut.panLane]))
    let cutBefore = cut.snapshot
    report.expect(cut.page.cutTimeSelection(), cppID: drawerAutomationRangeID,
                  message: "the cut copies and deletes in one document write")
    report.expectEqual(expected: ["120:40"], actual: cut.values(cut.panLane), cppID: drawerAutomationRangeID,
                       what: "the cut removes only the covered span")
    report.expectEqual(expected: cutBefore.revision + 1, actual: cut.document.revision, cppID: drawerAutomationRangeID,
                       what: "the cut is one revision")
    report.expect(cut.page.hasClipboard && cut.undo(), cppID: drawerAutomationRangeID,
                  message: "the cut keeps its payload and is undoable")
    report.expectEqual(expected: ["24:30", "120:40"], actual: cut.values(cut.panLane), cppID: drawerAutomationRangeID,
                       what: "one undo restores the cut span")
    report.expect(!cut.document.history.canUndo, cppID: drawerAutomationRangeID,
                  message: "one undo consumes the cut's single history entry")

    // Lane copy is cross-parameter but must not overwrite the system range clip.
    cut.activate(cut.panLane)
    _ = cut.page.openParameterMenu(index: cut.page.catalogIndex(of: cut.panLane), x: 0, y: 0)
    report.expect(cut.page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: drawerAutomationRangeID, message: "lane menu copies its absolute points")
    cut.activate(cut.volumeLane)
    _ = cut.page.openParameterMenu(index: cut.page.catalogIndex(of: cut.volumeLane), x: 0, y: 0)
    report.expect(cut.page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: drawerAutomationRangeID, message: "lane menu pastes into another parameter")
    report.expectEqual(expected: ["24:30", "120:40"], actual: cut.values(cut.volumeLane), cppID: drawerAutomationRangeID,
                       what: "lane paste preserves absolute ticks across parameters")
    cut.page.detach()
    let otherDocument = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    report.expectEqual(expected: 280, actual: otherDocument.page.pasteTimeSelection(at: 200).map(Int.init) ?? -1,
                       cppID: drawerAutomationRangeID, what: "the native range clip survives lane copy and detach")
    report.expectEqual(expected: ["204:30"], actual: otherDocument.values(otherDocument.panLane), cppID: drawerAutomationRangeID,
                       what: "another document pastes the shared range clip, not the lane buffer")

    // A whole-lane replacement keeps the lane's own point rules.
    let replace = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 30)])
    replace.activate(replace.panLane)
    let edit = AutomationRangeEditor.replaceLane(
        replace.facts(replace.panLane),
        points: [AutomationLanePoint(tick: 48, value: 200),
                 AutomationLanePoint(tick: 48, value: 20),
                 AutomationLanePoint(tick: 96, value: -5)])
    report.expect(!edit.unchanged, cppID: drawerAutomationRangeID,
                  message: "a replacement that differs from the lane is a change")
    report.expectEqual(expected: Tick(0), actual: edit.tickBegin, cppID: drawerAutomationRangeID,
                       what: "a whole-lane replacement starts at tick zero")
    report.expectEqual(expected: TimeDefaults.noTick, actual: edit.tickEnd, cppID: drawerAutomationRangeID,
                       what: "a whole-lane replacement covers the whole lane")
    report.expect(AutomationCommit.apply(edit, in: replace.document), cppID: drawerAutomationRangeID,
                  message: "the replacement commits through one lane write")
    report.expectEqual(expected: ["48:20", "96:0"], actual: replace.values(replace.panLane), cppID: drawerAutomationRangeID,
                       what: "the replacement deduplicates by tick and clamps into the domain")
    let clear = AutomationRangeEditor.replaceLane(replace.facts(replace.panLane), points: [])
    report.expect(AutomationCommit.apply(clear, in: replace.document), cppID: drawerAutomationRangeID,
                  message: "clearing the lane writes once")
    report.expectEqual(expected: 0, actual: replace.lanePoints(replace.panLane).count, cppID: drawerAutomationRangeID,
                       what: "clearing removes every written point")
    report.expect(AutomationRangeEditor.replaceLane(replace.facts(replace.panLane),
                                                    points: []).unchanged,
                  cppID: drawerAutomationRangeID, message: "clearing an empty lane is unchanged")
}

@MainActor
func drawerAutomationCrossLanePasteClamps(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "automation/AutomationEditingTest::clipboardCrossLanePasteClamps"
    let lfo = AutomationParameter.controlChange(track: 0, controller: 21)
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(96, TimeDefaults.microsecondsPerQuarterNote(forBPM: 300))])
    fixture.document.writeLane(track: 0, lane: .controller(21), from: 0,
                               through: TimeDefaults.maxTick,
                               points: [LaneWrite(tick: 96, value: 96)])
    let page = fixture.page
    fixture.activate(.tempo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: .tempo), x: 0, y: 0),
                  cppID: id, message: "the tempo label opens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: id, message: "the tempo Copy row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Copy tempo pick closes the menu")
    fixture.activate(lfo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: lfo), x: 0, y: 0),
                  cppID: id, message: "the CC label opens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: id, message: "the Paste CC row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Paste CC pick closes the menu")
    report.expectEqual(expected: ["96:127"], actual: fixture.values(lfo), cppID: id,
                       what: "the pasted tempo point clamps into the CC domain at its tick")
    fixture.document.writeLane(track: 0, lane: .controller(21), from: 0,
                               through: TimeDefaults.maxTick,
                               points: [LaneWrite(tick: 144, value: 0)])
    fixture.activate(lfo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: lfo), x: 0, y: 0),
                  cppID: id, message: "the CC label reopens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: id, message: "the Copy CC row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Copy CC pick closes the menu")
    fixture.activate(.tempo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: .tempo), x: 0, y: 0),
                  cppID: id, message: "the tempo label reopens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: id, message: "the Paste tempo row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Paste tempo pick closes the menu")
    let pasted = fixture.document.state.tempo
    report.expectEqual(expected: 1, actual: pasted.count, cppID: id,
                       what: "the pasted CC point replaces the tempo stream")
    report.expectEqual(expected: Tick(144), actual: pasted.first?.tick ?? Tick.max, cppID: id,
                       what: "the pasted tempo point keeps the CC tick")
    report.expectEqual(expected: TimeDefaults.microsecondsPerQuarterNote(forBPM: TimeDefaults.minimumTempoBPM), actual:
                       pasted.first?.microsecondsPerQuarterNote ?? 0, cppID: id,
                       what: "the pasted tempo point clamps to the slowest tempo")
}

@MainActor
func drawerAutomationTrackScopedSelectionClipboard(_ report: CheckReport, suite: DocumentSession,
                                                   service: ProjectService) {
    let copyID = "clipcheck/ClipCheckTest::timeSelectionCopy"
    let scopedID = "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks"
    let deleteID = "clipcheck/ClipCheckTest::rangeDeleteCutAndUndo"
    let noteID = "clipcheck/ClipCheckTest::sameDocumentPaste"
    let crossID = "clipcheck/ClipCheckTest::crossTpbNotePaste"
    let mergeID = "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo"
    let emptyID = "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop"
    let tileID = "clipcheck/ClipCheckTest::tiledTimePasteUndoesOneTileAtATime"
    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    let clipboard = GridClipboard()
    _ = pd_clipboard_write(nil, 0)

    let single = drawerAutomationAutomationFixture(suite: suite, service: service)
    single.session.setSelectedNotes(single.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    single.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .tracks([0])))
    report.expect(single.session.selectedNotes.isEmpty, cppID: copyID,
                  message: "a time-selection commit clears the competing note selection")
    report.expect(single.session.timeSelection?.isActive == true
                      && single.session.timeSelection?.range == TimeRange(startTick: 0, endTick: 96),
                  cppID: copyID, message: "the committed time selection is active over its exact range")
    report.expect(single.session.timeSelection?.scope == .tracks([0]), cppID: copyID,
                  message: "the committed scope is track-scoped")
    report.expect(single.session.timeSelection?.scope == .tracks([0]), cppID: copyID,
                  message: "the stored track scope keeps the swept tracks")
    report.expect(!single.page.selectionCommandAvailable(command: .paste), cppID: copyID,
                  message: "Paste is unavailable without native clip bytes")
    report.expect(single.page.consumeSelectionCommand(command: .copy), cppID: copyID,
                  message: "Copy consumes the committed track selection")
    let singleClip = clipboard.read()
    report.expect(singleClip?.ticksPerBeat == 24 && singleClip?.clip.span == 96
                      && singleClip?.clip.tracks == [ClipTrack(track: 0, notes: [
                          ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
                      ])],
                  cppID: copyID, message: "Copy over an active time selection writes the decodable span clip")
    report.expect(single.page.selectionCommandAvailable(command: .paste), cppID: copyID,
                  message: "Paste becomes available after track-scoped Copy")

    let scoped = drawerAutomationAutomationFixture(suite: suite, service: service)
    scoped.document.deleteNotes(scoped.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    for (track, tick, pitch, duration, velocity, laneTick, laneValue) in [
        (0, Tick(12), UInt8(60), Tick(12), UInt8(90), Tick(18), 11),
        (1, Tick(24), UInt8(64), Tick(24), UInt8(100), Tick(30), 22),
        (2, Tick(36), UInt8(68), Tick(36), UInt8(110), Tick(42), 33),
    ] {
        if track > 0 { _ = scoped.document.addTrack(voice: 0) }
        guard (try? scoped.document.addNotes([
            NewNote(track: track, tick: tick, pitch: pitch, duration: duration, velocity: velocity),
        ]))?.count == 1 else {
            report.fail(scopedID, "the scoped copy fixture could not stage its source note")
            return
        }
        scoped.document.writeLane(track: track, lane: .controller(1), from: laneTick,
                                  through: laneTick, points: [LaneWrite(tick: laneTick, value: laneValue)])
    }
    scoped.session.setSelectedNotes(scoped.document.notes(in: 0).filter { $0.tick == 12 }.map(\.id))
    scoped.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .tracks([0, 1, 2])))
    report.expect(scoped.session.selectedNotes.isEmpty, cppID: scopedID,
                  message: "a time-selection commit clears the competing note selection")
    report.expect(scoped.session.timeSelection?.isActive == true
                      && scoped.session.timeSelection?.range == TimeRange(startTick: 0, endTick: 96),
                  cppID: scopedID, message: "the committed time selection is active over its exact range")
    report.expect(scoped.session.timeSelection?.scope == .tracks([0, 1, 2]), cppID: scopedID,
                  message: "the committed scope is track-scoped")
    report.expect(scoped.session.timeSelection?.scope == .tracks([0, 1, 2]), cppID: scopedID,
                  message: "the stored track scope keeps the swept tracks")
    report.expect(scoped.page.consumeSelectionCommand(command: .copy), cppID: scopedID,
                  message: "Copy consumes the three-track selection")
    let scopedClip = clipboard.read()
    report.expect(scopedClip?.clip.span == 96
                      && scopedClip?.clip.tracks.map(\.track) == [0, 1, 2]
                      && scopedClip?.clip.tracks.map(\.notes) == [
                          [ClipNote(relTick: 12, key: 60, duration: 12, velocity: 90)],
                          [ClipNote(relTick: 24, key: 64, duration: 24, velocity: 100)],
                          [ClipNote(relTick: 36, key: 68, duration: 36, velocity: 110)],
                      ]
                      && scopedClip?.clip.lanes.filter { $0.cc == 1 }.map(\.points) == [
                          [ClipLanePoint(relTick: 18, value: 11)],
                          [ClipLanePoint(relTick: 30, value: 22)],
                          [ClipLanePoint(relTick: 42, value: 33)],
                      ], cppID: scopedID,
                  message: "Copy over an active time selection writes the decodable span clip")
    let destination = drawerAutomationAutomationFixture(suite: suite, service: service)
    destination.document.deleteNotes(destination.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    let destinationBefore = coreTimeBytes(destination.document)
    destination.session.editCursor = 0
    report.expect(destination.page.consumeSelectionCommand(command: .paste), cppID: scopedID,
                  message: "the scoped clip pastes through the production command")
    report.expect(destination.document.engineTracks.usedTrackCount == 3
                      && destination.document.notes(in: 0).contains { $0.tick == 12 && $0.pitch == 60 }
                      && destination.document.notes(in: 1).contains { $0.tick == 24 && $0.pitch == 64 }
                      && destination.document.notes(in: 2).contains { $0.tick == 36 && $0.pitch == 68 }
                      && destination.document.lanePoints(track: 2, lane: .controller(1))
                          .contains { $0.tick == 42 && $0.value == 33 }
                      && destination.session.editCursor == 96, cppID: scopedID,
                  message: "a scoped three-track paste expands the destination tracks")
    report.expect(destination.document.lanePoints(track: 0, lane: .controller(1))
                      .contains { $0.tick == 18 && $0.value == 11 }
                      && destination.document.lanePoints(track: 1, lane: .controller(1))
                          .contains { $0.tick == 30 && $0.value == 22 }
                      && destination.document.lanePoints(track: 2, lane: .controller(1))
                          .contains { $0.tick == 42 && $0.value == 33 }, cppID: scopedID,
                  message: "the expanded destination carries each track's modulation point")
    report.expect(destination.undo() && coreTimeBytes(destination.document) == destinationBefore
                      && destination.document.engineTracks.usedTrackCount == 1, cppID: scopedID,
                  message: "one Undo restores the destination track, lanes, and voice seed")

    let deleting = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     tempo: [(24, 600_000), (96, 400_000)])
    deleting.document.deleteNotes(deleting.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    report.expect((try? deleting.document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 96, pitch: 64, duration: 24, velocity: 80),
    ]))?.count == 2, cppID: deleteID, message: "the delete fixture stages both covered and retained notes")
    deleting.document.writeLane(track: 0, lane: .voice, from: 24, through: 24,
                                points: [LaneWrite(tick: 24, value: 3)])
    deleting.document.writeLane(track: 0, lane: .voice, from: 96, through: 96,
                                points: [LaneWrite(tick: 96, value: 5)])
    deleting.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 48), scope: .tracks([0])))
    let beforeDelete = coreTimeBytes(deleting.document)
    report.expect(deleting.page.consumeSelectionCommand(command: .copy), cppID: deleteID,
                  message: "range Copy captures the covered note, voice, and tempo")
    let copiedBeforeCut = clipboard.read()
    report.expect(deleting.page.consumeSelectionCommand(command: .delete), cppID: deleteID,
                  message: "Delete consumes the selected range")
    report.expect(deleting.document.notes(in: 0).filter { $0.tick < 120 }.map(\.tick) == [96]
                      && deleting.document.lanePoints(track: 0, lane: .voice).map(\.tick) == [96]
                      && deleting.document.state.tempo.map(\.tick) == [96], cppID: deleteID,
                  message: "range Delete removes the covered note, voice, and tempo only")
    report.expect(deleting.session.timeSelection?.isActive == true, cppID: deleteID,
                  message: "range delete leaves the time selection active")
    report.expect(deleting.undo() && coreTimeBytes(deleting.document) == beforeDelete, cppID: deleteID,
                  message: "one Undo restores the deleted note, voice, and tempo")
    report.expect(deleting.page.consumeSelectionCommand(command: .cut), cppID: deleteID,
                  message: "Cut consumes the selected range")
    let cutClip = clipboard.read()
    report.expect(cutClip == copiedBeforeCut
                      && cutClip?.clip.tracks.first?.notes == [
                          ClipNote(relTick: 24, key: 60, duration: 24, velocity: 100),
                      ]
                      && cutClip?.clip.lanes.first { $0.cc == TimeDefaults.laneCCVoice }?
                          .points.contains(ClipLanePoint(relTick: 24, value: 3)) == true
                      && cutClip?.clip.tempo.first?.relTick == 24
                      && deleting.document.notes(in: 0).filter { $0.tick < 120 }.map(\.tick) == [96],
                  cppID: deleteID, message: "range Cut publishes its payload and removes the covered content")
    report.expect(deleting.undo() && coreTimeBytes(deleting.document) == beforeDelete, cppID: deleteID,
                  message: "one Undo restores the cut note, voice, and tempo")

    let notes = drawerAutomationAutomationFixture(suite: suite, service: service)
    notes.document.deleteNotes(notes.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    guard let sourceIDs = try? notes.document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 36, pitch: 64, duration: 12, velocity: 80),
    ]), let noteClip = ClipboardSemantics.copyNotes(
        sourceIDs.compactMap(notes.document.note), from: 0, unterminatedDuration: 6) else {
        report.fail(noteID, "the two source notes cannot be staged for span-zero paste")
        return
    }
    notes.session.setSelectedNotes(sourceIDs)
    report.expect(clipboard.write(noteClip, ticksPerBeat: 24), cppID: noteID,
                  message: "the selected notes stage their span-zero clip")
    notes.session.editCursor = 48
    report.expect(notes.page.consumeSelectionCommand(command: .paste), cppID: noteID,
                  message: "note Paste consumes the copied clip")
    let inserted = notes.document.notes(in: 0).filter { $0.tick == 48 || $0.tick == 60 }
    report.expect(inserted.count == 2 && notes.session.selectedNotes == Set(inserted.map(\.id)),
                  cppID: noteID,
                  message: "a span-zero paste through the command path selects the pasted notes")
    report.expect(notes.session.editCursor == 72, cppID: noteID,
                  message: "a span-zero paste through the command path advances the cursor to the paste end")

    let cross = drawerAutomationAutomationFixture(suite: suite, service: service, division: 48)
    cross.session.editCursor = 24
    report.expect(clipboard.write(PorydawClip(tracks: [
        ClipTrack(track: 0, notes: [ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100)]),
    ]), ticksPerBeat: 24) && cross.page.consumeSelectionCommand(command: .paste), cppID: crossID,
                  message: "a 24-TPB clip pastes into the 48-TPB document")
    report.expect(cross.session.editCursor == 72
                      && cross.document.notes(in: 0).contains {
                          $0.tick == 24 && $0.pitch == 60 && $0.duration == 48
                      }, cppID: crossID,
                  message: "a rescaled cross-ticks-per-beat paste advances the cursor to the rescaled end")

    let merging = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    modulation: [(36, 40), (60, 70), (96, 40)],
                                                    tempo: [(0, 500_000), (25, 600_000), (60, 700_000)])
    merging.document.deleteNotes(merging.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    report.expect((try? merging.document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 48, pitch: 64, duration: 24, velocity: 100),
    ]))?.count == 2, cppID: mergeID, message: "the merge fixture stages its two destination notes")
    merging.session.editCursor = 24
    merging.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 48), scope: .tracks([0])))
    let beforeMerge = coreTimeBytes(merging.document)
    let mergeClip = PorydawClip(span: 48, tracks: [
        ClipTrack(track: 0, notes: [ClipNote(relTick: 0, key: 60, duration: 24, velocity: 120)]),
    ], lanes: [ClipLane(track: 0, cc: 1, points: [
        ClipLanePoint(relTick: 23, value: 110), ClipLanePoint(relTick: 24, value: 120),
    ])], tempo: [
        ClipTempo(relTick: 1, microsecondsPerQuarterNote: 300_000),
        ClipTempo(relTick: 2, microsecondsPerQuarterNote: 400_000),
    ])
    report.expect(clipboard.write(mergeClip, ticksPerBeat: 48)
                      && merging.page.consumeSelectionCommand(command: .paste), cppID: mergeID,
                  message: "the staged last-wins range clip pastes through the command")
    report.expect(merging.document.notes(in: 0).filter { $0.tick < 72 }
                      .map { "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)" } ==
                      ["24:60:12:120", "36:60:12:100", "48:64:24:100"]
                      && merging.document.lanePoints(track: 0, lane: .controller(1))
                          .map { "\($0.tick):\($0.value)" } == ["36:120", "60:70", "96:40"]
                      && merging.document.state.tempo.map {
                          "\($0.tick):\($0.microsecondsPerQuarterNote)"
                      } == ["0:500000", "25:400000", "60:700000"], cppID: mergeID,
                  message: "range paste uses last-wins lane and tempo points")
    report.expect(merging.session.editCursor == 48, cppID: mergeID,
                  message: "a last-wins range paste advances the cursor by its span")
    report.expect(merging.session.timeSelection == nil, cppID: mergeID,
                  message: "a range paste through the command path clears the active time selection")
    report.expect(merging.undo() && coreTimeBytes(merging.document) == beforeMerge, cppID: mergeID,
                  message: "one Undo restores the last-wins range merge")

    let empty = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  volume: [(144, 90)])
    empty.document.deleteNotes(empty.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    report.expect((try? empty.document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 62, duration: 24, velocity: 100),
    ]))?.count == 1, cppID: emptyID, message: "the empty-lane fixture stages its retained note")
    empty.session.editCursor = 120
    let emptyBefore = empty.snapshot
    let emptyRevision = empty.document.revision
    let emptyHistory = empty.document.history.currentIdentity
    report.expect(clipboard.write(PorydawClip(span: 48, lanes: [
        ClipLane(track: 0, cc: 7, points: []),
    ]), ticksPerBeat: 24), cppID: emptyID, message: "the empty lane clip is staged")
    _ = empty.page.consumeSelectionCommand(command: .paste)
    report.expect(empty.snapshot == emptyBefore && empty.document.revision == emptyRevision
                      && empty.document.history.currentIdentity == emptyHistory
                      && empty.document.notes(in: 0).contains { $0.tick == 24 && $0.pitch == 62 }
                      && empty.document.lanePoints(track: 0, lane: .controller(7))
                          .contains { $0.tick == 144 && $0.value == 90 }, cppID: emptyID,
                  message: "an empty lane paste through the command path changes neither document nor history")
    report.expect(empty.session.editCursor == 120, cppID: emptyID,
                  message: "an empty lane paste leaves the edit cursor unchanged")

    let tiled = drawerAutomationAutomationFixture(suite: suite, service: service)
    tiled.document.deleteNotes(tiled.document.notes(in: 0).filter { $0.tick == 0 }.map(\.id))
    tiled.session.editCursor = 0
    report.expect(clipboard.write(PorydawClip(span: 96, tracks: [
        ClipTrack(track: 0, notes: [ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100)]),
    ]), ticksPerBeat: 24), cppID: tileID, message: "the 96-tick tile is staged")
    let tileBefore = coreTimeBytes(tiled.document)
    _ = tiled.page.consumeSelectionCommand(command: .paste)
    let firstCursor = tiled.session.editCursor
    _ = tiled.page.consumeSelectionCommand(command: .paste)
    let secondCursor = tiled.session.editCursor
    let secondTile = tiled.document.notes(in: 0).contains { $0.tick == 96 && $0.pitch == 60 }
    let firstUndo = tiled.undo() && !tiled.document.notes(in: 0).contains { $0.tick == 96 && $0.pitch == 60 }
        && tiled.document.notes(in: 0).contains { $0.tick == 0 && $0.pitch == 60 }
    let secondUndo = tiled.undo() && coreTimeBytes(tiled.document) == tileBefore
    report.expect(firstCursor == 96 && secondCursor == 192 && secondTile && firstUndo && secondUndo,
                  cppID: tileID,
                  message: "each tiled paste advances the cursor by one span and retracts as its own undo entry")
}
