import Foundation
import PorydawCore
import QtBridge

@MainActor
extension GridScene {
    /// Content seam: resolves palette/colors and records once per content
    /// key, repacks legacy bytes on content-key moves, then builds the frame.
    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        let (palette, colors) = resolvePalette(input)
        let key = RollDrawingContent.key(input, palette: palette)
        if noteRecordsKey != key.notesSection {
            noteRecordsMaxDuration = RollDrawingContent.resolveNotes(input, into: &noteRecords)
            noteRecordsKey = key.notesSection
            builtProjection = input.camera.projection
            contentGeneration += 1
        }
        if key != drawingContentKey {
            drawingContentData = RollDrawingContent.pack(input, palette: palette)
            drawingContentKey = key
            contentRevision += 1
            contentGeneration += 1
        }
        rebuildPlot(input, colors: colors)
    }

    /// Camera-only seam: O(visible), no content-key scan. Cold start with
    /// no resolved records falls back to the content seam.
    @QtIgnored
    func rebuildDisplayLists(_ input: GridSceneInput) {
        guard noteRecordsKey != nil else {
            rebuildNotes(input)
            return
        }
        let (_, colors) = resolvePalette(input)
        rebuildPlot(input, colors: colors)
    }

    /// True when the cached records were resolved against this projection.
    /// Fixed-size compare; never scans notes.
    @QtIgnored
    func projectionCovers(_ projection: PitchProjection) -> Bool {
        builtProjection == projection
    }

    @QtIgnored
    private func rebuildPlot(_ input: GridSceneInput, colors: [UInt32]) {
        let snapshot = input.camera.snapshot
        let band = input.bandSelection.map {
            RollBandSignature(x: $0.x, y: $0.y, w: $0.w, h: $0.h)
        }
        let frame = RollDisplayFrameKey(
            generation: contentGeneration, camera: snapshot,
            dpr: input.metrics.dpr, band: band)
        if frame == displayFrameKey { return }
        if displayLists.count != 3 {
            displayLists = [Data(), retainedEmptyDisplayList(), retainedEmptyDisplayList()]
        }
        // Release the previous buffer before the retained writer reuses its
        // own: otherwise finish()'s shared output copies on write each frame.
        displayLists[0] = Data()
        let built = plotBuilder.build(
            input, records: noteRecords, palette: colors,
            maxDuration: noteRecordsMaxDuration,
            width: snapshot.viewportWidth, height: snapshot.rollHeight)
        displayLists[0] = built.data
        displayFrameKey = frame
        noteRecordCount = built.count
        displayRevision += 1
    }

    /// Palette colors resolved once per palette identity + velocity; the
    /// legacy packed bytes derive from the same colors in slot order.
    @QtIgnored
    private func resolvePalette(_ input: GridSceneInput) -> (data: Data, colors: [UInt32]) {
        let key = PaletteContentKey(
            palette: ObjectIdentifier(input.palette),
            lastVelocity: input.lastVelocity)
        if let cached = paletteContentCache, cached.key == key { return (cached.data, plotPalette) }
        let colors = RollDrawingContent.paletteColors(input)
        let data = RollDrawingContent.paletteSection(colors: colors)
        paletteContentCache = (key, data)
        plotPalette = colors
        return (data, colors)
    }
}
