import Foundation
import PorydawCore
import PorydawDocument
import QtBridge
import PorydawAppCommands
import PorydawAppPresentation

@MainActor
extension PianoGrid {
    func commandAvailableImpl(command: Int) -> Bool {
        guard let command = EditCommand(rawValue: command) else { return false }
        return commands.isAvailable(command)
    }

    func performCommandImpl(command: Int) {
        guard let command = EditCommand(rawValue: command) else { return }
        if interactionActive && !editCommandPolicy(command).survivesPointerGesture {
            return
        }
        switch command {
        case .pencilMode:
            pencilMode.toggle()
        case .gridNarrow:
            guard viewport.grid.narrow() else { return }
            refreshGridMenuPresentation()
            refreshFromSession()
        case .gridWiden:
            guard viewport.grid.widen() else { return }
            refreshGridMenuPresentation()
            refreshFromSession()
        case .gridTriplet:
            guard viewport.grid.toggleFeel() else { return }
            refreshGridMenuPresentation()
            refreshFromSession()
        default:
            let position = TimeDefaults.tick(from: Double(editCursorTick))
            let grid = viewport.grid.snapTicksAt(position, camera: viewport.camera)
            let didEdit = commands.execute(
                command, snapTicks: grid,
                editCursor: position,
                nextSubdivision: { tick in
                    viewport.grid.nextSubdivisionTickAfter(tick, camera: viewport.camera)
                })
            guard didEdit else { return }
            switch command {
            case .transposeUp, .transposeUpOctave, .transposeDown, .transposeDownOctave:
                let upward = command == .transposeUp || command == .transposeUpOctave
                var edgePitch = upward ? 0 : 127
                var found = false
                for id in session.selectedNoteOrder {
                    guard let note = session.document.note(id),
                        note.track == session.selectedTrack
                    else { continue }
                    edgePitch =
                        upward
                        ? max(edgePitch, Int(note.pitch))
                        : min(edgePitch, Int(note.pitch))
                    found = true
                }
                if found {
                    viewport.mutateCamera { camera in
                        _ = camera.ensureKeyVisible(edgePitch)
                    }
                    if let firstID = session.selectedNoteOrder.first(where: {
                        session.document.note($0)?.track == session.selectedTrack
                    }), let first = session.document.note(firstID) {
                        keyboardAuditionKey = Int(first.pitch)
                        keyboardAuditionTrack = first.track
                        keyboardTransposeAuditionActive = true
                        onAudition?(first.track, Int(first.pitch), Int(first.velocity))
                    }
                }
            case .nudgeLeft, .nudgeRight:
                var first = UInt64.max
                var last: UInt64 = 0
                for id in session.selectedNoteOrder {
                    guard let note = session.document.note(id),
                        note.track == session.selectedTrack
                    else { continue }
                    first = min(first, UInt64(note.tick))
                    let duration = note.isUnterminated ? grid : max(1, note.duration)
                    last = max(last, UInt64(note.tick) + UInt64(duration))
                }
                if first != UInt64.max {
                    let preferEnd = command == .nudgeRight
                    viewport.mutateCamera { camera in
                        _ = camera.ensureRangeVisible(
                            startTick: first, endTick: last,
                            preferEnd: preferEnd, dpr: devicePixelRatio)
                    }
                }
            default:
                break
            }
        }
    }

    func openGridMenuImpl(kind: Int) {
        guard kind == 1 || kind == 2 else { return }
        if gridMenuKind != kind { onGridMenuOpened?() }
        gridMenuKind = kind
        refreshGridMenuPresentation()
    }

    func dismissGridMenuImpl() {
        guard gridMenuKind != 0 else { return }
        gridMenuKind = 0
    }

    func activateGridMenuRowImpl(actionId: Int) {
        let kind = gridMenuKind
        guard
            (kind == 1 && viewport.grid.selections.contains { $0.toMenuId() == actionId })
                || (kind == 2 && (0...1).contains(actionId))
        else { return }
        dismissGridMenu()
        let changed =
            kind == 1
            ? viewport.grid.setSelection(GridSelection.fromMenuId(actionId))
            : viewport.grid.setFeel(actionId == 1 ? .triplet : .straight)
        guard changed else { return }
        refreshGridMenuPresentation()
        refreshFromSession()
    }

    private func gridDivisionText(_ selection: GridSelection) -> String {
        switch selection {
        case .auto: "Auto"
        case .musical(let denominator): "1/\(denominator)"
        case .clock: "Clock"
        }
    }

    func refreshGridMenuPresentation() {
        let selection = viewport.grid.selection
        gridSelectionMenuId = selection.toMenuId()
        gridDivisionControlText = gridDivisionText(selection)
        tripletGrid = viewport.grid.feel == .triplet
        gridFeelControlText = tripletGrid ? "Triplet" : "Straight"
        if gridMenuKind == 1 {
            gridMenuRows.reset(
                to: viewport.grid.selections.map { item in
                    let text = gridDivisionText(item)
                    return GridSubdivisionMenuItem(
                        actionId: item.toMenuId(), text: text,
                        checked: item == selection)
                })
        } else if gridMenuKind == 2 {
            gridMenuRows.reset(to: [
                GridSubdivisionMenuItem(
                    actionId: 0, text: "Straight",
                    checked: !tripletGrid),
                GridSubdivisionMenuItem(
                    actionId: 1, text: "Triplet",
                    checked: tripletGrid),
            ])
        }
    }
}
