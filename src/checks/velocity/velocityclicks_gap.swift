import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func drawerVelocityClickSetupGapPredicates(_ report: CheckReport,
                                           session: DocumentSession,
                                           service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let id = "velocity/velocityclicks.cpp"
    let maximumY = page.axisModel.velocityToY(127)
    let rulerX = min(max(1, page.rulerWidth / 2), max(1, page.rulerWidth - 1))
    report.expect(page.session === fixture.session, cppID: id, message: "A016")
    report.expect(page.axisModel.drawableSpan > 0, cppID: id, message: "A017")
    report.expect(page.rulerWidth > 0, cppID: id, message: "A018")
    report.expect(page.axisModel.yToVelocity(maximumY) == 127, cppID: id, message: "A020")
    report.expect(maximumY >= 0 && maximumY <= page.plotHeight && rulerX < page.rulerWidth,
                  cppID: id, message: "A021")
}
