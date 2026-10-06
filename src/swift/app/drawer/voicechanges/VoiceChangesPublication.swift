import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

// Equality-gated scene, row and modal publication for the retained page owner.

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
        guard let viewport else { return 0 }
        return VoiceChangesScene.xForTick(
            tick, camera: viewport.camera,
            devicePixelRatio: devicePixelRatio)
    }

    @QtIgnored
    func snapTick(at x: Double, fine: Bool = false) -> Tick {
        guard let viewport else { return 0 }
        let raw = max(0, viewport.camera.tickAtContentX(max(0, x)))
        return viewport.grid.snapTick(raw, camera: viewport.camera, fine: fine)
    }

    @QtIgnored
    func markerHit(at x: Double) -> LanePoint? {
        guard let viewport else { return nil }
        return VoiceChangesScene.markerHit(
            at: x, points: lanePoints(), camera: viewport.camera,
            devicePixelRatio: devicePixelRatio,
            hitRadius: fontPx(baseFontPx, VoiceChangesPagePolicy.markerHitRadiusFactor))
    }

    @QtIgnored
    func effectiveContextTick() -> Tick {
        guard let session else { return 0 }
        return VoiceChangesScene.effectiveContextTick(
            playing: playing,
            presentedTick: contextTick,
            editCursor: session.editCursor)
    }

    @QtIgnored
    func contextKey(at tick: Tick) -> VoiceContextKey {
        VoiceChangesScene.contextKey(
            tick: tick, firstProgram: firstProgram(),
            points: lanePoints(), playing: playing)
    }

    // MARK: Content rebuild

    /// Rebuilds every static projection: the typography, the gutter texts, the
    /// held spans, the grid and the markers.
    @QtIgnored
    func rebuildContent() {
        guard let session, let viewport, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        let entries = markerEntries()
        let snapshot = VoiceChangesSceneSnapshot.build(
            sceneInput(session, viewport: viewport, entries: entries), palette: palette, title: title,
            caption: caption)
        trackAvailable = snapshot.trackAvailable
        publishGutter(snapshot.gutterTexts)
        projectMarkers(snapshot.entries)
        publishReadout(snapshot.readout)
        publishTransient()
        publishDisplayLists(entries: entries, session: session, viewport: viewport)
    }

    /// Valid empty list for out-of-range fetches before the first publish.
    /// Built once and retained.
    @QtIgnored func retainedEmptyDisplayList() -> Data {
        DrawerStaticsContent.retainedEmptyDisplayList(cached: &cachedEmptyDisplayList)
    }

    private func publishDisplayLists(
        entries: [VoiceProjectionEntry], session: DocumentSession, viewport: DocumentViewport
    ) {
        var rects: [DrawerStaticRect] = []
        if let track = currentTrack(session), plotHeight > 0 {
            let color = SceneRectPacking.argb(
                PaletteMath.hex(PaletteMath.trackIdentityOklab(track), alpha: 18))
            var program = session.timeline.tracks[track].firstProgram
            var start: Tick = 0
            for entry in entries {
                if program >= 0, entry.tick > start {
                    rects.append(
                        DrawerStaticRect(
                            tickStart: start, tickEnd: entry.tick, y: 0,
                            height: Float(plotHeight), argb: color))
                }
                program = entry.value
                start = entry.tick
            }
            if program >= 0, session.timeline.lengthTicks > start {
                rects.append(
                    DrawerStaticRect(
                        tickStart: start, tickEnd: session.timeline.lengthTicks, y: 0,
                        height: Float(plotHeight), argb: color))
            }
        }
        let colors = DrawerStaticsContent.gridPaletteColors(palette)
        let viewportSize = CGSize(width: plotWidth, height: plotHeight)
        let camera = viewport.camera
        // Release the previous buffer before the retained writer reuses its
        // own: otherwise finish()'s shared output copies on write each frame.
        var writer = listWriter
        DrawerStaticsContent.buildGrid(
            into: &writer, axis: session.projectionCache.timeAxis, grid: viewport.grid,
            camera: camera, viewport: viewportSize, paletteColors: colors)
        DrawerStaticsContent.buildTickRects(
            into: &writer, rects: rects,
            camera: camera, dpr: devicePixelRatio, viewport: viewportSize)
        let list0 = writer.finish()
        listWriter = writer
        let next = [list0]
        guard next != displayLists else { return }
        displayLists = next
        displayRevision &+= 1
    }

    /// The page's own facts for one scene build: the lane, the bank, the track,
    /// the body geometry and the live interaction, over the marker entries the
    /// caller already projected.
    private func sceneInput(
        _ session: DocumentSession,
        viewport: DocumentViewport,
        entries: [VoiceProjectionEntry]
    ) -> VoiceChangesSceneInput {
        let track = currentTrack(session)
        let pad = fontPx(baseFontPx, VoiceChangesPagePolicy.spaceOneFactor)
        return VoiceChangesSceneInput(
            points: lanePoints(),
            entries: entries,
            slots: slotViews(),
            track: track ?? 0,
            firstProgram: firstProgram(),
            trackAvailable: track != nil,
            gutterTitle: gutterTitle,
            contextTick: effectiveContextTick(),
            plotOrigin: plotOrigin,
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            devicePixelRatio: devicePixelRatio,
            pad: pad,
            gap: max(fontPx(baseFontPx, VoiceChangesPagePolicy.hoverPaintPaddingFactor), pad),
            stairLimit: fontPx(baseFontPx, VoiceChangesPagePolicy.spaceFourFactor),
            camera: viewport.camera,
            interaction: interactionSnapshot())
    }

    /// The live interaction one rebuild reads: the frozen drag, the hovered
    /// occurrence and the pressed selection.
    private func interactionSnapshot() -> VoiceInteractionSnapshot {
        VoiceInteractionSnapshot(
            drag: drag, hoverIdentity: hoverIdentity,
            selectedIdentity: selectedIdentity)
    }

    @QtIgnored
    func publishTypography() {
        caption = VoiceCaption(font: typography.caption)
        title = VoiceCaption(font: typography.captionBold)
        publish(\.captionFont, typography.caption.qmlFont)
        publish(\.titleFont, typography.captionBold.qmlFont)
        publish(\.noteNameFont, typography.noteName.qmlFont)
    }

    /// Applies the scene's gutter lines: the title, then the change summary the
    /// legacy band publishes while a track is presented.
    @QtIgnored
    func publishGutter(_ values: [SceneText]) {
        syncModel(gutterTexts, values) {
            $0.current == $1.current
                && $0.clipX == $1.clipX && $0.clipY == $1.clipY
                && $0.clipWidth == $1.clipWidth && $0.clipHeight == $1.clipHeight
        }
    }

    /// The marker projection: the scene computes one marker rule and one label
    /// box per entry from the page's own geometry, and the page publishes them
    /// through its model seam while keeping the geometry lookup a repaint reuses.
    @QtIgnored
    func projectMarkers(_ entries: [VoiceProjectionEntry], reuseGeometry: Bool = false) {
        if !reuseGeometry { markerLookup.removeAll(keepingCapacity: true) }
        guard let session, let viewport else {
            publishMarkers([])
            return
        }
        publishMarkers(
            VoiceChangesScene.markers(
                sceneInput(session, viewport: viewport, entries: entries), palette: palette, caption: caption,
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
            publish(\.previewVisible, false)
            publish(\.previewX, 0)
            publish(\.previewTick, 0)
            return
        }
        publish(\.previewVisible, true)
        publish(\.previewX, xForTick(live.previewTick))
        publish(\.previewTick, Double(live.previewTick))
    }

    /// The current legacy lane hint: marker-specific while the pointer hits a
    /// change rule, horizontal scrolling everywhere else in the plot.
    @QtIgnored
    func publishHoverHintProfile(marker: Bool) {
        let profile = marker ? VoiceHintProfile.marker : VoiceHintProfile.horizontalScroll
        publish(\.hoverHintProfile, profile)
    }

    /// The readout from live page facts: the cursor-only publication path, which
    /// applies it without a rebuild.
    @QtIgnored
    func publishReadout() {
        publishReadout(
            VoiceChangesScene.readout(
                firstProgram: firstProgram(),
                tick: effectiveContextTick(),
                points: lanePoints(),
                slots: slotViews(),
                pad: fontPx(baseFontPx, VoiceChangesPagePolicy.spaceOneFactor),
                plotWidth: plotWidth,
                plotHeight: plotHeight))
    }
    /// Re-publishes a retained context without resolving the voice lane again.
    @QtIgnored
    func publishReadout(forSlot slot: Int) {
        let pad = fontPx(baseFontPx, VoiceChangesPagePolicy.spaceOneFactor)
        let slots = slotViews()
        let view = slots.indices.contains(slot) ? slots[slot] : nil
        publishReadout(
            VoiceReadoutValues(
                slot: slot,
                blank: view?.voice == nil && view?.tone == nil,
                symbol: view?.voice?.symbol ?? "",
                text: {
                    let label = VoiceChangesScene.sceneContextLabel(slot: slot, slots: slots)
                    return label.isEmpty ? "No voice" : label
                }(),
                x: pad,
                y: 0,
                width: max(0, plotWidth - 2 * pad),
                height: plotHeight))
    }

    /// Applies the scene's readout values: the effective context's label,
    /// right-aligned in the plot. The page always publishes them; the QML draws
    /// them while a track is presented, exactly as the legacy band does.
    private func publishReadout(_ values: VoiceReadoutValues) {
        publish(\.contextSlot, values.slot)
        publish(\.contextBlank, values.blank)
        publish(\.contextSymbol, values.symbol)
        publish(\.readoutText, values.text)
        publish(\.readoutVisible, trackAvailable)
        publish(\.readoutX, values.x)
        publish(\.readoutY, values.y)
        publish(\.readoutWidth, values.width)
        publish(\.readoutHeight, values.height)
    }

    // MARK: Internals: picker publication

    @QtIgnored
    func publishPicker() {
        guard let live = picker else {
            syncPickerRows([])
            return
        }
        pickerCache.resolve(filter: live.filter)
        pickerCache.releaseIfFilteredOut(audition: onAuditionVoice)
        syncPickerRows(pickerCache.selectedRows(program: live.program))
        publish(\.pickerFilter, live.filter)
        publish(\.pickerIndex, pickerCache.indices[live.program] ?? -1)
        publish(\.pickerHasMatch, live.program >= 0)
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
        live.program = pickerCache.initialProgram(live.program)
        picker = live
        publish(\.pickerTitle, live.title)
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
        VoiceChangesProjection.publishPickerRows(
            pickerRows, snapshots: &pickerRowSnapshots, values: values)
    }


}
