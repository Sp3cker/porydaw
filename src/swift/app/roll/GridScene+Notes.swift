import Foundation
import PorydawCore
import QtBridge

@MainActor
extension GridScene {
    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        let palette = paletteContent(input)
        let key = RollDrawingContent.key(input, palette: palette)
        if key == drawingContentKey { return }
        let packed = RollDrawingContent.pack(input, palette: palette)
        drawingContentData = packed.data
        drawingContentKey = key
        noteRecordCount = packed.noteRecords
        contentRevision += 1
    }

    private func paletteContent(_ input: GridSceneInput) -> Data {
        let key = PaletteContentKey(
            palette: ObjectIdentifier(input.palette),
            lastVelocity: input.lastVelocity)
        if let cached = paletteContentCache, cached.key == key { return cached.data }
        let data = RollDrawingContent.paletteSection(input)
        paletteContentCache = (key, data)
        return data
    }
}
