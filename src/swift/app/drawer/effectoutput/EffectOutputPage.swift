import Foundation
import NativeDisplayList
import PorydawAppCommands
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawPluginHost
import QtBridge

/// Workspace-owned session output. QML reports focus through its slot; publication is owner-controlled.
@MainActor
@QtBridgeable
public final class EffectOutputPage: EditorDrawerPage, QmlUncreatable {
    public static let contentUrl =
        QmlEngineAccess.moduleResourcePrefix + "src/ui/songview/quick/drawer/EffectOutputPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .effectOutput
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    @QtIgnored public var onAddEffectRequested: ((Int) -> Void)?
    @QtIgnored public var onCommandAvailabilityChanged: (() -> Void)?
    public var bodyFocused: Bool = false
    @QtIgnored public var interactionActive: Bool = false {
        didSet {
            if interactionActive != oldValue { onCommandAvailabilityChanged?() }
        }
    }
    public var hasEffect: Bool = false
    public var live: Bool = false
    public var rendering: Bool = false
    public var busy: Bool = false
    public var canOperate: Bool = false
    public var canRender: Bool = false
    public var canGrab: Bool = false
    public var canOpenEditor: Bool = false
    public var canReload: Bool = false
    public var canCopy: Bool = false
    public var canClear: Bool = false
    public var canAddEffect: Bool = false
    public var progress: Double = 0
    public var status: String = ""
    public var diagnostics: String = ""
    public var originLabel: String = ""
    public var emptyText: String = "No MIDI effect on this track"
    public var noteCount: Int = 0
    public var selectedCount: Int = 0
    public var minimumPitch: Int = 0
    public var maximumPitch: Int = 0
    public var pitchLabel: String = ""
    public var plotWidth: Double = 0
    public var plotHeight: Double = 0
    public var rulerWidth: Double = 0
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var devicePixelRatio: Double = 1
    public var displayRevision: Int = 0
    @QtTracked public var promptStyle = PromptStyle()
    @QtTracked public var bodyFont = QmlFont(family: gridBodyFamily, pixelSize: 13)

    private weak var viewport: DocumentViewport?
    private var effects: TrackEffectsController?
    private var colors = GridPalette()
    private let clipboard = GridClipboard()
    private var selectedTrack: Int?
    private var effectID: EffectID?
    private var output: EffectOutput?
    private var selected: Set<Int> = []
    private var rectangles: [CGRect] = []
    private var rangeBand: CGRect?
    private var fills: [UInt32] = []
    private var writer = DisplayListWriter()
    private var bytes = Data()
    private var emptyBytes: Data?
    private var active = false
    private var playing = false
    private var message = ""
    private var outputMessage = ""
    private var renderMessage = ""
    private var dragDistance: Double = DrawerPan.dragDistanceSeed
    private var gesture: Gesture?
    // Observation can end before execution; every unfinished request stays owned independently.
    private var currentOperation: ActiveOperation?
    private var pendingOperations: [UUID: Task<Void, Never>] = [:]

    private struct Gesture {
        let start: CGPoint
        let selection: Set<Int>
        let additive: Bool
        var current: CGPoint
        var dragging = false
    }

    private enum Operation {
        case live(Bool)
        case render(TimeRange)
        case openEditor, reload
    }

    private struct ActiveOperation {
        let token: UUID
        let effect: EffectID
        let kind: Operation
    }

    public init(baseFontPx: Double = 13) {
        let base = baseFontPx.isFinite && baseFontPx > 0 ? baseFontPx : GridCameraPolicy.seedBaseFontPx
        self.baseFontPx = base
        bodyPolicy = EditorDrawerBodyPolicy { (hostHeight: Int, metrics: EditorDrawerMetrics) -> Int in
            max(metrics.minimumBody, hostHeight / 5)
        }
    }

    isolated deinit {
        for task in pendingOperations.values { task.cancel() }
    }

    private func cancelOperation() {
        guard let currentOperation else { return }
        self.currentOperation = nil
        pendingOperations[currentOperation.token]?.cancel()
        if case .render = currentOperation.kind { effects?.cancelRender(currentOperation.effect) }
    }

    @QtIgnored
    public func attach(viewport: DocumentViewport, palette: GridPalette, effects: TrackEffectsController) {
        cancelOperation()
        self.viewport = viewport
        colors = palette
        self.effects = effects
        refreshAppearance()
        refreshFromDocument()
    }

    @QtIgnored
    public func activate() {
        active = true
        refreshFromDocument()
    }

    public func setBodyFocused(focused: Bool) {
        guard bodyFocused != focused else { return }
        bodyFocused = focused
        onCommandAvailabilityChanged?()
    }

    @QtIgnored
    public func suspend() {
        active = false
        setBodyFocused(focused: false)
        cancelOperation()
        cancelSectionInteraction()
        refreshHeader()
    }

    @QtIgnored
    public func detach() {
        suspend()
        viewport = nil
        effects = nil
        selectedTrack = nil
        effectID = nil
        output = nil
        rangeBand = nil
        selected.removeAll(keepingCapacity: true)
        rectangles.removeAll(keepingCapacity: true)
        fills.removeAll(keepingCapacity: true)
        message = ""
        outputMessage = ""
        onAddEffectRequested = nil
        refreshOutputFacts()
        onCommandAvailabilityChanged = nil
        publishScene()
        refreshHeader()
    }

    /// Joins every page-owned request before the workspace shuts down its controller.
    @QtIgnored
    public func shutdown() async {
        detach()
        for task in pendingOperations.values { task.cancel() }
        while let task = pendingOperations.values.first { await task.value }
    }

    private func refreshOutputFacts() {
        publish(\.noteCount, output?.notes.count ?? 0)
        publish(\.selectedCount, selected.count)
        var low = 127
        var high = 0
        if let output {
            for note in output.notes {
                low = min(low, Int(note.pitch))
                high = max(high, Int(note.pitch))
            }
        }
        publish(\.minimumPitch, noteCount == 0 ? 0 : low)
        publish(\.maximumPitch, noteCount == 0 ? 0 : high)
        publish(\.pitchLabel, noteCount == 0 ? "" : "\(low)–\(high)")
        publish(\.diagnostics, MidiEffectDiagnostics.text(output?.report))
        var origin = ""
        if let output {
            switch output.origin {
            case .render: origin = "Rendered"
            case .grab: origin = "Played"
            }
            if output.degraded { origin += " · some notes were dropped" }
        }
        publish(\.originLabel, origin)
        onCommandAvailabilityChanged?()
    }

    private func refreshHeader() {
        let effect = selectedTrack.flatMap { (track: Int) -> TrackEffect? in
            viewport?.session.document.effect(onTrack: track)
        }
        publish(\.hasEffect, effect != nil)
        publish(
            \.emptyText, effect == nil ? "No MIDI effect on this track" : "Render or grab played to see output here")
        publish(\.live, effectID.map { (id: EffectID) -> Bool in effects?.isLive(id) == true } ?? false)
        var nextStatus = message.isEmpty ? outputMessage : message
        var crashed = false
        var unavailable = false
        var loading = false
        var nextRendering = false
        var fraction = 0.0
        if let effect, let effects {
            switch effects.status(effect.id) {
            case .idle, .ready: break
            case .loading: loading = true
            case .rendering(let value):
                nextRendering = true
                fraction = min(1, max(0, value))
                nextStatus = renderMessage
            case .nothingHeard: nextStatus = "Nothing heard yet — play with Live on, then grab."
            case .unavailable(let reason):
                unavailable = true
                nextStatus = "Plugin unavailable: \(reason)"
            case .crashed(let reason):
                crashed = true
                nextStatus = "\(effect.config.plugin.name) \(reason)."
            case .failed(let reason):
                if message.isEmpty { nextStatus = reason }
            }
        }
        if case .render = currentOperation?.kind { nextRendering = true }
        if nextRendering, nextStatus.isEmpty { nextStatus = renderMessage }
        if nextStatus.isEmpty, live { nextStatus = "Live — play the song; the plugin drives this track." }
        let pending = currentOperation != nil || loading || nextRendering
        let permitted = active && effect != nil && !crashed && !unavailable
        publish(\.busy, pending)
        publish(\.rendering, nextRendering)
        publish(\.progress, fraction)
        publish(\.canOperate, permitted && !pending)
        publish(\.canRender, permitted && !pending)
        let loaded = effectID.map { (id: EffectID) -> Bool in effects?.instance(for: id) != nil } ?? false
        publish(\.canGrab, permitted && !pending && loaded)
        publish(\.canOpenEditor, permitted && !pending)
        publish(\.canReload, active && crashed && !pending)
        publish(\.canCopy, active && noteCount > 0)
        publish(\.canClear, active && output != nil && !nextRendering)
        publish(\.canAddEffect, active && selectedTrack != nil && effect == nil)
        publish(\.status, nextStatus)
    }

    private func loadOutput() {
        cancelSectionInteraction()
        selected.removeAll(keepingCapacity: true)
        output = effectID.flatMap { (id: EffectID) -> EffectOutput? in effects?.outputs[id] }
        message = ""
        outputMessage = ""
        if let output {
            switch output.origin {
            case .render:
                outputMessage =
                    output.notes.isEmpty
                    ? "No notes captured — try Realtime pacing." : "Rendered \(output.notes.count) notes."
            case .grab:
                outputMessage =
                    output.notes.isEmpty
                    ? "Nothing heard yet — play with Live on, then grab."
                    : "Grabbed \(output.notes.count) played notes."
            }
        }
        refreshOutputFacts()
        rebuildGeometry()
        refreshHeader()
    }

    @QtIgnored
    public func refreshFromDocument() {
        let track = viewport?.session.selectedTrack
        let id = track.flatMap { (track: Int) -> EffectID? in viewport?.session.document.effect(onTrack: track)?.id }
        if track != selectedTrack || id != effectID {
            cancelOperation()
            selectedTrack = track
            effectID = id
            loadOutput()
        } else {
            refreshHeader()
        }
    }

    @QtIgnored
    public func effectChanged(_ id: EffectID) {
        guard id == effectID else { return }
        refreshHeader()
    }

    @QtIgnored
    public func outputChanged(_ id: EffectID) {
        guard id == effectID else { return }
        loadOutput()
    }

    @QtIgnored
    public func refreshPlayhead(tick _: Double, playing: Bool) {
        guard playing != self.playing else { return }
        self.playing = playing
        refreshHeader()
    }

    @QtIgnored
    public func refreshAppearance() {
        let typography = Typography(baseFontPx: Int(baseFontPx.rounded()))
        publish(\.bodyFont, typography.body.qmlFont)
        promptStyle.update(metrics: PromptAppearance.Layout(base: baseFontPx), palette: colors, font: bodyFont)
        rebuildGeometry()
    }

    public func configureBody(
        width: Double, height: Double, rulerWidth: Double,
        devicePixelRatio: Double, baseFontPx: Double, dragDistance: Double
    ) {
        let width = max(0, width.isFinite ? width : 0)
        let height = max(0, height.isFinite ? height : 0)
        let ruler = max(0, rulerWidth.isFinite ? rulerWidth : 0)
        let dpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let font = baseFontPx.isFinite && baseFontPx > 0 ? baseFontPx : GridCameraPolicy.seedBaseFontPx
        if dragDistance.isFinite, dragDistance > 0 { self.dragDistance = dragDistance }
        guard
            width != plotWidth || height != plotHeight || ruler != self.rulerWidth
                || dpr != self.devicePixelRatio || font != self.baseFontPx
        else { return }
        cancelSectionInteraction()
        publish(\.plotWidth, width)
        publish(\.plotHeight, height)
        publish(\.rulerWidth, ruler)
        publish(\.devicePixelRatio, dpr)
        let fontChanged = font != self.baseFontPx
        publish(\.baseFontPx, font)
        if fontChanged { refreshAppearance() } else { rebuildGeometry() }
    }

    private func rebuildGeometry() {
        let count = output?.notes.count ?? 0
        if rectangles.count > count { rectangles.removeLast(rectangles.count - count) }
        while rectangles.count < count { rectangles.append(.zero) }
        fills.removeAll(keepingCapacity: true)
        fills.reserveCapacity(count)
        if let output {
            for note in output.notes {
                fills.append(colors.noteFillArgb(track: selectedTrack ?? note.track, velocity: Int(note.velocity)))
            }
        }
        refreshCamera()
    }

    @QtIgnored
    public func refreshCamera() {
        guard let camera = viewport?.camera.snapshot, let output else {
            rangeBand = nil
            publishScene()
            return
        }
        let dpr = devicePixelRatio
        let tickScale = camera.pixelsPerTick * dpr
        let origin = (camera.scrollX * dpr).rounded() / dpr
        let start = (Double(output.range.startTick) * tickScale).rounded() / dpr - origin
        let end = (Double(output.range.endTick) * tickScale).rounded() / dpr - origin
        rangeBand = CGRect(x: start, y: 0, width: max(0, end - start), height: plotHeight)
        let padding = min(baseFontPx / 2, plotHeight / 4)
        let rowHeight = max(0, plotHeight - 2 * padding) / Double(max(1, maximumPitch - minimumPitch + 1))
        let gap = min(1 / dpr, rowHeight / 4)
        for index in output.notes.indices {
            let note = output.notes[index]
            let x = (Double(note.tick) * tickScale).rounded() / dpr - origin
            let end = ((Double(note.tick) + Double(note.duration)) * tickScale).rounded() / dpr - origin
            rectangles[index] = CGRect(
                x: x, y: padding + Double(maximumPitch - Int(note.pitch)) * rowHeight + gap,
                width: max(1 / dpr, end - x), height: max(0, rowHeight - 2 * gap))
        }
        publishScene()
    }

    private func emit(_ rect: CGRect, argb: UInt32, id: UInt64 = UInt64.max) {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: plotWidth, height: plotHeight))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return }
        writer.rect(
            PdDlRect(
                x: clipped.minX, y: clipped.minY, w: clipped.width, h: clipped.height,
                id: id, argb: argb, flags: 0))
    }

    private func publishScene() {
        // Drop the Data alias before the retained writer mutates its output storage.
        bytes = Data()
        let pixel = 1 / devicePixelRatio
        if let rangeBand {
            emit(rangeBand, argb: PaletteMath.argb(colors.selectionFill))
            let edge = PaletteMath.argb(colors.selectionEdge)
            emit(CGRect(x: rangeBand.minX, y: 0, width: rangeBand.width, height: pixel), argb: edge)
            emit(CGRect(x: rangeBand.minX, y: 0, width: pixel, height: plotHeight), argb: edge)
            emit(CGRect(x: rangeBand.maxX - pixel, y: 0, width: pixel, height: plotHeight), argb: edge)
            let normalBorder = PaletteMath.argb(colors.noteBorder)
            for index in rectangles.indices {
                let rect = rectangles[index]
                guard rect.maxX > 0, rect.minX < plotWidth else { continue }
                emit(rect, argb: selected.contains(index) ? edge : normalBorder, id: UInt64(index))
                let inset = min(pixel, min(rect.width, rect.height) / 4)
                emit(rect.insetBy(dx: inset, dy: inset), argb: fills[index], id: UInt64(index))
            }
        }
        if let gesture, gesture.dragging {
            let box = CGRect(
                x: min(gesture.start.x, gesture.current.x), y: min(gesture.start.y, gesture.current.y),
                width: abs(gesture.current.x - gesture.start.x), height: abs(gesture.current.y - gesture.start.y))
            emit(box, argb: PaletteMath.argb(colors.selectionFill))
            DrawerStaticsContent.buildDashedFrame(
                into: &writer, box: box, argb: PaletteMath.argb(colors.selectionEdge),
                dashDevicePx: baseFontPx / 3 * devicePixelRatio, gapDevicePx: baseFontPx / 6 * devicePixelRatio,
                dpr: devicePixelRatio, viewport: CGSize(width: plotWidth, height: plotHeight))
        }
        bytes = writer.finish()
        displayRevision &+= 1
    }

    public func displayList(list: Int) -> Data {
        guard list == 0, !bytes.isEmpty else {
            return DrawerStaticsContent.retainedEmptyDisplayList(cached: &emptyBytes)
        }
        return bytes
    }

    private func publishSelection() {
        publish(\.selectedCount, selected.count)
        publishScene()
    }

    public func pointerPress(x: Double, y: Double, modifiers: Int) -> Bool {
        guard active, noteCount > 0, x.isFinite, y.isFinite else { return false }
        cancelSectionInteraction()
        let point = CGPoint(x: x, y: y)
        let hit = rectangles.indices.reversed().first { (index: Int) -> Bool in rectangles[index].contains(point) }
        let additive = modifiers & 0x0200_0000 != 0
        gesture = Gesture(start: point, selection: selected, additive: additive, current: point)
        if let hit {
            if additive {
                if !selected.insert(hit).inserted { selected.remove(hit) }
            } else {
                selected.removeAll(keepingCapacity: true)
                selected.insert(hit)
            }
        } else if !additive {
            selected.removeAll(keepingCapacity: true)
        }
        interactionActive = true
        publishSelection()
        return true
    }

    public func pointerMove(x: Double, y: Double) {
        guard var gesture, x.isFinite, y.isFinite else { return }
        gesture.current = CGPoint(x: min(plotWidth, max(0, x)), y: min(plotHeight, max(0, y)))
        if hypot(x - gesture.start.x, y - gesture.start.y) >= dragDistance { gesture.dragging = true }
        if gesture.dragging {
            let box = CGRect(
                x: min(gesture.start.x, gesture.current.x), y: min(gesture.start.y, gesture.current.y),
                width: abs(gesture.current.x - gesture.start.x), height: abs(gesture.current.y - gesture.start.y))
            selected.removeAll(keepingCapacity: true)
            if gesture.additive { selected.formUnion(gesture.selection) }
            for index in rectangles.indices where rectangles[index].intersects(box) { selected.insert(index) }
        }
        self.gesture = gesture
        publishSelection()
    }

    public func pointerRelease(x: Double, y: Double) {
        guard gesture != nil else { return }
        pointerMove(x: x, y: y)
        gesture = nil
        interactionActive = false
        publishSelection()
    }

    public func cancelSectionInteraction() {
        guard let gesture else { return }
        selected = gesture.selection
        self.gesture = nil
        interactionActive = false
        publishSelection()
    }

    public func handleEscape() -> Bool {
        guard gesture?.dragging == true else { return false }
        cancelSectionInteraction()
        return true
    }

    public func selectAll() {
        guard active, !interactionActive else { return }
        selected.removeAll(keepingCapacity: true)
        for index in rectangles.indices { selected.insert(index) }
        publishSelection()
    }

    public func copyOutput() {
        guard canCopy, let output, let track = selectedTrack, let session = viewport?.session else { return }
        var notes: [NewNote] = []
        notes.reserveCapacity(selected.isEmpty ? output.notes.count : selected.count)
        for index in output.notes.indices where selected.isEmpty || selected.contains(index) {
            let note = output.notes[index]
            notes.append(
                NewNote(
                    track: track, tick: note.tick, pitch: note.pitch, duration: note.duration, velocity: note.velocity))
        }
        guard let clip = ClipboardSemantics.copyNotes(notes, from: track),
            clipboard.write(clip, ticksPerBeat: session.timeline.ticksPerBeat)
        else {
            message = "Could not copy effect output to the clipboard."
            refreshHeader()
            return
        }
    }

    @QtIgnored
    public func selectionCommandAvailable(command: EditCommand) -> Bool {
        guard active, bodyFocused, !interactionActive, viewport?.session.timeSelection?.isActive != true else {
            return false
        }
        return (command == .copy || command == .selectAll) && noteCount > 0
    }

    @QtIgnored
    @discardableResult
    public func consumeSelectionCommand(command: EditCommand) -> Bool {
        guard active, bodyFocused, !interactionActive, viewport?.session.timeSelection?.isActive != true,
            command == .copy || command == .selectAll
        else { return false }
        if selectionCommandAvailable(command: command) {
            if command == .copy { copyOutput() } else { selectAll() }
        }
        return true
    }

    public func clearOutput() {
        guard canClear, let id = effectID else { return }
        effects?.outputs.clear(id)
    }

    public func addEffect() {
        guard canAddEffect, let track = selectedTrack else { return }
        onAddEffectRequested?(track)
    }

    private func begin(_ next: Operation) {
        guard active, let id = effectID, let effects else { return }
        cancelOperation()
        let token = UUID()
        currentOperation = ActiveOperation(token: token, effect: id, kind: next)
        message = ""
        outputMessage = ""
        pendingOperations[token] = Task { @MainActor [weak self] in
            defer { self?.pendingOperations[token] = nil }
            guard !Task.isCancelled, self?.currentOperation?.token == token else { return }
            var failure = ""
            do {
                switch next {
                case .live(let enabled): try await effects.setLive(id, enabled)
                case .render(let range): try await effects.render(id, range: range)
                case .openEditor: try await effects.openEditor(id)
                case .reload: try await effects.reload(id)
                }
            } catch is CancellationError {
                // Lifecycle cancellation retires this request, not a plug-in failure.
            } catch {
                failure = String(describing: error)
            }
            guard let self, self.currentOperation?.token == token else { return }
            self.currentOperation = nil
            self.message = failure
            self.refreshHeader()
        }
        refreshHeader()
    }

    public func setLive(enabled: Bool) {
        guard canOperate else { return }
        begin(.live(enabled))
    }

    public func renderOutput() {
        guard canRender, let id = effectID, let effects, let session = viewport?.session,
            let track = selectedTrack, let effect = session.document.effect(onTrack: track)
        else { return }
        if live, playing {
            message = "Stop playback to render"
            refreshHeader()
            return
        }
        do {
            let range = try effects.renderRange(id)
            if effect.config.plugin.input == .trackNotes {
                let hasSource = session.document.notes(in: track).contains { (note: Note) -> Bool in
                    let end = note.endTick ?? UInt64(range.endTick)
                    return note.tick < range.endTick && end > UInt64(range.startTick)
                }
                guard hasSource else {
                    message = "No source notes in range."
                    refreshHeader()
                    return
                }
            }
            let request = CaptureRequest(
                timeline: session.timeline, track: track, range: range, input: effect.config.plugin.input,
                pacing: effect.config.plugin.pacing, prerollBars: effect.config.plugin.prerollBars)
            let transport = try CaptureTransport(request)
            switch request.pacing {
            case .offline:
                renderMessage = "Rendering..."
            case .realtime:
                let seconds = Int(
                    ceil(Double(transport.endSample - transport.startSample) / CaptureTransport.sampleRate))
                renderMessage = "Rendering in real time (about \(seconds) s)"
            }
            begin(.render(range))
        } catch {
            message = String(describing: error)
            refreshHeader()
        }
    }

    public func cancelRender() {
        guard rendering, let id = effectID else { return }
        if case .render = currentOperation?.kind {
            cancelOperation()
        } else {
            effects?.cancelRender(id)
        }
        message = ""
        refreshHeader()
    }

    public func grabPlayed() {
        guard canGrab, let id = effectID, let effects else { return }
        do {
            message = ""
            try effects.grabPlayed(id)
        } catch {
            message = String(describing: error)
        }
        refreshHeader()
    }

    public func openEditor() {
        guard canOpenEditor else { return }
        begin(.openEditor)
    }

    public func reloadPlugin() {
        guard canReload else { return }
        begin(.reload)
    }
}
