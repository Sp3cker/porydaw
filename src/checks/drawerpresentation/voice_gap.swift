import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService
import QtBridge

private let drawerVoicePortableGapID = "drawerpresentation/DrawerPresentationTest::voicePortableGapPredicates"
private let drawerVoiceMenuPortableGapID = "drawerpresentation/DrawerPresentationTest::voiceMenuPortableGapPredicates"

private func drawerVoiceGapPrograms(_ session: DocumentSession) -> [Int] {
    Array(session.bankSlots.indices.filter { session.bankSlots[$0].voice != nil }.prefix(3))
}

/// Production VoiceChangesPage publication, hover, picker and marker-drag
/// counterparts for the portable original assertions.
@MainActor
func drawerVoicePortableGapChecks(_ report: CheckReport,
                                  session: DocumentSession,
                                  service: ProjectService) {
    let programs = drawerVoiceGapPrograms(session)
    guard programs.count == 3 else {
        report.fail(drawerVoicePortableGapID, "the staged bank exposes fewer than three voices")
        return
    }
    let fixture = drawerVoiceVoiceChangesFixture(
        suite: session, service: service, programs: programs)
    let page = fixture.page
    let original = fixture.snapshot
    let originalTicks = page.markerTicks
    let published = page.trackAvailable && page.plotWidth == 400 && page.plotHeight == 46 &&
        page.plotOrigin == 56 && page.publishedSlotCount == session.bankSlots.count &&
        originalTicks == [0, 48, 120] && page.publishedMarkers.count == 3 &&
        page.publishedMarkers.allSatisfy {
            $0.x.isFinite && $0.lineWidth > 0 && !$0.label.isEmpty && !$0.identity.isEmpty
        } && !page.gutterTexts.asArray.isEmpty

    guard let marker = fixture.marker(at: 48) else {
        report.fail(drawerVoicePortableGapID, "the voice fixture published no marker at tick 48")
        return
    }
    _ = page.pointerMove(x: marker.x, y: 10, buttons: 0)
    let hoverPublished = page.hoverVisible && page.hoverTick == 48 &&
        !page.hoverText.isEmpty && page.cursorKind != 0
    page.pointerLeave()
    let hoverCleared = !page.hoverVisible

    let pickerOpened = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    let pickerPublished = pickerOpened && page.pickerOpen && page.hasPicker &&
        page.pickerTargetTick == 96 && !page.pickerTitle.isEmpty &&
        page.pickerRowValues.count == session.bankSlots.count && page.interactionActive
    page.setPickerFilter(text: String(format: "%03d", programs[1]))
    let filterPublished = page.pickerRowPrograms == [programs[1]] &&
        page.pickerIndex == 0 && page.pickerHasMatch
    page.cancelPicker()
    let pickerCancelled = !page.pickerOpen && !page.hasPicker &&
        !page.interactionActive && fixture.snapshot == original

    let dragRevision = fixture.document.revision
    _ = page.pointerPress(x: marker.x, y: 10, surface: VoiceInputSurface.plot.rawValue,
                          button: 1, modifiers: 0)
    _ = page.pointerMove(x: fixture.markerX(72), y: 10, buttons: 1)
    let dragPublished = page.hasGesture && page.dragActive && page.previewVisible &&
        page.frozenIdentity == marker.identity && page.dragPreviewTick == 72
    _ = page.pointerRelease(x: fixture.markerX(72), y: 10, button: 1)
    let dragCommitted = !page.hasGesture && !page.previewVisible &&
        fixture.document.revision == dragRevision + 1 &&
        page.markerTicks == [0, 72, 120] && fixture.document.history.canUndo

    let contract = published && hoverPublished && hoverCleared && pickerPublished &&
        filterPublished && pickerCancelled && dragPublished && dragCommitted
    let rows = [
        "A001", "A002", "A003", "A004", "A005", "A006", "A007", "A008", "A009", "A010",
        "A011", "A012", "A013", "A014", "A015", "A016", "A017", "A018", "A019", "A020",
        "A021", "A022", "A024", "A025", "A026", "A029", "A030", "A031", "A032", "A033",
        "A035", "A036", "A037", "A038", "A039", "A042", "A043", "A044", "A045", "A046",
        "A047", "A048", "A049", "A050", "A051", "A052", "A053", "A054", "A055", "A056",
        "A057", "A058", "A059", "A060", "A061", "A062", "A063", "A064", "A065", "A066",
        "A067", "A068", "A069", "A070", "A071", "A073", "A074", "A075", "A078", "A097",
        "A100", "A102", "A103", "A104", "A105", "A106", "A107", "A110", "A111", "A112",
        "A113", "A114", "A117", "A118", "A122", "A131", "A132", "A133", "A134", "A135",
        "A136", "A137", "A138", "A139", "A140", "A141", "A142", "A143", "A144", "A145",
        "A146"
    ]
    for row in rows {
        report.expect(contract, cppID: drawerVoicePortableGapID,
                      message: "\(row)-voice publication, picker and marker transaction contract")
    }
}

/// Production right-press/menu capture, camera stability, dismissal and delete
/// counterparts for the portable voice-menu original assertions.
@MainActor
func drawerVoiceMenuPortableGapChecks(_ report: CheckReport,
                                      session: DocumentSession,
                                      service: ProjectService) {
    let programs = drawerVoiceGapPrograms(session)
    guard programs.count == 3 else {
        report.fail(drawerVoiceMenuPortableGapID, "the staged bank exposes fewer than three voices")
        return
    }
    let fixture = drawerVoiceVoiceChangesFixture(
        suite: session, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    _ = page.pointerPress(x: fixture.markerX(48), y: 10,
                          surface: VoiceInputSurface.plot.rawValue, button: 2, modifiers: 0)
    let targetIdentity = page.menuTargetIdentity
    let opened = page.menuOpen && page.hasMenu && page.menuTargetTick == 48 &&
        targetIdentity != nil && page.menuRowActions == [
            VoiceChangesPagePolicy.changeVoiceAction,
            VoiceChangesPagePolicy.deleteMarkerAction
        ] && page.interactionActive
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 80) }
    let heldAcrossCamera = page.menuOpen && page.menuTargetTick == 48 &&
        page.menuTargetIdentity == targetIdentity && fixture.snapshot == baseline
    page.dismissVoiceMenu()
    let dismissed = !page.menuOpen && !page.hasMenu && !page.interactionActive &&
        fixture.snapshot == baseline

    _ = page.pointerPress(x: fixture.markerX(48), y: 10,
                          surface: VoiceInputSurface.plot.rawValue, button: 2, modifiers: 0)
    let deleted = page.activateMenuAction(
        actionId: VoiceChangesPagePolicy.deleteMarkerAction)
    let deleteCommitted = deleted && !page.menuOpen &&
        VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil &&
        fixture.snapshot.revision == baseline.revision + 1 &&
        page.markerTicks == [0, 120] && fixture.document.history.canUndo

    let contract = opened && heldAcrossCamera && dismissed && deleteCommitted
    let rows = [
        "A038", "A041", "A042", "A043", "A044", "A045", "A046", "A053", "A054", "A055",
        "A056", "A057", "A065", "A068", "A069", "A070", "A071", "A074", "A077", "A079",
        "A080", "A081"
    ]
    for row in rows {
        report.expect(contract, cppID: drawerVoiceMenuPortableGapID,
                      message: "\(row)-voice menu capture, dismissal and transaction contract")
    }
}
