import Foundation
import PorydawApp
import PorydawAppPresentation
import PorydawAppCommands
import PorydawCore
import PorydawCoreCheckNative
import PorydawDocument
import PorydawPlayback

// MARK: - Session Editor Semantics

@MainActor
internal func mouseHintOwnershipChecks(_ report: CheckReport) {
    let id = "swiftcore/MouseHints::sourceOwnership"
    let hints = MouseHints()
    let first = hints.allocateSourceToken()
    let second = hints.allocateSourceToken()
    hints.claim(sourceToken: first, profile: 15)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: id,
        what: "inactive windows reject hint claims")
    hints.setWindowActive(active: true)
    hints.claim(sourceToken: first, profile: 15)
    let nodeHint = hints.text
    hints.claim(sourceToken: second, profile: 15)
    hints.clear(sourceToken: first)
    report.expectEqual(
        expected: nodeHint, actual: hints.text, cppID: id,
        what: "replaced source cannot clear an identical-profile new owner")
    hints.claim(sourceToken: first, profile: 0)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: id,
        what: "empty profile replaces and clears prior visible hint")
    hints.clear(sourceToken: second)
    hints.claim(sourceToken: first, profile: 26)
    report.expect(
        hints.text != nodeHint, cppID: id,
        message: "replacing the node profile changes the presented instructions")
    hints.clear(sourceToken: first)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: id,
        what: "current source lifecycle clear removes hint")
    hints.claim(sourceToken: second, profile: 21)
    hints.setWindowActive(active: false)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: id,
        what: "window deactivation clears an owned hint")
    hints.setWindowActive(active: true)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: id,
        what: "reactivation never resurrects cached ownership")
    hints.claim(sourceToken: second, profile: 21)
    hints.claim(sourceToken: first, profile: -1)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: id,
        what: "unknown profile clears rather than retaining unrelated instructions")
    hints.claim(sourceToken: first, profile: 14)
    let headerHint = hints.text
    hints.claim(sourceToken: second, profile: 10)
    let rollHint = hints.text
    hints.clear(sourceToken: first)
    report.expect(
        !headerHint.isEmpty && !rollHint.isEmpty && headerHint != rollHint
            && hints.text == rollHint, cppID: id,
        message: "hidden header owner cannot clear the surviving roll profile")
    hints.claim(sourceToken: first, profile: 0)
    hints.claim(sourceToken: second, profile: 10)
    hints.clear(sourceToken: first)
    report.expectEqual(
        expected: rollHint, actual: hints.text, cppID: id,
        what: "released empty scrollbar owner cannot erase the roll release target")
    hints.claim(sourceToken: first, profile: 14)
    hints.clear(sourceToken: first)
    hints.claim(sourceToken: second, profile: 10)
    hints.clear(sourceToken: first)
    report.expectEqual(
        expected: rollHint, actual: hints.text, cppID: id,
        what: "destroyed tab owner cannot clear the newly claimed sibling hint")
    mouseHintScopeChecks(report)
}

@MainActor
internal func mouseHintScopeChecks(_ report: CheckReport) {
    let presenter = ShellPresenter()
    let hints = presenter.mouseHints
    hints.setWindowActive(active: true)
    let editor = hints.allocateSourceToken()
    let menu = hints.allocateSourceToken()
    let popup = hints.allocateSourceToken()
    hints.claim(sourceToken: editor, profile: 1)
    let renameHint = hints.text
    hints.claim(sourceToken: menu, profile: 0)
    let menuMuted = hints.text.isEmpty
    hints.clear(sourceToken: menu)
    hints.claim(sourceToken: editor, profile: 1)
    let renameRestored = hints.text == renameHint
    hints.claim(sourceToken: editor, profile: 14)
    let editorHint = hints.text
    report.expect(
        !renameHint.isEmpty && menuMuted && renameRestored
            && !editorHint.isEmpty && editorHint != renameHint,
        cppID: "swiftcore/mouseHintScopeChecks::menuScope",
        message: "an open menu keeps the rename hint and dismiss restores the editor hint")

    hints.claim(sourceToken: popup, profile: 0)
    let covered = hints.text.isEmpty
    hints.clear(sourceToken: popup)
    hints.claim(sourceToken: editor, profile: 14)
    report.expect(
        covered && hints.text == editorHint,
        cppID: "swiftcore/mouseHintScopeChecks::popupScope",
        message: "dismissing a popup restores the covered target hint")

    presenter.statusText = "Operational message"
    report.expect(
        presenter.mouseHints === presenter.session.mouseHintsPresenter()
            && hints.text == editorHint && presenter.statusText == "Operational message",
        cppID: "swiftcore/mouseHintScopeChecks::statusPresentation",
        message: "an operational status update preserves the presenter's current hint")
}

@MainActor
internal func editorSelectionCommandChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/ApplicationSession::selectionCommandRouting"
    let document = SongDocument(
        file: makeMidiFixture(), config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    let viewport = DocumentViewport(session: session)
    let grid = PianoGrid(viewport: viewport)
    let page = AutomationPage()
    page.attach(viewport: viewport, palette: GridPalette())
    defer { page.detach() }
    session.onChange = { [weak page] _ in page?.refreshFromDocument() }
    let ruler = RulerMenuPresenter(viewport: viewport, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    let lane = AutomationParameter.controlChange(track: 0, controller: TimeDefaults.ccPan)
    document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccPan), from: 0,
        through: TimeDefaults.noTick,
        points: [LaneWrite(tick: 24, value: 30), LaneWrite(tick: 72, value: 90)])
    guard let selectedNote = document.notes(in: 0).first else {
        report.fail(id, "fixture has no note to verify range precedence")
        return
    }
    session.addSelectedNote(selectedNote.id)
    page.selectRange(from: 24, to: 48, lanes: [lane])
    let revision = document.revision
    report.expect(
        router.isAvailable(.delete) && router.isAvailable(.copy)
            && router.isAvailable(.cut), cppID: id,
        message: "automation range owns semantic edit availability")
    report.expectEqual(
        expected: EditKeyDecision.execute.rawValue,
        actual: router.route(.delete, autoRepeat: true).rawValue,
        cppID: id, what: "range Delete retains canonical repeat execution")
    report.expectEqual(
        expected: revision, actual: document.revision, cppID: id,
        what: "availability and key arbitration never mutate the document")
    report.expectEqual(
        expected: EditKeyDecision.consume.rawValue,
        actual: router.route(.transposeUp, autoRepeat: false).rawValue,
        cppID: id, what: "lane-scoped transpose consumes without falling through to notes")
    router.perform(.transposeUp)
    report.expectEqual(
        expected: revision, actual: document.revision, cppID: id,
        what: "lane transpose does not mutate notes after the time selection clears note focus")
    router.perform(.delete)
    report.expectEqual(
        expected: [Tick(72)],
        actual: document.lanePoints(
            track: 0, lane: .controller(TimeDefaults.ccPan)
        ).map(\.tick),
        cppID: id, what: "range Delete removes only points in the selected interval")
    report.expect(
        document.note(selectedNote.id) != nil, cppID: id,
        message: "time selection deletion leaves notes outside the selected lane intact")
    let afterDelete = document.revision
    router.perform(.delete)
    report.expectEqual(
        expected: afterDelete, actual: document.revision, cppID: id,
        what: "empty selected range deletion never falls through to notes")
    report.expect(
        document.note(selectedNote.id) != nil, cppID: id,
        message: "empty range still owns the operation target")
    router.perform(.clearTimeSelection)
    report.expect(
        page.selection == nil, cppID: id,
        message: "canonical clear-selection command clears the automation range")
    session.addSelectedNote(selectedNote.id)
    report.expectEqual(
        expected: EditKeyDecision.execute.rawValue,
        actual: router.route(.delete, autoRepeat: false).rawValue,
        cppID: id, what: "reselecting the note makes it the target after range clear")
    router.perform(.delete)
    report.expect(
        document.note(selectedNote.id) == nil, cppID: id,
        message: "shared note deletion remains reachable after range clear")

    // Track-scoped ranges include notes, not just the plotted automation lane.
    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 48, endTick: 73), scope: .tracks([0])))
    router.perform(.delete)
    report.expect(
        !document.notes(in: 0).contains(where: { $0.tick == 48 })
            && document.lanePoints(track: 0, lane: .controller(TimeDefaults.ccPan)).isEmpty,
        cppID: id, message: "track range deletes both its notes and automation points")
    report.expect(
        document.notes(in: 0).contains(where: { $0.tick == 96 }), cppID: id,
        message: "track range leaves outside notes intact")

    page.clearTimeSelection()
    guard let remaining = document.notes(in: 0).first else {
        report.fail(id, "outside note required for pointer arbitration")
        return
    }
    session.addSelectedNote(remaining.id)
    grid.beginRightPointer(x: 0, y: 0)
    let beforeGestureCommand = document.revision
    report.expectEqual(
        expected: EditKeyDecision.consume.rawValue,
        actual: router.route(.delete, autoRepeat: false).rawValue,
        cppID: id, what: "a live pointer gesture consumes semantic deletion")
    router.perform(.delete)
    report.expectEqual(
        expected: beforeGestureCommand, actual: document.revision, cppID: id,
        what: "direct activation cannot bypass pointer gesture arbitration")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    checkPerTabScaleState(report, suite: suite, service: service)
    checkScaleDeleteUndoLeavesCleanDocument(report, suite: suite, service: service)
}

@MainActor
internal func arrowKeyTrackSelectionChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/ApplicationSession::arrowKeyTrackSelection"
    let document = SongDocument(
        file: makeMidiFixture(), config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    guard document.duplicateTrack(0) == 1, let note = document.notes(in: 0).first,
        let otherTrackNote = document.notes(in: 1).first
    else {
        report.fail(id, "fixture needs two tracks with notes")
        return
    }
    let viewport = DocumentViewport(session: session)
    let grid = PianoGrid(viewport: viewport)
    let page = AutomationPage()
    page.attach(viewport: viewport, palette: GridPalette())
    defer { page.detach() }
    let ruler = RulerMenuPresenter(viewport: viewport, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    // ShellPresenter.routeEditorKey's activation of each decision.
    func press(_ command: EditCommand, repeating: Bool = false) -> EditKeyDecision {
        let decision = router.route(command, autoRepeat: repeating)
        if decision == .execute { router.perform(command) }
        if decision == .selectAdjacentTrack { router.selectAdjacentTrack(command) }
        return decision
    }
    session.selectPrimaryTrack(0)

    report.expect(
        router.route(.transposeDown, autoRepeat: false) == .selectAdjacentTrack
            && session.selectedTrack == 0,
        cppID: id, message: "routing Down with nothing selected decides without moving")
    _ = press(.transposeDown)
    report.expect(
        session.selectedTrack == 1, cppID: id,
        message: "Down with nothing selected moves to the track below")
    _ = press(.transposeDown)
    report.expect(
        session.selectedTrack == 1, cppID: id, message: "Down on the last track stays there")
    _ = press(.transposeUp, repeating: true)
    report.expect(
        session.selectedTrack == 0, cppID: id, message: "a held Up moves to the track above")
    report.expect(
        press(.transposeDownOctave) == .consume && session.selectedTrack == 0, cppID: id,
        message: "Shift+Down with a track below never changes track")
    router.perform(.transposeDown)
    report.expect(
        session.selectedTrack == 0, cppID: id,
        message: "menu Transpose Down never changes track")

    session.setSelectedNotes([otherTrackNote.id])
    _ = press(.transposeDown)
    report.expect(
        session.selectedTrack == 1 && document.note(otherTrackNote.id)?.pitch == otherTrackNote.pitch,
        cppID: id, message: "notes selected only on another track still let Down change track")
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([note.id])
    report.expect(
        press(.transposeDown) == .execute && session.selectedTrack == 0
            && document.note(note.id)?.pitch == note.pitch - 1,
        cppID: id, message: "selected notes keep Down as transpose")
    session.setSelectedNotes([])
    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 0, endTick: 24), scope: .tracks([0])))
    report.expect(
        press(.transposeDown) == .execute && session.selectedTrack == 0
            && document.note(note.id)?.pitch == note.pitch - 2,
        cppID: id, message: "an active time range keeps Down as transpose")
    page.clearTimeSelection()
    grid.beginRightPointer(x: 0, y: 0)
    report.expect(
        press(.transposeDown) == .consume && session.selectedTrack == 0, cppID: id,
        message: "a live pointer gesture swallows Down without changing track")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
}

@MainActor
internal func overlapRefusalChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/ApplicationSession::overlapRefusal"
    let document = SongDocument(
        file: makeMidiFixture(), config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    guard let note = document.notes(in: 0).first, let end = note.endTick, note.duration > 1 else {
        report.fail(id, "fixture needs a sounding note on track 0")
        return
    }
    // Raw insertion bypasses the editor's overlap guard, like an imported file.
    document.insertRawEvent(
        chunk: note.chunk,
        event: .channel(tick: note.tick + 1, status: 0x90 | note.channel, data0: note.pitch, data1: 100))
    document.insertRawEvent(
        chunk: note.chunk,
        event: .channel(tick: Tick(end) + 1, status: 0x90 | note.channel, data0: note.pitch, data1: 0))
    let pair = document.notes(in: 0).filter { $0.pitch == note.pitch && $0.tick <= note.tick + 1 }
    guard pair.count == 2 else {
        report.fail(id, "fixture did not gain an overlapping same-pitch pair")
        return
    }
    let viewport = DocumentViewport(session: session)
    let grid = PianoGrid(viewport: viewport)
    let page = AutomationPage()
    page.attach(viewport: viewport, palette: GridPalette())
    defer { page.detach() }
    let ruler = RulerMenuPresenter(viewport: viewport, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    session.selectPrimaryTrack(0)
    session.setSelectedNotes(pair.map(\.id))
    let revision = document.revision
    let refusal = router.perform(.transposeUp)
    report.expect(
        refusal != nil && document.revision == revision, cppID: id,
        message: "transposing an overlapping same-pitch pair is refused with status text")
    report.expect(
        router.perform(.nudgeRight) != nil && document.revision == revision, cppID: id,
        message: "nudging the same pair reports the same refusal")
    session.setSelectedNotes([pair[0].id])
    report.expect(
        router.perform(.transposeUp) == nil && document.note(pair[0].id)?.pitch == note.pitch + 1,
        cppID: id, message: "one note of the pair still transposes without a refusal")
}

// Fork tabs_scale.cpp:149-151 stage track selection plus Highlight/Fold writes
// around deleteTrack(0)/undo; only the dirty flag below is otherwise unread.
@MainActor
private func checkScaleDeleteUndoLeavesCleanDocument(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/ApplicationSession::tabsScale"
    let document = SongDocument(
        file: makeMidiFixture(), config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    let viewport = DocumentViewport(session: session)
    viewport.setScale(highlight: true)
    viewport.setScale(fold: true)
    guard let extra = document.addTrack(voice: 0) else {
        report.fail(id, "could not add a track for the delete-undo clean-document read")
        return
    }
    session.selectPrimaryTrack(extra)
    session.selectPrimaryTrack(0)
    document.deleteTrack(0)
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the deleted track for the clean-document read")
        return
    }
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the added track for the clean-document read")
        return
    }
    report.expect(
        !document.isDirty, cppID: id,
        message: "deleting then undoing every track edit leaves the document clean")
    withExtendedLifetime(viewport) {}
}

@MainActor
private func checkPerTabScaleState(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/ApplicationSession::tabsScale"
    func makeViewport() -> DocumentViewport {
        let document = SongDocument(
            file: makeMidiFixture(), config: suite.document.state.config,
            source: suite.document.source, trackBudget: suite.document.trackBudget)
        return DocumentViewport(
            session: DocumentSession(
                document: document, service: service,
                lease: suite.bankLease, slots: suite.bankSlots,
                dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000))
    }
    let first = makeViewport()
    let second = makeViewport()
    func isDefault(_ viewport: DocumentViewport) -> Bool {
        let scale = viewport.scale
        return scale.root == 0 && scale.scale == .major && !scale.highlight && !scale.fold
    }
    report.expect(
        isDefault(first) && isDefault(second), cppID: id,
        message: "a fresh tab defaults to C major with Highlight and Fold off")
    let firstDocument = first.session.document
    let firstHistory = firstDocument.history.currentIdentity
    let secondHistory = second.session.document.history.currentIdentity
    first.setScale(root: 9)
    first.setScale(type: .dorian)
    first.setScale(highlight: true)
    first.setScale(fold: true)
    report.expect(
        isDefault(second) && first.scale.root == 9
            && first.scale.scale == .dorian && first.scale.highlight
            && first.scale.fold, cppID: id,
        message: "unselected tab retains defaults after scale edits")
    second.setScale(root: 4)
    second.setScale(type: .naturalMinor)
    second.setScale(highlight: false)
    second.setScale(fold: false)
    report.expect(
        first.scale.root == 9 && first.scale.fold
            && second.scale.root == 4 && second.scale.scale == .naturalMinor
            && firstDocument.history.currentIdentity == firstHistory
            && second.session.document.history.currentIdentity == secondHistory,
        cppID: id, message: "scale state stays with its tab")
    guard let additional = firstDocument.addTrack(voice: 0) else {
        report.fail(id, "could not add a track for tab-scale retention")
        return
    }
    first.session.selectPrimaryTrack(additional)
    first.session.selectPrimaryTrack(0)
    report.expect(
        first.scale.root == 9 && first.scale.scale == .dorian
            && first.scale.highlight && first.scale.fold,
        cppID: id, message: "track selection preserves per-tab scale state")
    firstDocument.deleteTrack(additional)
    report.expect(
        first.scale.root == 9 && first.scale.scale == .dorian
            && first.scale.highlight && first.scale.fold,
        cppID: id, message: "deleting a track preserves the tab's scale state")
    guard firstDocument.history.undoDocument() else {
        report.fail(id, "could not undo the tab's deleted track")
        return
    }
    report.expect(
        firstDocument.engineTracks.usedTrackCount > additional
            && first.scale.root == 9 && first.scale.scale == .dorian
            && first.scale.highlight && first.scale.fold,
        cppID: id, message: "undo restores scale state across a deleted track")
}
