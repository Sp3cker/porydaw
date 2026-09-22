import PorydawCore
import QtBridge

// Publication machinery for the drawer's Voice Changes section: the content
// rebuild that republishes every static projection, the scene-input assembly
// each build reads, the marker/span/grid/gutter apply paths that sync the
// published primitives and item models, the picker-row publication, and the
// readout, transient and hover-hint publications, plus the metrics and entry
// caches those paths reuse.
//
// Ownership: an extension of the page, never a separate object. Published
// state and the caches stay declared on `VoiceChangesPage` — `@QtBridgeable`
// registers class-body members only and stored properties cannot move to an
// extension — so this file reads and writes the page's own state and publishes
// through `setPublished` and `syncModel`: it holds no session, no cache and no
// bridge type of its own.

@MainActor
extension VoiceChangesPage {
    // MARK: Internals: projection

    @QtIgnored
    func lanePoints() -> [LanePoint] {
        guard let session, let track = currentTrack(session) else { return [] }
        return session.projectionCache.lanePoints(track: track, lane: .voice)
    }

    @QtIgnored
    func firstProgram() -> Int {
        guard let session, let track = currentTrack(session) else { return -1 }
        return session.timeline.tracks[track].firstProgram
    }

    @QtIgnored
    func slotViews() -> [BankSlotView] { session?.bankSlots ?? [] }

    /// The page's binding of the scene's plot rules to the live session: the
    /// shared camera, the cached grid metrics and the document's own clock
    /// lattice. The rules themselves live in `VoiceChangesScene`.
    @QtIgnored
    func xForTick(_ tick: Tick) -> Double {
        guard let session else { return 0 }
        return VoiceChangesScene.xForTick(tick, camera: session.camera,
                                          devicePixelRatio: devicePixelRatio)
    }

    @QtIgnored
    func snapTick(at x: Double, fine: Bool = false) -> Tick {
        guard let session else { return 0 }
        return VoiceChangesScene.snapTick(
            at: x, fine: fine, camera: session.camera, metrics: gridMetrics(session),
            division: session.document.ticksPerBeat,
            extendedClocks: session.document.state.config.extendedClocks)
    }

    @QtIgnored
    func markerHit(at x: Double) -> LanePoint? {
        guard let session else { return nil }
        return VoiceChangesScene.markerHit(
            at: x, points: lanePoints(), camera: session.camera,
            devicePixelRatio: devicePixelRatio,
            hitRadius: fontPx(VoiceChangesPagePolicy.markerHitRadiusFactor))
    }

    @QtIgnored
    func effectiveContextTick() -> Tick {
        guard let session else { return 0 }
        return VoiceChangesScene.effectiveContextTick(playing: playing,
                                                     presentedTick: contextTick,
                                                     editCursor: session.editCursor)
    }

    @QtIgnored
    func contextKey(at tick: Tick) -> VoiceContextKey {
        VoiceChangesScene.contextKey(tick: tick, firstProgram: firstProgram(),
                                     points: lanePoints(), playing: playing)
    }

    // MARK: Content rebuild

    /// Rebuilds every static projection: the typography, the gutter texts, the
    /// held spans, the grid and the markers.
    @QtIgnored
    func rebuildContent() {
        guard let session, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        let entries = markerEntries()
        let snapshot = VoiceChangesSceneSnapshot.build(
            sceneInput(session, entries: entries), palette: palette, title: title,
            caption: caption)
        trackAvailable = snapshot.trackAvailable
        publishGutter(snapshot.gutterTexts)
        publishSpans(snapshot.spans)
        publishGrid(snapshot.gridLines)
        projectMarkers(snapshot.entries)
        publishReadout(snapshot.readout)
        publishTransient()
    }

    /// The page's own facts for one scene build: the lane, the bank, the track,
    /// the body geometry and the live interaction, over the marker entries the
    /// caller already projected.
    private func sceneInput(_ session: DocumentSession,
                            entries: [VoiceProjectionEntry]) -> VoiceChangesSceneInput {
        let track = currentTrack(session)
        let pad = fontPx(VoiceChangesPagePolicy.spaceOneFactor)
        return VoiceChangesSceneInput(
            points: lanePoints(),
            entries: entries,
            slots: slotViews(),
            track: track ?? 0,
            firstProgram: firstProgram(),
            lengthTicks: session.timeline.lengthTicks,
            trackAvailable: track != nil,
            gutterTitle: gutterTitle,
            contextTick: effectiveContextTick(),
            plotOrigin: plotOrigin,
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            devicePixelRatio: devicePixelRatio,
            pad: pad,
            gap: max(fontPx(VoiceChangesPagePolicy.hoverPaintPaddingFactor), pad),
            stairLimit: fontPx(VoiceChangesPagePolicy.spaceFourFactor),
            camera: session.camera,
            metrics: gridMetrics(session),
            division: session.document.ticksPerBeat,
            extendedClocks: session.document.state.config.extendedClocks,
            interaction: interactionSnapshot())
    }

    /// The live interaction one rebuild reads: the frozen drag, the hovered
    /// occurrence and the pressed selection.
    private func interactionSnapshot() -> VoiceInteractionSnapshot {
        VoiceInteractionSnapshot(drag: drag, hoverIdentity: hoverIdentity,
                                 selectedIdentity: selectedIdentity)
    }


    @QtIgnored
    func publishTypography() {
        let pixelSize = max(1, Int(baseFontPx.rounded()))
        let caption = VoiceCaption(pixelSize: pixelSize, weight: 400)
        let title = VoiceCaption(pixelSize: pixelSize, weight: 600)
        self.caption = caption
        self.title = title
        setPublishedFont(&captionFont, caption.fontMap)
        setPublishedFont(&titleFont, title.fontMap)
    }

    /// Applies the scene's gutter lines: the title, then the change summary the
    /// legacy band publishes while a track is presented.
    @QtIgnored
    func publishGutter(_ values: [SceneText]) {
        VoiceChangesProjection.syncTexts(gutterTexts, values)
    }

    /// Applies the scene's held spans: one rect per program section, from the
    /// previous change to this one, then the tail to the song's end.
    @QtIgnored
    func publishSpans(_ values: [SceneRect]) {
        VoiceChangesProjection.syncRects(heldSpans, values)
    }

    /// Applies the scene's vertical grid: the roll's own subdivision, beat,
    /// fine-beat and bar lines, through the same grid metrics.
    @QtIgnored
    func publishGrid(_ values: [SceneRect]) {
        VoiceChangesProjection.syncRects(gridLines, values)
    }

    /// The marker projection: the scene computes one marker rule and one label
    /// box per entry from the page's own geometry, and the page publishes them
    /// through its model seam while keeping the geometry lookup a repaint reuses.
    @QtIgnored
    func projectMarkers(_ entries: [VoiceProjectionEntry], reuseGeometry: Bool = false) {
        if !reuseGeometry { markerLookup.removeAll(keepingCapacity: true) }
        guard let session else {
            publishMarkers([])
            return
        }
        publishMarkers(VoiceChangesScene.markers(
            sceneInput(session, entries: entries), palette: palette, caption: caption,
            reusing: markerLookup))
    }

    /// Hover changes only marker roles, not their projected geometry.
    @QtIgnored
    func publishMarkerHover() {
        for (index, marker) in published.enumerated() {
            let hovered = marker.identity == hoverIdentity
            if marker.hovered != hovered {
                marker.hovered = hovered
                markers[index] = marker
            }
        }
    }

    /// The drag's transient: where the frozen occurrence currently drafts.
    @QtIgnored
    func publishTransient() {
        guard let live = drag, live.active else {
            setPublished(&previewVisible, false)
            setPublished(&previewX, 0)
            setPublished(&previewTick, 0)
            return
        }
        setPublished(&previewVisible, true)
        setPublished(&previewX, xForTick(live.previewTick))
        setPublished(&previewTick, Double(live.previewTick))
    }

    /// The current legacy lane hint: marker-specific while the pointer hits a
    /// change rule, horizontal scrolling everywhere else in the plot.
    @QtIgnored
    func publishHoverHintProfile(marker: Bool) {
        let profile = marker ? VoiceHintProfile.marker : VoiceHintProfile.horizontalScroll
        if hoverHintProfile != profile { hoverHintProfile = profile }
    }

    /// The readout from live page facts: the cursor-only publication path, which
    /// applies it without a rebuild.
    @QtIgnored
    func publishReadout() {
        publishReadout(VoiceChangesScene.readout(
            firstProgram: firstProgram(),
            tick: effectiveContextTick(),
            points: lanePoints(),
            slots: slotViews(),
            pad: fontPx(VoiceChangesPagePolicy.spaceOneFactor),
            plotWidth: plotWidth,
            plotHeight: plotHeight))
    }

    /// Applies the scene's readout values: the effective context's label,
    /// right-aligned in the plot. The page always publishes them; the QML draws
    /// them while a track is presented, exactly as the legacy band does.
    private func publishReadout(_ values: VoiceReadoutValues) {
        setPublished(&contextSlot, values.slot)
        setPublished(&contextBlank, values.blank)
        setPublished(&contextSymbol, values.symbol)
        setPublished(&readoutText, values.text)
        setPublished(&readoutVisible, trackAvailable)
        setPublishedRect(&readoutRect,
                         VoiceMarkerHandle.rect(values.x, values.y, values.width, values.height))
    }

    // MARK: Internals: picker publication

    @QtIgnored
    func publishPicker() {
        guard let live = picker else {
            syncPickerRows([])
            return
        }
        pickerCache.resolve(filter: live.filter)
        if let soundingProgram, pickerCache.indices[Int(soundingProgram)] == nil {
            releasePickerAudition()
        }
        syncPickerRows(pickerCache.selectedRows(program: live.program))
        setPublished(&pickerFilter, live.filter)
        setPublished(&pickerIndex, pickerCache.indices[live.program] ?? -1)
        setPublished(&pickerHasMatch, live.program >= 0)
    }

    /// A bank publication while the picker is open: the captured target still
    /// holds, so the picker stays open and its rows, title and filter context
    /// are re-resolved against the new bank's slots. A selection the new bank
    /// no longer publishes falls back to the first visible row, the same
    /// resolution `openPicker` applies.
    @QtIgnored
    func refreshPicker() {
        releasePickerAudition()
        guard var live = picker else { return }
        pickerCache.resolve(filter: live.filter)
        let visible = pickerCache.programs
        if !visible.contains(live.program) {
            live.program = visible.first ?? -1
        }
        picker = live
        setPublished(&pickerTitle, live.title)
        publishPicker()
    }


    @QtIgnored
    func selectPickerProgram(_ program: Int) {
        guard var live = picker, live.program != program else { return }
        live.program = program
        picker = live
        publishPicker()
    }

    // MARK: Internals: publication plumbing

    @QtIgnored
    func publishMarkers(_ values: [VoiceMarkerHandle]) {
        published = values
        if values.isEmpty { markerLookup.removeAll(keepingCapacity: true) }
        for value in values where markerLookup[value.identity] !== value {
            markerLookup[value.identity] = value
        }
        syncModel(markers, values, matches: { $0.matches($1) })
    }

    /// The marker entries one repaint draws: the document's own entries from the
    /// page's revision/track cache, with the frozen drag's preview applied.
    @QtIgnored
    func markerEntries() -> [VoiceProjectionEntry] {
        guard let session, let track = currentTrack(session) else { return [] }
        if entriesRevision != session.document.revision || entriesTrack != track {
            cachedEntries = VoiceChangesProjection.entries(points: lanePoints())
            entriesRevision = session.document.revision
            entriesTrack = track
        }
        return VoiceChangesScene.projectedEntries(
            cachedEntries, interaction: interactionSnapshot())
    }


    @QtIgnored
    func syncPickerRows(_ values: [VoicePickerRowHandle]) {
        let samePrograms = pickerRowSnapshots.count == values.count
            && zip(pickerRowSnapshots, values).allSatisfy { pair in
                pair.0.program == pair.1.program
            }
        pickerRowSnapshots = values
        if samePrograms {
            VoiceChangesProjection.syncPickerRows(pickerRows, values)
        } else {
            // VoicePickerModel::setFilter resets when the visible program set
            // changes; row updates are reserved for selection/label changes.
            pickerRows.reset(to: values)
        }
    }



    /// Writes one published primitive only when it really changed, so a repeated
    /// equal publication emits nothing.
    @QtIgnored
    func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }

    /// The variant-typed records compare through their published spelling:
    /// `[String: QVariantSettable]` is not `Equatable`, and an equal record must
    /// leave its storage untouched.
    @QtIgnored
    func setPublishedRect(_ storage: inout [String: QVariantSettable],
                          _ value: [String: QVariantSettable]) {
        if !VoiceMarkerHandle.rectMatches(storage, value) { storage = value }
    }

    private func setPublishedFont(_ storage: inout [String: QVariantSettable],
                                  _ value: [String: QVariantSettable]) {
        if !VoiceChangesProjection.fontMatches(storage, value) { storage = value }
    }

    // MARK: Internals: shared metrics

    @QtIgnored
    func fontPx(_ multiplier: Double) -> Double {
        multiplier == 0 ? 0 : max(1, (baseFontPx * multiplier).rounded())
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        let key = MetricsKey(revision: session.document.revision, font: baseFontPx,
                             dpr: devicePixelRatio, width: plotWidth, height: plotHeight)
        if metricsKey == key, let cachedMetrics { return cachedMetrics }
        let metrics = GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio,
                                  width: plotWidth, height: plotHeight,
                                  timeAxis: session.projectionCache.timeAxis)
        metricsKey = key
        cachedMetrics = metrics
        return metrics
    }

    static let fontFamily = "Atkinson Hyperlegible Next"
}
