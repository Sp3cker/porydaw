import PorydawCore
import QtBridge

struct VelocityPublicationScope: OptionSet, Sendable {
    let rawValue: Int

    static let context = Self(rawValue: 1 << 0)
    static let axis = Self(rawValue: 1 << 1)
    static let handles = Self(rawValue: 1 << 2)
    static let grid = Self(rawValue: 1 << 3)
    static let bands = Self(rawValue: 1 << 4)
    static let transient = Self(rawValue: 1 << 5)
    static let readout = Self(rawValue: 1 << 6)
    static let prompt = Self(rawValue: 1 << 7)
    static let interaction = Self(rawValue: 1 << 8)
    static let clear = Self(rawValue: 1 << 9)

    static let content: Self = [
        .context, .axis, .handles, .grid, .bands, .transient, .readout,
        .prompt, .interaction,
    ]
    static let camera: Self = [.handles, .grid, .bands, .transient, .readout]
    static let axisAndHandles: Self = [.axis, .handles, .readout]
    static let handlesAndReadout: Self = [.handles, .readout]
}

@MainActor
extension VelocityPage {
    // MARK: State sampling

    func documentFacts() -> VelocityDocumentFacts {
        guard let session else { return VelocityDocumentFacts() }
        let track = session.selectedTrack ?? -1
        let notes = track >= 0 ? session.projectionCache.notes(in: track) : []
        let source: VelocityContextSource
        if track >= 0, track < session.timeline.tracks.count {
            source = VelocityContextSource(
                firstProgram: session.timeline.tracks[track].firstProgram,
                voiceChanges: session.projectionCache.lanePoints(track: track, lane: .voice),
                slots: session.bankSlots)
        } else {
            source = .unresolved
        }
        return VelocityDocumentFacts(
            revision: session.document.revision, selectedTrack: track, notes: notes,
            orderedSelection: session.selectedNoteOrder, source: source,
            editCursor: session.editCursor)
    }

    func sceneInput() -> VelocitySceneInput {
        let body = state.body
        return VelocitySceneInput(
            camera: state.camera,
            context: state.presentedContext,
            notes: state.document.notes,
            selectedNotes: state.selectedNotes,
            selectedNoteIDs: state.document.selectedIDSet,
            track: max(0, state.document.selectedTrack),
            source: state.document.source,
            gesture: gesture,
            hovered: state.hovered,
            detentsEnabled: state.detentsEnabled,
            geometry: body.geometry,
            plotWidth: body.plotWidth,
            plotHeight: body.plotHeight,
            rulerWidth: body.rulerWidth,
            devicePixelRatio: body.devicePixelRatio,
            baseFontPx: body.baseFontPx,
            metrics: session.map { gridMetrics($0) },
            palette: VelocityScenePalette(
                gridLineSub1: palette.gridLineSub1,
                gridLineSub2: palette.gridLineSub2,
                gridLineSub3: palette.gridLineSub3,
                gridLineBar: palette.gridLineBar,
                gridLineBeat: palette.gridLineBeat,
                gridLineBeatFine: palette.gridLineBeatFine,
                separator: palette.separator,
                primaryText: palette.primaryText,
                selectionRing: palette.selectionRing,
                selectionFill: palette.selectionFill,
                selectionEdge: palette.selectionEdge,
                outline: palette.outline,
                noteBorder: palette.noteBorder))
    }

    // MARK: Single publication pass

    /// The only entry that builds/reuses scene blocks and writes Qt properties
    /// or item models. Callers choose the dependency block invalidated by their
    /// state change; untouched blocks remain cached.
    @QtIgnored func publish(_ scope: VelocityPublicationScope) {
        var next = sceneCache
        if scope.contains(.clear) {
            next = VelocityScene()
        } else {
            let input = sceneInput()
            if scope.contains(.axis), scope.contains(.grid) {
                next = VelocityScene.build(input, textMetrics: textMetrics)
            } else if scope.contains(.grid) {
                let rows = VelocityScene.buildHandleRows(input, axis: axis)
                next.handles = rows.handles
                next.grid = VelocityScene.grid(input)
                let projection = VelocityProjection(
                    camera: input.camera, geometry: input.geometry,
                    devicePixelRatio: input.devicePixelRatio, axis: axis)
                next.bands = VelocityScene.bands(input, axis: axis, projection: projection)
                next.readout = rows.readout
            } else if scope.contains(.axis) {
                let built = VelocityScene.buildAxisAndHandles(input, textMetrics: textMetrics)
                next.axis = built.axis
                next.handles = built.handles
                next.axisRows = built.rows
                next.readout = built.readout
            } else if scope.contains(.handles) {
                let built = VelocityScene.buildHandleRows(input, axis: axis)
                next.handles = built.handles
                next.readout = built.readout
            }
            if scope.contains(.transient) {
                next.transient = VelocityScene.transient(input)
            }
            if scope.contains(.readout), !scope.contains(.handles), !scope.contains(.axis) {
                next.readout = VelocityScene.readout(input, handles: next.handles)
            }
        }

        let previous = sceneCache
        sceneCache = next
        if scope.contains(.axis) || scope.contains(.clear) { axis = next.axis }
        if scope.contains(.context) || scope.contains(.clear) { publishContextValues() }
        if scope.contains(.axis) || scope.contains(.clear) { publishAxis(next.axis, rows: next.axisRows,
                                                                        previous: previous.axisRows) }
        if scope.contains(.handles) || scope.contains(.clear) {
            publishHandles(next.handles, previous: previous.handles)
        }
        if scope.contains(.grid) || scope.contains(.clear) {
            publishRects(gridLines, previous: previous.grid, values: next.grid)
        }
        if scope.contains(.bands) || scope.contains(.clear) {
            publishRects(psgBands, previous: previous.bands, values: next.bands)
        }
        if scope.contains(.transient) || scope.contains(.clear) {
            publishTransient(next.transient, previous: previous.transient)
        }
        if scope.contains(.readout) || scope.contains(.clear) {
            publishReadout(next.readout)
        }
        if scope.contains(.context) || scope.contains(.clear) { publishContextActivation() }
        if scope.contains(.prompt) || scope.contains(.clear) { publishPrompt() }
        if scope.contains(.interaction) || scope.contains(.clear) {
            setPublished(&interactionActive, gesture != nil || prompt != nil)
        }
    }

    private func publishContextValues() {
        let context = state.presentedContext
        setPublished(&contextDiagnostic, context.diagnostic)
        setPublished(&contextSlot, context.slot)
        setPublished(&contextVoiceName, context.map.voiceName)
    }

    private func publishContextActivation() {
        let context = state.presentedContext
        setPublished(&detentsAvailable, context.status == .resolved && context.map.isPSG)
        setPublished(&contextUnsupported, !context.editable)
    }

    private func publishAxis(_ next: VelocityAxisModel, rows: VelocityAxisRows,
                             previous: VelocityAxisRows) {
        publishRects(axisTicks, previous: previous.ticks, values: rows.ticks)
        publishRects(axisGraduations, previous: previous.graduations, values: rows.graduations)
        publishRects(axisMarkers, previous: previous.markers, values: rows.markers)
        publishTexts(axisLabels, previous: previous.labels, values: rows.labels)
        setPublished(&axisMode, next.mode.rawValue)
        setPublished(&axisAccessibleDescription, next.accessibleDescription)
        setPublished(&axisGraduationsVisible, next.mode == .intrinsic && detentsEnabled)
    }

    private func publishHandles(_ values: [VelocityHandleValue],
                                previous: [VelocityHandleValue]) {
        var old = previous
        syncModel(handles, previous: &old, values, makeRow: VelocityHandle.init)
    }

    private func publishRects(_ model: QListModel<SceneRect>, previous: [DrawerRectValue],
                              values: [DrawerRectValue]) {
        var old = previous
        syncModel(model, previous: &old, values) {
            SceneRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height,
                      fillColor: $0.fillColor, primitiveName: $0.primitiveName)
        }
    }

    private func publishTexts(_ model: QListModel<SceneText>, previous: [DrawerTextValue],
                              values: [DrawerTextValue]) {
        var old = previous
        syncModel(model, previous: &old, values) { value in
            let row = SceneText(
                rect: (value.rect.x, value.rect.y, value.rect.width, value.rect.height),
                text: value.text, color: value.color, font: value.font.map,
                horizontal: value.horizontalAlignment, vertical: value.verticalAlignment,
                background: value.background,
                backgroundRect: (value.backgroundRect.x, value.backgroundRect.y,
                                 value.backgroundRect.width, value.backgroundRect.height))
            row.labelClipRect = [
                "x": value.clipRect.x, "y": value.clipRect.y,
                "width": value.clipRect.width, "height": value.clipRect.height,
            ]
            return row
        }
    }

    private func publishTransient(_ value: VelocityTransientValue,
                                  previous: VelocityTransientValue) {
        publishRects(transientRects, previous: previous.rects, values: value.rects)
        let ramp = value.ramp
        setPublished(&rampX0, ramp.x0)
        setPublished(&rampY0, ramp.y0)
        setPublished(&rampLength, ramp.length)
        setPublished(&rampSlopeY, ramp.slopeY)
        setPublished(&rampColor, ramp.color)
        setPublished(&rampVisible, ramp.visible)
    }

    private func publishReadout(_ value: VelocityReadoutValue) {
        setPublished(&readoutText, value.text)
        setPublished(&readoutX, value.x)
        setPublished(&readoutY, value.y)
        setPublished(&selectedCount, value.selectedCount)
        setPublished(&hoveredNoteText, value.hoveredNoteText)
        setPublished(&readoutVisible, value.visible)
    }

    private func publishPrompt() {
        setPublished(&promptDraft, prompt?.draft ?? "")
        setPublished(&promptError, prompt?.error ?? "")
        setPublished(&promptInitialValue, prompt?.initialValue ?? VelocityPromptPolicy.minimum)
        setPublished(&promptOpen, prompt != nil)
    }

    // MARK: Native measurement and projection adapter


    private var textMetrics: DrawerTextMetrics? {
        guard let session else { return nil }
        let key = TypographyKey(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                                rowHeight: session.camera.snapshot.keyHeight)
        if let typographyCache, typographyCache.key == key { return typographyCache.value }
        let typography = GridTypography(
            fonts: GridTypography.fonts(metrics: gridMetrics(session)), rowHeight: key.rowHeight)
        let kinds: [GridFontKind] = [.ruler, .beat, .bold, .sig, .chip, .keyLabel]
        let value = DrawerTextMetrics(
            fonts: Dictionary(uniqueKeysWithValues: kinds.map { ($0, typography.fontSpec($0)) }),
            rulerAscent: typography.rulerAscent,
            rulerHeight: typography.rulerHeight,
            beatAscent: typography.beatAscent,
            beatHeight: typography.beatHeight,
            boldHeight: typography.boldHeight,
            chipHeight: typography.chipHeight)
        typographyCache = (key, value)
        return value
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        let key = MetricsKey(revision: session.document.revision, font: baseFontPx,
                             dpr: devicePixelRatio, width: plotWidth, height: plotHeight)
        if let metricsCache, metricsCache.key == key { return metricsCache.value }
        let value = VelocityScene.gridMetrics(
            baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
            width: plotWidth, height: plotHeight, timeAxis: session.projectionCache.timeAxis)
        metricsCache = (key, value)
        return value
    }

    @QtIgnored var projection: VelocityProjection {
        VelocityProjection(camera: state.camera, geometry: state.body.geometry,
                           devicePixelRatio: state.body.devicePixelRatio, axis: axis)
    }

    private func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }
}
