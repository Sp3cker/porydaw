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
        let notes: (data: Data, count: Int)
        if let cached = notesSectionCache, cached.key == key.notesSection {
            notes = (cached.data, cached.count)
        } else {
            notes = RollDrawingContent.notesSection(input)
            notesSectionCache = (key.notesSection, notes.data, notes.count)
        }
        drawingContentData = RollDrawingContent.pack(input, palette: palette, notes: notes.data)
        drawingContentKey = key
        noteRecordCount = notes.count
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
