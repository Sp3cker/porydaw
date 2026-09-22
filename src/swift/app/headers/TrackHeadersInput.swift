import Foundation
import PorydawCore

// Order is shared with the production hit-target contract.
enum HeaderHitTarget: Int { case none, body, voice, mute, solo, addTrack }

struct HeaderPointerState {
    var hoverRow = -1
    var hoverTarget = HeaderHitTarget.none
    var pressedRow = -1
    var pressedTrack = -1
    var pressedTarget = HeaderHitTarget.none
    var pressX: Double = 0
    var pressY: Double = 0
    var dragArmed = false
    var dragging = false
    var target: PendingHeaderMenu?
}

@MainActor
extension TrackHeadersPresenter {
    func rowAt(_ y: Double) -> Int {
        guard rowHeight > 0, y.isFinite else { return -1 }
        let coordinate = (y + scrollY) / Double(rowHeight)
        guard coordinate >= 0, coordinate < Double(snapshots.count) else { return -1 }
        return Int(coordinate.rounded(.down))
    }

    func hitTarget(row: Int, x: Double, y: Double) -> HeaderHitTarget {
        guard snapshots.indices.contains(row), x.isFinite, x >= 0, x <= viewportWidth else {
            return .none
        }
        if snapshots[row].isAddTrack { return .addTrack }
        let localY = y + scrollY - Double(row * rowHeight)
        if geometry.muteRect(width: viewportWidth).contains(x: x, y: localY) { return .mute }
        if geometry.soloRect(width: viewportWidth).contains(x: x, y: localY) { return .solo }
        if geometry.textRects(width: viewportWidth, metrics: textMetrics).1.contains(x: x, y: localY) {
            return .voice
        }
        return .body
    }

    func hover(x: Double, y: Double) {
        let row = rowAt(y)
        pointer.hoverRow = row
        pointer.hoverTarget = hitTarget(row: row, x: x, y: y)
        publishPointerVisuals()
    }

    func publishPointerVisuals() {
        for index in snapshots.indices {
            var row = snapshots[index]
            func hovered(_ target: HeaderHitTarget) -> Bool {
                pointer.hoverRow == index && pointer.hoverTarget == target
            }
            func pressed(_ target: HeaderHitTarget) -> Bool {
                hovered(target) && pointer.pressedRow == index && pointer.pressedTarget == target
            }
            row.muteHovered = !row.isAddTrack && hovered(.mute)
            row.mutePressed = !row.isAddTrack && pressed(.mute)
            row.soloHovered = !row.isAddTrack && hovered(.solo)
            row.soloPressed = !row.isAddTrack && pressed(.solo)
            row.addHovered = row.isAddTrack && hovered(.addTrack)
            row.addPressed = row.isAddTrack && pressed(.addTrack)
            publishRow(row, at: index)
        }
    }

    func pointerPress(x: Double, y: Double, button: Int, modifiers: Int) -> Bool {
        guard let session, !session.isClosed, rowHeight > 0 else { return false }
        if menuOpen {
            dismissHeaderMenu()
            pointer = HeaderPointerState()
            publishPointerVisuals()
            return true
        }
        let row = rowAt(y)
        let target = hitTarget(row: row, x: x, y: y)
        guard target != .none else { return false }
        // An additional right press cannot displace an in-flight left gesture.
        if button == 2 && pointer.pressedRow >= 0 { return true }
        pointer = HeaderPointerState()
        let track = snapshots[row].track
        if target == .addTrack {
            guard button == 1 else { return true }
        } else if button == 2 {
            selectTrack(track)
            showHeaderMenu(track: track, x: x, y: y)
            return true
        } else if target != .mute && target != .solo {
            let action: DocumentSession.TrackScopeAction = modifiers & 0x0400_0000 != 0
                ? .toggle : modifiers & 0x0200_0000 != 0 ? .range : .plain
            session.adjustTrackScope(track: track, action: action)
            if let primary = session.selectedTrack { onTrackSelected?(primary) }
            refreshFromDocument()
            guard button == 1, modifiers & (0x0200_0000 | 0x0400_0000) == 0 else { return true }
            pointer.dragArmed = true
        } else if button != 1 { return true }
        pointer.pressedRow = row
        pointer.pressedTrack = track
        pointer.pressedTarget = target
        pointer.pressX = x
        pointer.pressY = y
        pointer.target = PendingHeaderMenu(document: session.document, track: track)
        hover(x: x, y: y)
        return true
    }

    func pointerMove(x: Double, y: Double, modifiers: Int) -> Bool {
        guard session != nil, rowHeight > 0, x.isFinite, y.isFinite else { return false }
        hover(x: x, y: y)
        if pointer.dragging { updateReorder(y: y); return true }
        if pointer.dragArmed, abs(x - pointer.pressX) + abs(y - pointer.pressY) >= dragDistance,
           snapshots.count - (snapshots.last?.isAddTrack == true ? 1 : 0) >= 2 {
            pointer.dragArmed = false
            pointer.dragging = true
            cursorKind = 18 // Qt::ClosedHandCursor.
            updateReorder(y: y)
            return true
        }
        return pointer.hoverRow >= 0 || pointer.pressedRow >= 0
    }

    func pointerRelease(x: Double, y: Double, button: Int, modifiers: Int) -> Bool {
        guard session != nil, rowHeight > 0 else { return false }
        if pointer.dragging {
            updateReorder(y: y)
            finishReorder(commit: button == 1)
            pointer = HeaderPointerState()
            publishPointerVisuals()
            return true
        }
        guard pointer.pressedRow >= 0 else { return false }
        let pressed = pointer
        let row = rowAt(y)
        let target = hitTarget(row: row, x: x, y: y)
        pointer = HeaderPointerState()
        publishPointerVisuals()
        guard button == 1, row == pressed.pressedRow, target == pressed.pressedTarget,
              let session, pressed.target?.matches(session.document) == true else { return true }
        switch target {
        case .addTrack: activateAddTrack()
        case .mute: activateMute(track: pressed.pressedTrack)
        case .solo: activateSolo(track: pressed.pressedTrack)
        case .body, .voice: onRevealTrackVoiceRequested?(pressed.pressedTrack)
        case .none: break
        }
        return true
    }

    func pointerDoubleClick(x: Double, y: Double, button: Int, modifiers: Int) -> Bool {
        guard session != nil, rowHeight > 0 else { return false }
        let row = rowAt(y)
        let target = hitTarget(row: row, x: x, y: y)
        guard target != .none else { return false }
        pointer = HeaderPointerState()
        publishPointerVisuals()
        guard target == .body || target == .voice else { return true }
        let track = snapshots[row].track
        selectTrack(track)
        if target == .voice { requestTrackVoice(track: track) }
        else { beginRename(track: track) }
        return true
    }

    func updateReorder(y: Double) {
        guard pointer.dragging, y.isFinite else { return }
        let trackCount = snapshots.last?.isAddTrack == true ? snapshots.count - 1 : snapshots.count
        let contentY = y + scrollY
        var slot = 0
        // The frozen header contract inserts above in the top quarter, below
        // for the remaining three quarters. Slots adjacent to the source are no-ops.
        while slot < trackCount && contentY > Double(slot * rowHeight) + Double(rowHeight) * 0.25 {
            slot += 1
        }
        reorderIndicatorVisible = true
        reorderIndicatorY = Double(slot * rowHeight) - scrollY
    }

    func finishReorder(commit: Bool) {
        guard pointer.dragging else { return }
        let source = pointer.pressedTrack
        let slot = reorderIndicatorVisible
            ? Int(((reorderIndicatorY + scrollY) / Double(rowHeight)).rounded()) : -1
        let target = pointer.target
        pointer.dragging = false
        pointer.dragArmed = false
        reorderIndicatorVisible = false
        reorderIndicatorY = 0
        cursorKind = 0
        guard commit, let session, target?.matches(session.document) == true,
              validTrack(source), slot >= 0,
              slot <= session.document.engineTracks.usedTrackCount,
              slot != source, slot != source + 1 else { return }
        let destination = slot > source ? slot - 1 : slot
        finishRename(commit: true, restoreRollFocus: false)
        if session.document.moveTrack(source, to: destination) { refreshFromDocument() }
    }

    func scrollWheel(angleDeltaX: Double, angleDeltaY: Double,
                     pixelDeltaX: Double, pixelDeltaY: Double) -> Bool {
        guard session != nil, rowHeight > 0 else { return false }
        let pixel = pixelDeltaX != 0 || pixelDeltaY != 0
        let x = pixel ? pixelDeltaX : angleDeltaX
        let y = pixel ? pixelDeltaY : angleDeltaY
        guard x.isFinite, y.isFinite, y != 0, abs(x) <= abs(y) else { return false }
        let delta = pixel ? y : y / 120 * Double(rowHeight)
        scrollY = min(maximumScrollY, max(0, scrollY - delta))
        return true
    }
}
