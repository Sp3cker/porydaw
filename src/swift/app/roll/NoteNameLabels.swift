import QtBridge

/// One note face eligible for a pitch-name label: resolved out of GridScene's
/// note loop (box, published fill, ghost flag) so this file owns the whole
/// label decision without reaching back into the scene.
@MainActor
struct NoteNameFace {
    let pitch: Int
    let box: (x: Double, y: Double, w: Double, h: Double)
    let fillColor: String
    let ghost: Bool
}

/// Pitch-name labels on roll notes (View menu, note-name mode). Pure layout:
/// GridScene resolves the visible faces and publishes the returned records
/// into `pianoNoteTextModel`, which PianoRollCanvas.qml already renders.
///
/// Mirrors TimelineQuickView::synchronizeNoteText + PianoRoll::noteNameFits /
/// refreshTextLayout (timelinequickview_pianoroll.cpp, pianoroll.cpp,
/// pianoroll_geometry.cpp): with the mode on, each visible selected-track
/// (non-ghost) note carries its pitch name when the fixed face fits the
/// complete name plus two trailing spaces; ghost notes are never labeled.
/// Velocity-value labels shown during a velocity drag are out of scope.
@MainActor
enum NoteNameLabels {
    /// Old `kNoteNameMinKeyH` (pianoroll.cpp): device-independent pixels of
    /// vertical zoom. The Swift camera's `keyHeight` snapshot is the same DIP
    /// unit — GridCameraPolicy limits derive from baseFontPx in DIP, and the
    /// checks drive setKeyHeight with DIP values — so the threshold maps 1:1.
    static let minKeyHeight = 12.0

    /// Whether the fixed note-name face may show at all: mirrors
    /// PianoRoll::refreshTextLayout. The occupied face height (ascent +
    /// descent, i.e. SGFontExtents.height of the noteName font) must fit the
    /// row minus one physical pixel and the half-space label padding on each
    /// side; below that the face hides instead of shrinking. `keyHeight` is
    /// the camera snapshot's keyHeight in DIP (see minKeyHeight).
    static func faceFits(
        keyHeight: Double, occupiedHeight: Double, pixel: Double, spaceHalf: Double
    ) -> Bool {
        keyHeight >= minKeyHeight
            && occupiedHeight <= (keyHeight - pixel - 2 * spaceHalf).rounded(.down)
    }

    /// Whether one note's face fits its complete pitch name plus two trailing
    /// spaces: mirrors PianoRoll::noteNameFits. `advance` is the pitch name's
    /// advance in the fixed note-name face; `spaceHalf`/`spaceTwo` are the
    /// Half/Two spacings (m.spaceHalf/m.spaceTwo, the Swift equivalents of
    /// lyt::space(Space::Half/Two)). `width` is the note rect width — the
    /// Swift note box keeps the rect's width, so box.w applies directly.
    static func nameFits(
        width: Double, pitch: Int, advance: (Int) -> Double,
        spaceHalf: Double, spaceTwo: Double
    ) -> Bool {
        width >= spaceHalf + advance(pitch) + spaceTwo
    }

    /// Contrasting label ink for a note fill: mirrors songview
    /// contrastingTextColor (detail.cpp), choosing between the piano
    /// keyboard's natural- and black-key inks by WCAG contrast ratio.
    static func textColor(fillColor: String, palette: GridPalette) -> String {
        PaletteMath.contrastingTextColor(
            fill: fillColor, light: palette.keyboardNatural, dark: palette.keyboardBlack)
    }

    /// One left-aligned, vertically centred record per labelable face.
    /// `keyHeight`/`occupiedHeight`/`pixel`/`spaceHalf` feed the face gate;
    /// `spaceTwo` and `advance` feed the per-note fit rule; `font` is the
    /// .noteName font spec. Faces arrive pre-culled to the viewport (the same
    /// guard as the fills); ghosts are skipped here, matching the oracle,
    /// which continues past non-selected-track notes before measuring text.
    static func labels(
        faces: [NoteNameFace], keyHeight: Double, occupiedHeight: Double,
        pixel: Double, spaceHalf: Double, spaceTwo: Double,
        advance: (Int) -> Double, font: [String: QVariantSettable],
        palette: GridPalette
    ) -> [SceneText] {
        guard faceFits(
            keyHeight: keyHeight, occupiedHeight: occupiedHeight,
            pixel: pixel, spaceHalf: spaceHalf)
        else { return [] }
        var records: [SceneText] = []
        for face in faces where !face.ghost {
            guard nameFits(
                width: face.box.w, pitch: face.pitch, advance: advance,
                spaceHalf: spaceHalf, spaceTwo: spaceTwo)
            else { continue }
            let name = GridScene.keyName(face.pitch)
            records.append(SceneText(
                rect: (
                    face.box.x + spaceHalf, face.box.y + spaceHalf,
                    max(0, face.box.w - 2 * spaceHalf),
                    max(0, face.box.h - 2 * spaceHalf)),
                text: name, color: textColor(fillColor: face.fillColor, palette: palette),
                font: font, horizontal: 0x1, vertical: 0x80))
        }
        return records
    }
}
