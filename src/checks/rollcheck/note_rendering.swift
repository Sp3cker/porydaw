import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func runNoteRenderingChecks(_ report: CheckReport, session: DocumentSession) {
    checkNoteBorders(report, session: session)
    checkIdentityNoteColors(report, session: session)
    checkNoteNameMode(report, session: session)
    checkVelocityValues(report, session: session)
    checkGhostNotes(report, session: session)
    checkProjectionEconomy(report, session: session)
    checkRulerSweepSingleTrackScope(report, session: session)
}
