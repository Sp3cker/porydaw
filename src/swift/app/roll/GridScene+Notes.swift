import Foundation
import PorydawCore
import PorydawDocument
import QtBridge

@MainActor
extension GridScene {
    /// Retains document content independently of selected-track presentation.
    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        RollDrawingContent.updatePalette(input, into: &plotPalette)
        let colors = plotPalette
        let key = RollDrawingContent.key(input, palette: colors)
        if key != listContentKey {
            listContentKey = key
            contentGeneration += 1
        }
        rebuildRollLists(input, colors: colors)
    }

    @QtIgnored
    private func rebuildRollLists(_ input: GridSceneInput, colors: [UInt32]) {
        let snapshot = input.camera.snapshot
        let band = input.bandSelection.map {
            RollBandSignature(x: $0.x, y: $0.y, w: $0.w, h: $0.h)
        }
        let frame = RollDisplayFrameKey(
            generation: contentGeneration, camera: snapshot,
            dpr: input.metrics.dpr, band: band)
        if displayLists.count != 3 {
            displayLists = [Data(), retainedEmptyDisplayList(), retainedEmptyDisplayList()]
        }
        var changed = false
        if frame != displayFrameKey {
            let built = plotBuilder.build(
                input, palette: colors,
                width: snapshot.viewportWidth, height: snapshot.rollHeight,
                into: &displayLists[0])
            displayFrameKey = frame
            noteRecordCount = built.count
            changed = built.changed
        }
        if keyboardBuilder.build(
            input, palette: colors,
            width: input.metrics.keyboardWidth + snapshot.viewportWidth, height: snapshot.rollHeight,
            into: &displayLists[1])
        {
            changed = true
        }
        if rulerBuilder.build(
            input, palette: colors, width: snapshot.viewportWidth, height: input.rulerHeight,
            into: &displayLists[2])
        {
            changed = true
        }
        if changed { displayRevision += 1 }
    }

}
