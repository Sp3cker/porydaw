import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with voice.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoiceUndoRedoRefresh(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let builds = page.contentBuildCount
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    _ = page.acceptPicker()
    report.expectEqual(expected: builds + 1, actual: page.contentBuildCount, cppID: drawerVoiceHistoryID,
                       what: "one committed edit rebuilds the projection exactly once")
    let editedBuilds = page.contentBuildCount
    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceHistoryID, "undo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > editedBuilds, cppID: drawerVoiceHistoryID,
                  message: "undo rebuilds every affected page")
    report.expectEqual(expected: [0, 48, 120], actual: page.markerTicks, cppID: drawerVoiceHistoryID,
                       what: "undo removes the inserted marker")
    report.expectEqual(expected: VoiceLanePolicy.label(slot: programs[0],
                                             view: fixture.session.bankSlots[programs[0]]), actual: 
                       page.contextLabel(at: page.contextSlot), cppID: drawerVoiceHistoryID,
                       what: "undo restores the context the readout resolves")
    let undoneBuilds = page.contentBuildCount
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceHistoryID, "redo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > undoneBuilds, cppID: drawerVoiceHistoryID,
                  message: "redo rebuilds the projection again")
    report.expectEqual(expected: [0, 48, 96, 120], actual: page.markerTicks, cppID: drawerVoiceHistoryID,
                       what: "redo republishes the full marker set")

    // An equal refresh leaves every marker exactly as it was: the rebuild runs,
    // and no published row is replaced.
    let identities = page.markerIdentities
    let publishedMarkers = page.markers.asArray
    page.refreshFromDocument()
    report.expectEqual(expected: identities, actual: page.markerIdentities, cppID: drawerVoiceHistoryID,
                       what: "an equal refresh leaves every marker identity in place")
    report.expectEqual(expected: publishedMarkers.count, actual: page.markers.count, cppID: drawerVoiceHistoryID,
                       what: "an equal refresh publishes the same marker count")
    report.expect(zip(publishedMarkers, page.markers.asArray).allSatisfy { $0 === $1 },
                  cppID: drawerVoiceHistoryID,
                  message: "an equal refresh replaces no published marker row")
}

@MainActor
func drawerVoicePlayheadDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let documentFacts = fixture.snapshot
    page.refreshPlayhead(tick: 0, playing: true)
    let builds = page.contentBuildCount
    let presentations = page.playheadPresentationCount
    let contextChanges = page.contextChangeCount
    let readout = page.readoutText
    report.expectEqual(expected: programs[0], actual: page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the playing context opens on the first program span")

    // Every other distinct shared tick inside the same span: the page consumes
    // each of them and rebuilds no static content.
    var ticks: [Double] = []
    for step in 1..<48 { ticks.append(Double(step)) }
    for tick in ticks {
        page.refreshPlayhead(tick: tick, playing: true)
    }
    report.expectEqual(expected: presentations + UInt64(ticks.count), actual: page.playheadPresentationCount,
                       cppID: drawerVoiceDiagnosticsID,
                       what: "every distinct shared presentation is consumed once")
    // A shared position that rounds to a tick the page already presented is not
    // a presentation of its own, and neither is an equal one.
    let roundingBase = page.playheadPresentationCount
    page.refreshPlayhead(tick: 47.4, playing: true)
    report.expectEqual(expected: roundingBase, actual: page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "a position rounding to an already presented tick presents nothing")
    page.refreshPlayhead(tick: 47, playing: true)
    report.expectEqual(expected: roundingBase, actual: page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "an equal presentation is not consumed twice")
    report.expectEqual(expected: builds, actual: page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "playhead-only movement inside one span rebuilds no content")
    report.expectEqual(expected: contextChanges, actual: page.contextChangeCount, cppID: drawerVoiceDiagnosticsID,
                       what: "no span was crossed inside the span itself")
    report.expectEqual(expected: programs[0], actual: page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the presented context stayed in its own span")
    report.expectEqual(expected: readout, actual: page.readoutText, cppID: drawerVoiceDiagnosticsID,
                       what: "the readout names the same program throughout the span")
    report.expectEqual(expected: documentFacts, actual: fixture.snapshot, cppID: drawerVoiceDiagnosticsID,
                       what: "playhead movement mutates no document and consumes no redo")

    // An equal presentation publishes nothing.
    let settled = page.playheadPresentationCount
    page.refreshPlayhead(tick: ticks.last ?? 0, playing: true)
    report.expectEqual(expected: settled, actual: page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "an equal presentation is not consumed twice")

    // Crossing into the next span updates the readout and rebuilds once.
    page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(expected: programs[1], actual: page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "crossing a span updates the context indicator")
    report.expectEqual(expected: builds + 1, actual: page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "crossing a span rebuilds the projection exactly once")
    report.expectEqual(expected: contextChanges + 1, actual: page.contextChangeCount, cppID: drawerVoiceDiagnosticsID,
                       what: "one context change is counted")
    report.expect(page.readoutText.hasPrefix(String(format: "%03d", programs[1])),
                  cppID: drawerVoiceDiagnosticsID, message: "the readout names the new span's program")

    // Stopping returns the context to the edit cursor.
    fixture.session.editCursor = 200
    page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(expected: programs[2], actual: page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the stopped context follows the edit cursor")
    report.expectEqual(expected: builds + 2, actual: page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "the playing-to-stopped transition rebuilds once")
}

@MainActor
func drawerVoiceHoverAndBankRefresh(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let hoverX = fixture.markerX(24)
    page.refreshPlayhead(tick: 8, playing: true)
    _ = page.pointerMove(x: hoverX, y: 10, buttons: 0)
    let hovered = page.hoverText
    _ = page.pointerMove(x: hoverX, y: 10, buttons: 0)
    report.expect(page.hoverVisible && !hovered.isEmpty && page.hoverText == hovered,
                  cppID: drawerVoiceDiagnosticsID,
                  message: "a repeated hover move keeps the hover text")
    page.refreshPlayhead(tick: 32, playing: true)
    report.expect(page.hoverVisible && page.hoverText == hovered, cppID: drawerVoiceDiagnosticsID,
                  message: "hover survives a playhead move inside one voice span")
    page.refreshPlayhead(tick: 60, playing: true)
    report.expect(!page.hoverVisible && page.hoverText.isEmpty, cppID: drawerVoiceDiagnosticsID,
                  message: "a playhead crossing the change boundary clears the hover context")
    _ = page.pointerMove(x: hoverX, y: 10, buttons: 0)
    let hoverBeforeStopping = page.hoverVisible
    page.refreshPlayhead(tick: 0, playing: false)
    report.expect(hoverBeforeStopping && !page.hoverVisible && page.hoverText.isEmpty,
                  cppID: drawerVoiceDiagnosticsID,
                  message: "a stopped playhead returning to an earlier span clears the hover")
    _ = page.pointerMove(x: hoverX, y: 10, buttons: 0)
    page.pointerLeave()
    report.expect(!page.hoverVisible, cppID: drawerVoiceDiagnosticsID,
                  message: "a pointer leave clears the hover")
    _ = page.pointerMove(x: hoverX, y: 10, buttons: 0)
    report.expect(page.handleEscape() && !page.hoverVisible, cppID: drawerVoiceDiagnosticsID,
                  message: "an escape clears the hover")

    let original = programs.map { fixture.session.bankSlots[$0].voice }
    guard original.allSatisfy({ $0 != nil }) else {
        report.fail(drawerVoiceLabelID, "the named bank slots have no parsed voices to edit")
        return
    }
    guard page.publishedMarkers.count == programs.count else {
        report.fail(drawerVoiceLabelID, "the named bank did not publish every fixture marker")
        return
    }
    let namedLabels = page.publishedMarkers.map(\.label)
    for (index, slot) in programs.enumerated() {
        guard var edited = original[index] else {
            report.fail(drawerVoiceLabelID, "the staged bank slot \(slot) has no parsed voice to edit")
            return
        }
        edited.symbol = ""
        let cleared = edited
        do {
            _ = try runBlocking {
                try await fixture.session.applyBankEdit(slot: slot, value: cleared, expected: original[index])
            }
        } catch {
            report.fail(drawerVoiceLabelID, "could not clear voice symbol through the bank: \(error)")
            return
        }
    }
    page.detach()
    page.attach(session: fixture.session, palette: GridPalette())
    report.expect(page.publishedMarkers.count == programs.count
                  && zip(page.publishedMarkers, programs).enumerated().allSatisfy { index, pair in
        pair.0.symbol.isEmpty && pair.0.label.hasPrefix(String(format: "%03d ", pair.1))
            && pair.0.label != namedLabels[index]
    }, cppID: drawerVoiceLabelID,
        message: "a bank without symbol names falls back to program-number labels")

    do {
        for _ in programs {
            _ = try runBlocking { try await fixture.session.undo() }
        }
    } catch {
        report.fail(drawerVoiceLabelID, "could not restore the bank symbols: \(error)")
        return
    }
    page.detach()
    page.attach(session: fixture.session, palette: GridPalette())
    report.expect(page.publishedMarkers.map(\.label) == namedLabels, cppID: drawerVoiceLabelID,
                  message: "restoring the bank restores the named labels")

    guard var renamed = fixture.session.bankSlots[programs[1]].voice else {
        report.fail(drawerVoiceLabelID, "the restored bank has no voice to rename")
        return
    }
    let beforeRename = renamed
    renamed.symbol = "renamed_voice_symbol"
    do {
        _ = try runBlocking {
            try await fixture.session.applyBankEdit(slot: programs[1], value: renamed,
                                                    expected: beforeRename)
        }
    } catch {
        report.fail(drawerVoiceLabelID, "could not rename the bank symbol: \(error)")
        return
    }
    page.detach()
    page.attach(session: fixture.session, palette: GridPalette())
    let renamedLabel = page.publishedMarkers.count > 1 ? page.publishedMarkers[1].label : nil
    report.expect(renamedLabel?.contains("renamed_voice_symbol") == true
                  && renamedLabel != namedLabels[1], cppID: drawerVoiceLabelID,
                  message: "a renamed voice symbol relabels the lane")
    drawerVoiceWorkspaceHideShow(report, fixture: fixture)
}

@MainActor
private func drawerVoiceWorkspaceHideShow(_ report: CheckReport,
                                          fixture: drawerVoiceVoiceChangesFixture) {
    let audio: NativeAudio
    do {
        audio = try NativeAudio()
    } catch {
        report.fail(drawerVoiceCancellationID, "section visibility cannot create audio: \(error)")
        return
    }
    let playhead = SharedPlayheadPresenter()
    let guides = PlayheadGuidesPresenter()
    let eventList = EventListPresenter()
    let workspace = DocumentWorkspace(
        session: fixture.session, audio: audio, playhead: playhead,
        playheadGuides: guides, eventList: eventList, palette: GridPalette(),
        typography: Typography(baseFontPx: 13), callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { _ in }, timeSignaturePromptInvalidated: { _, _ in }))
    defer {
        workspace.teardown()
        withExtendedLifetime((audio, playhead, guides, eventList)) {}
    }
    workspace.activate()
    let page = workspace.voiceChangesPage
    page.configureBody(width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    let drawer = workspace.drawer
    let section = DrawerSectionKind.voiceChanges.rawValue
    drawer.setSectionVisible(kind: section, visible: true, drawerOwnsFocus: false)
    _ = playhead.observe(sample: fixture.session.timeline.sample(for: 60),
                         transport: SharedPlayheadPolicy.playingTransport)
    _ = page.pointerMove(x: fixture.markerX(24), y: 10, buttons: 0)
    guard page.hoverVisible && page.presentedContextSlot == fixture.lanePoints()[1].value else {
        report.fail(drawerVoiceCancellationID, "the visible workspace did not arm its voice hover")
        return
    }
    drawer.setSectionVisible(kind: section, visible: false, drawerOwnsFocus: false)
    report.expect(!drawer.voiceChangesSection.visible && !page.hoverVisible && !page.interactionActive,
                  cppID: drawerVoiceCancellationID,
                  message: "hiding the section cancels the interaction and clears the hover")
    let hiddenBuilds = page.contentBuildCount
    _ = playhead.observe(sample: fixture.session.timeline.sample(for: 8),
                         transport: SharedPlayheadPolicy.playingTransport)
    drawer.setSectionVisible(kind: section, visible: true, drawerOwnsFocus: false)
    report.expect(drawer.voiceChangesSection.visible && page.contentBuildCount > hiddenBuilds
                  && page.markerTicks == [0, 48, 120], cppID: drawerVoiceCancellationID,
                  message: "re-showing the section re-derives the markers")
}

@MainActor
func drawerVoiceAuditionCapability(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    var calls: [[UInt8]] = []
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    let baseline = fixture.snapshot
    let first = UInt8(programs[0])
    let second = UInt8(programs[1])

    func hold(_ program: Int) {
        guard let row = page.pickerRowPrograms.firstIndex(of: program) else {
            report.fail(drawerVoiceAuditionID, "the audition program is absent from the picker")
            return
        }
        page.pressAndHoldPickerRow(index: row)
    }
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    hold(programs[0])
    hold(programs[1])
    page.releasePickerAudition()
    page.releasePickerAudition()
    report.expectEqual(expected: [[first, 60, 112], [first, 60, 0],
                        [first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "held program replacement releases once before the next note")

    calls.removeAll()
    hold(programs[0])
    page.setPickerFilter(text: "__no_voice_can_match__")
    report.expectEqual(expected: [[first, 60, 112], [first, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "filter invalidation releases the sounding program")
    page.cancelPicker()

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    _ = page.acceptPicker()
    report.expectEqual(expected: [[second, 60, 112], [second, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "same-value acceptance releases without a musical edit")
    report.expectEqual(expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceAuditionID,
                       what: "audition, filtering and same-value acceptance leave document/history unchanged")

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    page.onAuditionVoice = nil
    report.expectEqual(expected: [[first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "picker and callback replacement release through the old owner")
    report.expect(!page.auditionAvailable, cppID: drawerVoiceAuditionID,
                  message: "removing the real callback removes audition availability")

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    fixture.session.selectedTrack = 1
    page.releasePickerAudition()
    report.expectEqual(expected: [[first, 60, 112], [first, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "stale track cancellation releases without a duplicate note-off")
    fixture.session.selectedTrack = 0
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    calls.removeAll()
    hold(programs[1])
    page.cancelSectionInteraction()
    report.expectEqual(expected: [[second, 60, 112], [second, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "workspace cancellation releases its held voice")
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    page.detach()
    report.expectEqual(expected: [[first, 60, 112], [first, 60, 0]], actual: calls,
                       cppID: drawerVoiceAuditionID, what: "document teardown releases the final held program")
    report.expectEqual(expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceAuditionID,
                       what: "picker replacement and teardown write no musical state")
}
