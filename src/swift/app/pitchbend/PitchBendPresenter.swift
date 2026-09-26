import Foundation
import PorydawCore
import PorydawAppCommands
import QtBridge

/// One document-scoped popup. Draft gestures stay in the kernels; only completed
/// gestures enter SongDocument history, so opening or dismissing adds no history.
@MainActor
@QtBridgeable
public final class PitchBendPresenter {
    @QtTracked public var isOpen = false
    @QtTracked public var bendRange = 2
    @QtTracked public var lfoSpeed = 22
    @QtTracked public var noteDescription = ""
    @QtTracked public var description = ""
    public var metrics: [String: QVariantSettable] = [:]
    public var appearance: [String: QVariantSettable] = [:]
    @QtTracked public var anchorX = 0.0
    @QtTracked public var anchorY = 0.0
    @QtTracked public var anchorWidth = 0.0
    @QtTracked public var anchorHeight = 0.0
    private let session: DocumentSession
    private let grid: PianoGrid
    private let palette: GridPalette
    private var typography: Typography
    private var geometry: PitchBendGeometry
    private var note: Note?
    private var noteEnd = 0
    private var endRange = 2
    private var endSpeed = 22
    @QtTracked public var currentPitch: PitchBendLane?
    @QtTracked public var currentMod: PitchBendLane?
    @QtIgnored public var onAuditionFromTick: ((Tick) -> Void)?
    @QtIgnored public var onSoloTracksRequested: (() -> Void)?

    public init(session: DocumentSession, grid: PianoGrid, palette: GridPalette,
                typography: Typography = Typography(baseFontPx: 13)) {
        self.session = session
        self.grid = grid
        self.palette = palette
        self.typography = typography
        geometry = PitchBendGeometry(fontPx: grid.baseFontPx,
                                     lineSpacing: grid.baseFontPx, dpr: 1)
        configure(fontPx: grid.baseFontPx, lineSpacing: grid.baseFontPx, dpr: 1)
    }

    public func pitchGraph() -> PitchBendLane {
        guard let currentPitch else { preconditionFailure("Pitch graph requested while closed") }
        return currentPitch
    }
    public func modGraph() -> PitchBendLane {
        guard let currentMod else { preconditionFailure("Mod graph requested while closed") }
        return currentMod
    }

    public func configure(fontPx: Double, lineSpacing: Double, dpr: Double) {
        guard fontPx > 0, lineSpacing > 0 else { return }
        let nextBase = Int(fontPx.rounded())
        if nextBase != typography.baseFontPx {
            typography = Typography(baseFontPx: nextBase)
        }
        geometry = PitchBendGeometry(fontPx: fontPx, lineSpacing: lineSpacing, dpr: dpr)
        metrics = geometry.metrics
        appearance = [
            "windowBackground": palette.windowBackground,
            "primaryText": palette.primaryText,
            "secondaryText": palette.secondaryText,
            "outline": palette.outline,
            "trackColor": palette.noteFill(track: note?.track ?? 0, velocity: 127),
            "titleFont": typography.bodyBold.map,
            "captionFont": typography.caption.map,
            "monospaceFont": typography.bodyMono.map,
            "dragInput": [
                "background": palette.buttonBackground,
                "text": palette.buttonText,
                "outline": palette.outline,
                "focus": palette.focusOutline,
                "selection": palette.tabSelectedBackground,
                "selectionText": palette.selectionText,
                "font": typography.body.map,
                "radius": Double(typography.space(.one)),
                "borderWidth": geometry.hairline,
                "horizontalPadding": Double(typography.space(.one)),
                "verticalPadding": Double(typography.space(.half)),
                "dragThreshold": geometry.scrubThreshold,
            ] as [String: QVariantSettable],
        ]
        currentPitch?.refreshGeometry(geometry: geometry)
        currentMod?.refreshGeometry(geometry: geometry)
    }

    /// The routed Edit→Pitch Bend command opens the first selected note on the active track.
    @discardableResult
    public func openSelected() -> Bool {
        guard !session.isClosed, let selectedTrack = session.selectedTrack,
              let note = session.selectedNoteOrder.lazy.compactMap({
                  self.session.document.note($0)
              }).first(where: { $0.track == selectedTrack }),
              let endTick = note.endTick, endTick <= UInt64(Tick.max) else { return false }
        let end = Int(endTick)
        guard end > Int(note.tick) else { return false }
        cancelAndClose()
        self.note = note
        noteEnd = end
        let x0 = session.camera.displayX(tick: Double(note.tick), origin: 0, dpr: grid.devicePixelRatio)
        let x1 = session.camera.displayX(tick: Double(end), origin: 0, dpr: grid.devicePixelRatio)
        let row = session.camera.projection.row(forPitch: Int(note.pitch))
        anchorX = x0
        anchorWidth = max(grid.baseFontPx / 6, x1 - x0)
        anchorY = Double(row) * session.camera.snapshot.keyHeight - session.camera.snapshot.scrollY
        anchorHeight = session.camera.snapshot.keyHeight
        (bendRange, endRange) = controllerValues(0x14, fallback: 2)
        (lfoSpeed, endSpeed) = controllerValues(0x15, fallback: 22)
        let pitch = PitchBendLane(kernel: kernel(for: .pitchBend, lane: .pitch, note: note),
                                  palette: palette, track: note.track)
        let mod = PitchBendLane(kernel: kernel(for: .controller(1), lane: .modulation, note: note),
                                palette: palette, track: note.track)
        pitch.bendRange = bendRange
        pitch.rebuild()
        pitch.onCommit = { [weak self, weak pitch] in
            guard let self, let pitch else { return }
            self.commit(pitch, lane: .pitchBend)
        }
        mod.onCommit = { [weak self, weak mod] in
            guard let self, let mod else { return }
            self.commit(mod, lane: .controller(1))
        }
        pitch.onWheelSteps = { [weak self] steps in
            guard let self else { return }
            self.setBendRange(value: self.bendRange + steps)
        }
        currentPitch = pitch
        currentMod = mod
        refreshDescription()
        isOpen = true
        return true
    }

    public func cancelAndClose() {
        guard isOpen else { return }
        currentPitch?.cancelGesture()
        currentMod?.cancelGesture()
        isOpen = false
        currentPitch = nil
        currentMod = nil
        note = nil
    }

    public func settleAndClose() {
        guard isOpen else { return }
        currentPitch?.settleGesture()
        currentMod?.settleGesture()
        isOpen = false
        currentPitch = nil
        currentMod = nil
        note = nil
    }

    public func resetPitchCurve() {
        guard isOpen, let pitch = currentPitch else { return }
        let before = pitch.kernel.points
        pitch.kernel.reset()
        guard pitch.kernel.points != before else { return }
        pitch.rebuild()
        commit(pitch, lane: .pitchBend)
    }

    public func resetModCurve() {
        guard isOpen, let mod = currentMod else { return }
        let before = mod.kernel.points
        mod.kernel.reset()
        guard mod.kernel.points != before else { return }
        mod.rebuild()
        commit(mod, lane: .controller(1))
    }

    public func setBendRange(value: Int) {
        let bounded = min(127, max(0, value))
        guard isOpen, bounded != bendRange, let note, spanStillPresent() else { return }
        let before = session.document.revision
        session.document.writeLane(track: note.track, lane: .controller(0x14),
                                   from: note.tick, through: Tick(noteEnd),
                                   points: [LaneWrite(tick: note.tick, value: bounded),
                                            LaneWrite(tick: Tick(noteEnd), value: endRange)])
        guard session.document.revision != before else { return }
        bendRange = bounded
        currentPitch?.bendRange = bounded
        currentPitch?.rebuild()
        refreshDescription()
    }

    public func setLfoSpeed(value: Int) {
        let bounded = min(127, max(0, value))
        guard isOpen, bounded != lfoSpeed, let note, spanStillPresent() else { return }
        let before = session.document.revision
        session.document.writeLane(track: note.track, lane: .controller(0x15),
                                   from: note.tick, through: Tick(noteEnd),
                                   points: [LaneWrite(tick: note.tick, value: bounded),
                                            LaneWrite(tick: Tick(noteEnd), value: endSpeed)])
        guard session.document.revision != before else { return }
        lfoSpeed = bounded
        refreshDescription()
    }

    /// DocumentSession publishes this on undo/redo and external note edits.
    @QtIgnored
    public func documentDidChange() {
        guard isOpen else { return }
        guard spanStillPresent() else { cancelAndClose(); return }
        if currentPitch?.kernel.hasGesture == true || currentMod?.kernel.hasGesture == true {
            return
        }
        (bendRange, endRange) = controllerValues(0x14, fallback: 2)
        (lfoSpeed, endSpeed) = controllerValues(0x15, fallback: 22)
        if let note {
            let pitch = kernel(for: .pitchBend, lane: .pitch, note: note)
            currentPitch?.kernel.setCurve(pitch.points, endValue: pitch.endValue)
            currentPitch?.bendRange = bendRange
            currentPitch?.rebuild()
            let mod = kernel(for: .controller(1), lane: .modulation, note: note)
            currentMod?.kernel.setCurve(mod.points, endValue: mod.endValue)
            currentMod?.rebuild()
        }
        refreshDescription()
    }

    public func routeUnclaimedKey(key: Int, modifiers: Int, autoRepeat: Bool) -> Bool {
        if key == 0x01000007 || key == 0x01000003 {
            currentPitch?.removeSelectedVertex()
            currentMod?.removeSelectedVertex()
            return true
        }
        if key == 0x01000004 || key == 0x01000005 {
            currentPitch?.kernel.finish()
            currentMod?.kernel.finish()
            return true
        }
        if !autoRepeat && KeybindingRegistry().matches(key, modifiers, "transport.play_pause") {
            if let note { onAuditionFromTick?(Tick(note.tick)) }
            return true
        }
        if KeybindingRegistry().matches(key, modifiers, "roll.solo_tracks") {
            onSoloTracksRequested?()
            return true
        }
        return false
    }

    private func controllerValues(_ controller: UInt8, fallback: Int) -> (Int, Int) {
        guard let note else { return (fallback, fallback) }
        var first = fallback
        var last = fallback
        for point in session.document.lanePoints(track: note.track, lane: .controller(controller)) {
            if Int(point.tick) <= Int(note.tick) { first = min(127, max(0, point.value)) }
            if Int(point.tick) <= noteEnd { last = min(127, max(0, point.value)) }
            if Int(point.tick) > noteEnd { break }
        }
        return (first, last)
    }

    private func kernel(for lane: Lane, lane graphLane: PitchBendKernel.Lane,
                        note: Note) -> PitchBendKernel {
        var entering = 0
        var ending = 0
        var points: [Int: Int] = [:]
        for point in session.document.lanePoints(track: note.track, lane: lane) {
            if Int(point.tick) <= Int(note.tick) { entering = point.value }
            if Int(point.tick) > noteEnd { break }
            ending = point.value
            if Int(point.tick) > Int(note.tick) && Int(point.tick) < noteEnd {
                points[Int(point.tick)] = point.value
            }
        }
        points[Int(note.tick)] = entering
        points[noteEnd] = ending
        let session = self.session
        return PitchBendKernel(lane: graphLane, geometry: geometry,
                               startTick: Int(note.tick), endTick: noteEnd,
                               fineTicks: Int(session.grid.fineGridTicks(camera: session.camera)),
                               snap: { [unowned session] tick, fine in
                                   Int(session.grid.snapTick(tick, camera: session.camera,
                                                             fine: fine))
                               },
                               snapUp: { [unowned session] tick, fine in
                                   Int(session.grid.snapTickUp(tick + 0.5,
                                                               camera: session.camera, fine: fine))
                               },
                               points: points, endValue: ending)
    }

    private func spanStillPresent() -> Bool {
        guard let note, let current = session.document.note(note.id) else { return false }
        if current.track != note.track { return false }
        if current.tick != note.tick { return false }
        if current.endTick != note.endTick { return false }
        return current.pitch == note.pitch
    }

    private func commit(_ graph: PitchBendLane, lane: Lane) {
        guard isOpen, let note, spanStillPresent() else { return }
        let sorted = graph.kernel.orderedPoints
        var points: [LaneWrite] = []
        points.reserveCapacity(sorted.count)
        for point in sorted {
            points.append(LaneWrite(tick: Tick(point.tick), value: point.value))
        }
        session.document.writeLane(track: note.track, lane: lane,
                                   from: note.tick, through: Tick(noteEnd),
                                   points: points)
    }

    private func refreshDescription() {
        noteDescription = note.map { "\(midiKeyName(Int($0.pitch))) · note-scoped · channel-wide" } ?? ""
        description = "BENDR is \(bendRange) semitones and LFO speed is \(lfoSpeed) for this note. "
            + "Edit pitch bend and modulation; scroll inside the pitch bend graph to change "
            + "BENDR, and hold Shift while drawing for angled lines. Both lanes affect every "
            + "sounding note on this MIDI channel."
    }
}
