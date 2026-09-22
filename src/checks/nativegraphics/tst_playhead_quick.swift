import Foundation
import PorydawApp
import PorydawCore

@MainActor
func checkPublicationAndReprojection(_ report: CheckReport, session: DocumentSession,
                                            presenter: SharedPlayheadPresenter) {
    _ = session.mutateCamera { _ = $0.setHScroll(0) }
    let sample = session.timeline.sample(for: 48)
    report.expect(presenter.observe(sample: sample, transport: 0), cppID: sharedPlayheadPublicationID,
                  message: "a changed observation publishes")
    let count = presenter.presentationCount
    let width = session.camera.snapshot.viewportWidth
    report.expect(gridCameraNear(presenter.tick, 48, tolerance: 0.5) && presenter.timelineAttached
                      && presenter.playing == false,
                  cppID: sharedPlayheadPublicationID,
                  message: "the published tick is the authoritative sample's timeline position")
    report.expect(gridCameraNear(presenter.contentX, session.camera.contentX(tick: presenter.tick)),
                  cppID: sharedPlayheadPublicationID,
                  message: "the published projection is the session camera's contentX")
    report.expect(presenter.visible == (presenter.contentX >= 0 && presenter.contentX < width),
                  cppID: sharedPlayheadPublicationID,
                  message: "published visibility follows the projected position and viewport")
    report.expect(presenter.observe(sample: sample, transport: 0) == false
                      && presenter.presentationCount == count,
                  cppID: sharedPlayheadPublicationID,
                  message: "a repeated identical observation publishes nothing")
    presenter.refreshProjection()
    report.expect(presenter.presentationCount == count, cppID: sharedPlayheadPublicationID,
                  message: "reprojecting an unchanged camera publishes nothing")

    let tick = presenter.tick
    _ = session.mutateCamera { _ = $0.setHScroll(24) }
    report.expect(gridCameraNear(presenter.tick, tick), cppID: sharedPlayheadReprojectionID,
                  message: "a camera publication keeps the authoritative tick")
    report.expect(gridCameraNear(presenter.contentX, session.camera.contentX(tick: tick)), cppID: sharedPlayheadReprojectionID,
                  message: "a camera publication reprojects through the new camera")
    report.expect(presenter.presentationCount == count + 1, cppID: sharedPlayheadReprojectionID,
                  message: "one camera publication presents exactly once")
    _ = session.mutateCamera { _ = $0.setHScroll(1_000_000) }
    report.expect(!presenter.visible && presenter.contentX < 0, cppID: sharedPlayheadReprojectionID,
                  message: "a camera scrolled past the position hides the segment")
    _ = session.mutateCamera { _ = $0.setHScroll(0) }
    report.expect(presenter.visible && gridCameraNear(presenter.tick, tick)
                      && gridCameraNear(presenter.contentX, session.camera.contentX(tick: tick)),
                  cppID: sharedPlayheadReprojectionID,
                  message: "scrolling back re-renders the same retained position")
}
