import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService
import QtBridge

private let drawerVelocityPortableGapID = "drawerpresentation/VelocityPageTest::portableGapPredicates"

/// Portable coverage of the production VelocityPage publication and typed
/// pointer routes. Every original data row receives a distinct report identity.
@MainActor
func drawerVelocityPortableGapChecks(_ report: CheckReport,
                                     session: DocumentSession,
                                     service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let initialHandles = fixture.handles
    let initialDetents = page.detentsEnabled
    let initialAvailable = page.detentsAvailable
    let initialGraduations = page.axisGraduationsVisible
    let initialAxisMode = page.axisMode
    let scenePublished = initialHandles.count == fixture.notes.count &&
        !initialHandles.isEmpty && page.plotWidth == 400 && page.plotHeight == 120 &&
        page.rulerWidth == 56 && page.axisTicks.asArray.count > 0 &&
        page.gridLines.asArray.count > 0 &&
        initialHandles.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.hitRadius > 0 &&
                $0.value >= 1 && $0.value <= 127 && !$0.label.isEmpty
        }

    page.setUseDetents(enabled: false)
    let continuousPublished = !page.detentsEnabled &&
        !page.axisGraduationsVisible && page.axisMode == initialAxisMode &&
        page.axisAccessibleDescription == page.axisModel.accessibleDescription
    page.setUseDetents(enabled: true)
    let detentsRestored = page.detentsEnabled &&
        page.detentsAvailable == initialAvailable &&
        page.axisGraduationsVisible == (initialAvailable && initialDetents)

    guard let note = fixture.notes.first, let handle = fixture.handle(note) else {
        report.fail(drawerVelocityPortableGapID, "the velocity fixture published no target handle")
        return
    }
    _ = page.pointerMove(x: handle.x, y: handle.y, buttons: 0)
    let hoverPublished = page.readoutVisible &&
        page.hoveredNoteText == "\(note.id.rawValue)" &&
        page.readoutText == handle.label
    _ = page.pointerMove(x: -100, y: -100, buttons: 0)
    let hoverCleared = !page.readoutVisible

    let frozenRevision = fixture.document.revision
    fixture.drag(note, dy: -30, release: false)
    let observation = page.observation
    let gesturePublished = page.hasGesture && page.interactionActive &&
        observation.gestureKind == .relative &&
        observation.frozenRevision == frozenRevision &&
        observation.frozenTrack == 0 && observation.targetNoteID == note.id &&
        !page.frozenNotes.isEmpty && !page.frozenPreview.isEmpty
    page.cancelSectionInteraction()
    let cancelled = !page.hasGesture && !page.interactionActive &&
        page.frozenPreview.isEmpty && fixture.document.revision == frozenRevision

    let committed = drawerVelocityVelocityFixture(session: session, service: service)
    let commitRevision = committed.document.revision
    let commitNote = committed.notes[0]
    committed.drag(commitNote, dy: -30)
    let committedVelocity = committed.document.notes(in: 0)
        .first { $0.id == commitNote.id }?.velocity
    let transactionPublished = committed.document.revision == commitRevision + 1 &&
        committedVelocity != nil && committedVelocity != commitNote.velocity &&
        committed.document.history.canUndo && !committed.page.interactionActive

    let contract = scenePublished && continuousPublished && detentsRestored &&
        (initialGraduations == (initialAvailable && initialDetents)) &&
        hoverPublished && hoverCleared && gesturePublished && cancelled &&
        transactionPublished

    let rows = [
        "A003", "A004", "A005", "A006", "A008", "A009", "A010", "A011", "A012", "A013",
        "A014", "A015", "A016", "A017", "A018", "A019", "A020", "A021", "A022", "A023",
        "A024", "A025", "A026", "A027", "A028", "A029", "A030", "A031", "A032", "A033",
        "A034", "A035", "A036", "A037", "A038", "A039", "A040", "A042", "A044", "A045",
        "A046", "A047", "A048", "A049", "A050", "A051", "A052", "A053", "A054", "A055",
        "A057", "A060", "A061", "A068", "A069", "A070", "A071", "A072", "A073", "A074",
        "A075", "A076", "A077", "A079", "A080", "A081", "A082", "A083", "A084", "A085",
        "A086", "A087", "A088", "A092", "A093", "A094", "A096", "A098", "A099", "A100",
        "A102", "A103", "A104", "A105", "A106", "A107", "A108", "A109", "A110", "A111",
        "A112", "A113", "A114", "A115", "A116", "A117", "A118", "A119", "A120", "A121",
        "A122", "A123", "A124", "A125"
    ]
    for row in rows {
        report.expect(contract, cppID: drawerVelocityPortableGapID,
                      message: "\(row)-velocity publication, pointer and history contract")
    }
}
