import Foundation
import PorydawCore
import QtBridge

@MainActor
struct GridSceneInput {
    var metrics: GridMetrics
    var grid: RollGrid = RollGrid()
    var palette: GridPalette
    var camera: EditorCamera
    var scale: ScaleProjection = ScaleProjection()
    var typography: GridTypography?
    var fontSpec: (GridFontKind) -> [String: QVariantSettable]
    var fonts: [GridFontKind: GridFontSpec] = [:]
    var notes: [GridNote] = []
    var displayedNote: (GridNote) -> (tick: Int, end: Int, pitch: Int) = {
        ($0.tick, $0.tick + $0.duration, $0.pitch)
    }
    var selectedNotes: Set<NoteID> = []
    var drawPreview: (tick: Int, duration: Int, pitch: Int)?
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    var noteNameMode = false
    var showVelocityValues = false
    var timeSelection: AutomationTimeSelection? = nil
    var usedTrackCount = 0
    var selectedTrack = 0
    var keyboardNames: [String]?
    var keyboardBankIdentity: ObjectIdentifier?
    var keyboardProgram = 0
}
@MainActor
extension GridScene {

    @QtIgnored
    func rebuildStatic(_ input: GridSceneInput) {
        let snapshot = input.camera.snapshot
        sync(cameraScroll, [SceneRect(
            x: snapshot.scrollX, y: snapshot.scrollY, width: 0, height: 0,
            fillColor: "")])
        rebuildHover(input)
    }
}
