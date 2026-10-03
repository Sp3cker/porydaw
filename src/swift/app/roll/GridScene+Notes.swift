import Foundation
import PorydawCore
import QtBridge

@MainActor
extension GridScene {
    /// Content seam: resolves palette/colors and records once per content
    /// key, then builds the frame.
    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        let colors = resolvePalette(input)
        let key = RollDrawingContent.key(input, palette: colors)
        if noteRecordsKey != key.notesSection {
            noteRecordsMaxDuration = RollDrawingContent.resolveNotes(input, into: &noteRecords)
            noteRecordsKey = key.notesSection
            builtProjection = input.camera.projection
            contentGeneration += 1
        }
        if key != listContentKey {
            listContentKey = key
            contentGeneration += 1
        }
        rebuildRollLists(input, colors: colors)
    }

    /// Camera-only seam: O(visible), no content-key scan. Cold start with
    /// no resolved records falls back to the content seam.
    @QtIgnored
    func rebuildDisplayLists(_ input: GridSceneInput) {
        guard noteRecordsKey != nil else {
            rebuildNotes(input)
            return
        }
        let colors = resolvePalette(input)
        rebuildRollLists(input, colors: colors)
    }

    /// True when the cached records were resolved against this projection.
    /// Fixed-size compare; never scans notes.
    @QtIgnored
    func projectionCovers(_ projection: PitchProjection) -> Bool {
        builtProjection == projection
    }

    @QtIgnored
    private func rebuildRollLists(_ input: GridSceneInput, colors: [UInt32]) {
        let snapshot = input.camera.snapshot
        let band = input.bandSelection.map {
            RollBandSignature(x: $0.x, y: $0.y, w: $0.w, h: $0.h)
        }
        let frame = RollDisplayFrameKey(
            generation: contentGeneration, camera: snapshot,
            dpr: input.metrics.dpr, band: band, hoverKey: input.hoverKey,
            rulerHeight: input.rulerHeight)
        if frame == displayFrameKey { return }
        if displayLists.count != 3 {
            displayLists = [Data(), retainedEmptyDisplayList(), retainedEmptyDisplayList()]
        }
        // Release the previous buffers before the retained writers reuse
        // their own: otherwise finish()'s shared output copies on write.
        displayLists[0] = Data()
        displayLists[1] = Data()
        displayLists[2] = Data()
        let built = plotBuilder.build(
            input, records: noteRecords, palette: colors,
            maxDuration: noteRecordsMaxDuration,
            width: snapshot.viewportWidth, height: snapshot.rollHeight)
        displayLists[0] = built.data
        // The keyboard list fills the full-width band beside the headers and
        // clips to it, so overflowing drum labels paint past the edge.
        displayLists[1] = keyboardBuilder.build(
            input, palette: colors,
            width: input.metrics.keyboardWidth + snapshot.viewportWidth,
            height: snapshot.rollHeight)
        displayLists[2] = rulerBuilder.build(
            input, palette: colors,
            width: snapshot.viewportWidth, height: input.rulerHeight)
        displayFrameKey = frame
        noteRecordCount = built.count
        displayRevision += 1
    }

    /// Palette colors resolved once per palette identity + velocity; the
    /// display lists index the same colors in slot order.
    @QtIgnored
    private func resolvePalette(_ input: GridSceneInput) -> [UInt32] {
        let key = PaletteContentKey(
            palette: ObjectIdentifier(input.palette),
            lastVelocity: input.lastVelocity)
        if let cached = paletteContentCache, cached.key == key { return cached.colors }
        let colors = RollDrawingContent.paletteColors(input)
        paletteContentCache = (key, colors)
        plotPalette = colors
        return colors
    }
}
