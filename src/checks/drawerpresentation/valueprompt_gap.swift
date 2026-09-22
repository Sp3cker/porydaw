import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let drawerValuePromptGapID = "drawerpresentation/DrawerPresentationTest::valuePromptPortableGaps"

/// Exercises the production AutomationPage prompt seam for centered-controller
/// insertion/replacement, numeric validation, cancellation, history and tempo.
@MainActor
func drawerValuePromptPortableGapChecks(_ report: CheckReport,
                                        session: DocumentSession,
                                        service: ProjectService) {
    let centered = drawerAutomationAutomationFixture(
        suite: session, service: service, pan: [(24, 64)])
    centered.activate(centered.panLane)
    let beforeCentered = centered.snapshot
    let openedCentered = centered.page.openPrompt(tick: 24, value: 64)
    let centeredPublication = centered.page.promptOpen &&
        centered.page.promptMinimum == -64 && centered.page.promptMaximum == 63 &&
        centered.page.promptDraft == "0"
    let committedCentered = centered.page.acceptPrompt(displayedValue: 5)
    let centeredWrite = centered.values(centered.panLane) == ["24:69"] &&
        centered.snapshot.revision == beforeCentered.revision + 1 &&
        centered.document.history.canUndo
    let centeredUndo = centered.document.history.undoDocument()
    let centeredRestored = centered.values(centered.panLane) == ["24:64"] &&
        centered.snapshot.identity == beforeCentered.identity

    let insertion = drawerAutomationAutomationFixture(
        suite: session, service: service, pan: [(24, 64)])
    insertion.activate(insertion.panLane)
    let insertionBefore = insertion.snapshot
    let openedInsertion = insertion.page.openPrompt(tick: 48, value: 64)
    insertion.page.updatePromptDraft(draft: "-5")
    let insertionDrafted = insertion.page.promptDraft == "-5" &&
        insertion.page.promptError.isEmpty && insertion.snapshot == insertionBefore
    let committedInsertion = insertion.page.acceptPromptDraft()
    let inserted = insertion.values(insertion.panLane) == ["24:64", "48:59"] &&
        insertion.snapshot.revision == insertionBefore.revision + 1

    let cancellation = drawerAutomationAutomationFixture(
        suite: session, service: service, pan: [(24, 64)])
    cancellation.activate(cancellation.panLane)
    let cancellationBefore = cancellation.snapshot
    let openedCancellation = cancellation.page.openPrompt(tick: 48, value: 64)
    cancellation.page.updatePromptDraft(draft: "999")
    let validationVisible = cancellation.page.promptOpen &&
        !cancellation.page.promptError.isEmpty
    cancellation.page.cancelPrompt()
    let cancelled = !cancellation.page.promptOpen &&
        cancellation.snapshot == cancellationBefore &&
        !cancellation.page.acceptPrompt(displayedValue: 12)

    let tempo = drawerAutomationAutomationFixture(
        suite: session, service: service, tempo: [(0, 500_000)])
    tempo.activate(.tempo)
    let tempoBefore = tempo.snapshot
    let openedTempo = tempo.page.openPrompt(tick: 0, value: 120)
    let tempoPublication = tempo.page.promptOpen &&
        tempo.page.promptMinimum == 20 && tempo.page.promptMaximum == 400 &&
        tempo.page.promptDraft == "120"
    let committedTempo = tempo.page.acceptPrompt(displayedValue: 90)
    let tempoWrite = tempo.tempoValues == ["0:90"] &&
        tempo.snapshot.revision == tempoBefore.revision + 1

    let panMetadata = AutomationParameterMetadata(parameter: centered.panLane)
    let panPrompt = panMetadata.prompt(storedValue: 64)
    let tempoPrompt = AutomationParameterMetadata(parameter: .tempo).prompt(storedValue: 120)
    let contract = openedCentered && centeredPublication && committedCentered &&
        centeredWrite && centeredUndo && centeredRestored &&
        openedInsertion && insertionDrafted && committedInsertion && inserted &&
        openedCancellation && validationVisible && cancelled &&
        openedTempo && tempoPublication && committedTempo && tempoWrite &&
        panPrompt.initialValue == 0 && panPrompt.minimum == -64 &&
        panPrompt.maximum == 63 && panMetadata.storedValue(prompted: -64) == 0 &&
        panMetadata.storedValue(prompted: 63) == 127 &&
        tempoPrompt.initialValue == 120 && tempoPrompt.minimum == 20 &&
        tempoPrompt.maximum == 400

    let rows = [
        "A017", "A018", "A019", "A024", "A028", "A029", "A030", "A035", "A042", "A043",
        "A044", "A045", "A049", "A050", "A054", "A055", "A056", "A057", "A063", "A073",
        "A080", "A081", "A082", "A083", "A084", "A085", "A086", "A096"
    ]
    for row in rows {
        report.expect(contract, cppID: drawerValuePromptGapID,
                      message: "\(row)-typed prompt publication and document transaction contract")
    }
}
