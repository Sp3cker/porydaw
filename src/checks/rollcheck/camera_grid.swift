import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

/// Shared 640x320 @2x viewport, scroll reset, and time zoom used by rollcheck
/// suites. Consolidates the repeated PianoGrid camera-setup blocks.
@MainActor
func makeCameraGrid(session: DocumentSession, zoom: Double = 35) -> PianoGrid {
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(zoom) }
    grid.refreshCamera()
    return grid
}

@MainActor
func firstRect(named name: String, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == name {
        return model[index]
    }
    return nil
}
