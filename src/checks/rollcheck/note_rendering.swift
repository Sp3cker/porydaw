import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument
import QtBridge

@MainActor
public func runNoteRenderingChecks(_ report: CheckReport, viewport: DocumentViewport) {
    checkNoteBorders(report, viewport: viewport)
    checkIdentityNoteColors(report, viewport: viewport)
    checkNoteNameMode(report, viewport: viewport)
    checkVelocityValues(report, viewport: viewport)
    checkGhostNotes(report, viewport: viewport)
    checkProjectionEconomy(report, viewport: viewport)
    checkRollPlotCullBound(report, viewport: viewport)
    checkRulerSweepSingleTrackScope(report, viewport: viewport)
    checkRollPreviewInvalidation(report, viewport: viewport)
}
