import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Session Editor Semantics

@MainActor
internal func mouseHintOwnershipChecks(_ report: CheckReport) {
    let id = "swiftcore/MouseHints::sourceOwnership"
    let hints = MouseHints()
    let first = hints.allocateSourceToken()
    let second = hints.allocateSourceToken()
    hints.claim(sourceToken: first, profile: 15)
    report.expectEqual(expected: "", actual: hints.text, cppID: id,
                       what: "inactive windows reject hint claims")
    hints.setWindowActive(active: true)
    hints.claim(sourceToken: first, profile: 15)
    let nodeHint = hints.text
    hints.claim(sourceToken: second, profile: 15)
    hints.clear(sourceToken: first)
    report.expectEqual(expected: nodeHint, actual: hints.text, cppID: id,
                       what: "replaced source cannot clear an identical-profile new owner")
    hints.claim(sourceToken: first, profile: 0)
    report.expectEqual(expected: "", actual: hints.text, cppID: id,
                       what: "empty profile replaces and clears prior visible hint")
    hints.clear(sourceToken: second)
    hints.claim(sourceToken: first, profile: 26)
    report.expect(hints.text != nodeHint, cppID: id,
                  message: "replacing the node profile changes the presented instructions")
    hints.clear(sourceToken: first)
    report.expectEqual(expected: "", actual: hints.text, cppID: id,
                       what: "current source lifecycle clear removes hint")
    hints.claim(sourceToken: second, profile: 21)
    hints.setWindowActive(active: false)
    report.expectEqual(expected: "", actual: hints.text, cppID: id,
                       what: "window deactivation clears an owned hint")
    hints.setWindowActive(active: true)
    report.expectEqual(expected: "", actual: hints.text, cppID: id,
                       what: "reactivation never resurrects cached ownership")
    hints.claim(sourceToken: second, profile: 21)
    hints.claim(sourceToken: first, profile: -1)
    report.expectEqual(expected: "", actual: hints.text, cppID: id,
                       what: "unknown profile clears rather than retaining unrelated instructions")
}

@MainActor
internal func editorSelectionCommandChecks(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "swiftcore/ApplicationSession::selectionCommandRouting"
    let document = SongDocument(file: makeMidiFixture(), config: suite.document.state.config,
                                source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    let grid = PianoGrid(session: session)
    let page = AutomationPage()
    page.attach(session: session, palette: GridPalette())
    defer { page.detach() }
    session.onChange = { [weak page] _ in page?.refreshFromDocument() }
    let router = EditorCommandRouter(session: session, grid: grid, automation: page)
    let lane = AutomationParameter.controlChange(track: 0, controller: TimeDefaults.ccPan)
    document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 0,
                       through: TimeDefaults.noTick,
                       points: [LaneWrite(tick: 24, value: 30), LaneWrite(tick: 72, value: 90)])
    guard let selectedNote = document.notes(in: 0).first else {
        report.fail(id, "fixture has no note to verify range precedence")
        return
    }
    session.addSelectedNote(selectedNote.id)
    page.selectRange(from: 24, to: 48, lanes: [lane])
    let revision = document.revision
    report.expect(router.isAvailable(.delete) && router.isAvailable(.copy)
                  && router.isAvailable(.cut), cppID: id,
                  message: "automation range owns semantic edit availability")
    report.expectEqual(expected: EditKeyDecision.execute.rawValue,
                       actual: router.route(.delete, autoRepeat: true).rawValue,
                       cppID: id, what: "range Delete retains canonical repeat execution")
    report.expectEqual(expected: revision, actual: document.revision, cppID: id,
                       what: "availability and key arbitration never mutate the document")
    report.expectEqual(expected: EditKeyDecision.consume.rawValue,
                       actual: router.route(.transposeUp, autoRepeat: false).rawValue,
                       cppID: id, what: "lane-scoped transpose consumes without falling through to notes")
    router.perform(.transposeUp)
    report.expectEqual(expected: revision, actual: document.revision, cppID: id,
                       what: "lane transpose does not mutate notes after the time selection clears note focus")
    router.perform(.delete)
    report.expectEqual(expected: [Tick(72)], actual: document.lanePoints(
        track: 0, lane: .controller(TimeDefaults.ccPan)).map(\.tick),
        cppID: id, what: "range Delete removes only points in the selected interval")
    report.expect(document.note(selectedNote.id) != nil, cppID: id,
                  message: "time selection deletion leaves notes outside the selected lane intact")
    let afterDelete = document.revision
    router.perform(.delete)
    report.expectEqual(expected: afterDelete, actual: document.revision, cppID: id,
                       what: "empty selected range deletion never falls through to notes")
    report.expect(document.note(selectedNote.id) != nil, cppID: id,
                  message: "empty range still owns the operation target")
    router.perform(.clearTimeSelection)
    report.expect(page.selection == nil, cppID: id,
                  message: "canonical clear-selection command clears the automation range")
    session.addSelectedNote(selectedNote.id)
    report.expectEqual(expected: EditKeyDecision.execute.rawValue,
                       actual: router.route(.delete, autoRepeat: false).rawValue,
                       cppID: id, what: "reselecting the note makes it the target after range clear")
    router.perform(.delete)
    report.expect(document.note(selectedNote.id) == nil, cppID: id,
                  message: "shared note deletion remains reachable after range clear")

    // Track-scoped ranges include notes, not just the plotted automation lane.
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 48, endTick: 73), scope: .tracks([0])))
    router.perform(.delete)
    report.expect(!document.notes(in: 0).contains(where: { $0.tick == 48 })
                  && document.lanePoints(track: 0, lane: .controller(TimeDefaults.ccPan)).isEmpty,
                  cppID: id, message: "track range deletes both its notes and automation points")
    report.expect(document.notes(in: 0).contains(where: { $0.tick == 96 }), cppID: id,
                  message: "track range leaves outside notes intact")

    page.clearTimeSelection()
    guard let remaining = document.notes(in: 0).first else {
        report.fail(id, "outside note required for pointer arbitration")
        return
    }
    session.addSelectedNote(remaining.id)
    grid.beginRightPointer(x: 0, y: 0)
    let beforeGestureCommand = document.revision
    report.expectEqual(expected: EditKeyDecision.consume.rawValue,
                       actual: router.route(.delete, autoRepeat: false).rawValue,
                       cppID: id, what: "a live pointer gesture consumes semantic deletion")
    router.perform(.delete)
    report.expectEqual(expected: beforeGestureCommand, actual: document.revision, cppID: id,
                       what: "direct activation cannot bypass pointer gesture arbitration")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
}
