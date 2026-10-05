import Foundation
import PorydawCore

// Voice changes interactions freeze and revalidate revision and occurrence identity.
// Qt-facing entries stay on VoiceChangesPage; this extension uses the page's own state.

private enum VoiceCursorKind: Int {
    case arrow = 0
    case sizeHorizontal = 3
}

@MainActor
extension VoiceChangesPage {
    // MARK: Page seam

    /// The page's local Escape: an open picker, menu, drag, pan or hover claims
    /// the key; otherwise it stays unhandled for the shared routing.
    func dispatchEscape() -> Bool {
        if picker != nil || menu != nil {
            dismissModal()
            return true
        }
        if drag != nil || panRevision != nil {
            cancelSectionInteraction()
            return true
        }
        guard hoverIdentity != nil || hoverVisible else { return false }
        clearHover()
        return true
    }

    /// Ends every page-owned interaction without committing, before hide, replacement
    /// or global cancellation publishes.
    func cancelAllInteractions() {
        cancelDrag()
        cancelPan()
        cancelPicker()
        dismissVoiceMenu()
        clearHover()
        refreshInteractionPublished()
    }

    // MARK: Pointer input

    /// Consumes a press; an open modal only dismisses, without retargeting its capture.
    @discardableResult
    func dispatchPointerPress(
        x: Double, y: Double, surface: Int, button: Int,
        modifiers: Int
    ) -> Bool {
        guard session != nil, let input = VoiceInputSurface(rawValue: surface) else { return false }
        if picker != nil || menu != nil {
            dismissModal()
            previousX = x
            return true
        }
        if input == .gutter {
            clearHover()
            return false
        }
        previousX = x
        switch button {
        case VoiceQtButton.right:
            // Capture before any signal-producing step: the target is fixed from
            // live state, so nothing after the capture can drift it.
            guard let target = captureTarget(at: x) else { return true }
            openMenu(target, anchorX: x, anchorY: max(0, y))
            return true
        case VoiceQtButton.middle:
            clearHover()
            panRevision = session?.document.revision
            refreshInteractionPublished()
            return true
        case VoiceQtButton.left:
            clearHover()
            let hit = markerHit(at: x)
            guard let hit else {
                selectedIdentity = ""
                refreshInteractionPublished()
                projectMarkers(markerEntries())
                return true
            }
            let occurrence = VoiceOccurrence(hit)
            selectedIdentity = occurrence.text
            let target = VoiceChangesTransactions.capture(
                revision: session?.document.revision ?? 0,
                track: session?.selectedTrack ?? -1,
                tick: occurrence.tick,
                occurrence: occurrence)
            drag = VoiceChangesTransactions.drag(target: target, pressX: x)
            refreshInteractionPublished()
            projectMarkers(markerEntries())
            return true
        default:
            return false
        }
    }

    /// Drafts the frozen drag or pans the shared camera; otherwise resolves hover.
    /// Alt maps the drag preview to the clock lattice.
    @discardableResult
    func dispatchPointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        _ = y
        _ = buttons
        if var live = drag {
            if !live.active {
                guard abs(x - live.pressX) >= dragDistance else { return true }
                live.active = true
                clearHover()
            }
            let tick = snapTick(at: x, fine: modifiers & VoiceModifier.alt != 0)
            let changed = tick != live.previewTick
            live.previewTick = tick
            drag = live
            cursorKind = VoiceCursorKind.sizeHorizontal.rawValue
            if changed {
                projectMarkers(
                    markerEntries(),
                    reuseGeometry: true)
                publishTransient()
            }
            return true
        }
        if panRevision != nil {
            DrawerPan.moved(x: x, previousX: &previousX, session: session)
            return true
        }
        updateHover(at: x)
        return true
    }

    /// One release: the drag's only document mutation, and a pan's end.
    @discardableResult
    func dispatchPointerRelease(x: Double, y: Double, button: Int) -> Bool {
        guard let session else { return false }
        _ = y
        if button == VoiceQtButton.middle {
            cancelPan()
            publishHoverHintProfile(marker: markerHit(at: x) != nil)
            return true
        }
        guard button == VoiceQtButton.left, let live = drag else { return false }
        let mutation = VoiceChangesTransactions.move(
            live,
            revision: session.document.revision,
            track: currentTrack(session) ?? -1,
            points: lanePoints())
        cancelDrag()
        if let mutation { commit(mutation) }
        publishHoverHintProfile(marker: markerHit(at: x) != nil)
        return true
    }

    /// The pointer left: hover clears, a live gesture keeps its frozen state.
    func dispatchPointerLeave() {
        guard drag == nil, panRevision == nil else { return }
        clearHover()
    }

    /// One double-click: the legacy direct picker entry. It captures the same
    /// guarded target the context menu's own rows hand over.
    @discardableResult
    func dispatchPointerDoubleClick(x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        _ = y
        guard let target = captureTarget(at: x) else { return true }
        openPicker(target)
        return true
    }

    // MARK: Picker

    /// Draft filtering: presentation only, over the current bank's labels.
    func dispatchSetPickerFilter(text: String) {
        guard var live = picker else { return }
        let filter = String(text.prefix(64))
        guard filter != live.filter else { return }
        live.filter = filter
        live.program = pickerCache.filteredProgram(filter)
        picker = live
        publishPicker()
    }

    /// Row selection from the list's own press.
    func dispatchSelectPickerRow(index: Int) {
        guard let live = picker else { return }
        pickerCache.resolve(filter: live.filter)
        selectPickerProgram(pickerCache.program(at: index))
    }

    func dispatchPressAndHoldPickerRow(index: Int) {
        guard let live = picker, let session,
            VoiceChangesTransactions.isCurrent(
                live.target, revision: session.document.revision,
                track: session.selectedTrack ?? -1),
            pickerRowSnapshots.indices.contains(index)
        else {
            releasePickerAudition()
            return
        }
        let program = pickerRowSnapshots[index].program
        selectPickerProgram(program)
        pickerCache.hold(program: program, audition: onAuditionVoice)
    }

    func dispatchReleasePickerAudition() {
        pickerCache.release(audition: onAuditionVoice)
    }
    /// Arrow navigation over the filtered rows.
    func dispatchMovePickerSelection(delta: Int) {
        guard let live = picker else { return }
        pickerCache.resolve(filter: live.filter)
        if let program = pickerCache.movedProgram(from: live.program, delta: delta) {
            selectPickerProgram(program)
        }
    }

    /// Like VoicePicker::accept, an unmatched row writes nothing; blank slots remain valid.
    /// Revalidates the capture, replacing its exact occurrence or inserting at its empty tick.
    @discardableResult
    func dispatchAcceptPicker() -> Bool {
        guard let live = picker, live.program >= 0 else { return false }
        let selected = live.program
        let target = live.target
        let slotCount = slotViews().count
        cancelPicker()
        guard let session, let track = currentTrack(session),
            let mutation = VoiceChangesTransactions.picker(
                target,
                program: selected,
                slotCount: slotCount,
                revision: session.document.revision,
                track: track,
                points: session.projectionCache.lanePoints(track: track, lane: .voice))
        else { return false }
        commit(mutation)
        return true
    }

    /// Dismissal: capture, filter, row draft and current program drop without a
    /// write.
    func dispatchCancelPicker() {
        releasePickerAudition()
        guard picker != nil else { return }
        picker = nil
        pickerOpen = false
        pickerTitle = ""
        pickerFilter = ""
        pickerIndex = -1
        pickerHasMatch = false
        syncPickerRows([])
        refreshInteractionPublished()
    }

    // MARK: Context menu

    /// One typed row activation. Every path revalidates the captured
    /// document/track/point identity first, and a stale pick writes nothing.
    @discardableResult
    func dispatchActivateMenuAction(actionId: Int) -> Bool {
        guard let live = menu else { return false }
        dismissVoiceMenu()
        guard let session, let track = currentTrack(session),
            VoiceChangesTransactions.isCurrent(
                live.target, revision: session.document.revision, track: track)
        else { return false }
        switch actionId {
        case VoiceChangesPagePolicy.changeVoiceAction,
            VoiceChangesPagePolicy.insertVoiceChangeAction:
            openPicker(live.target)
            return true
        case VoiceChangesPagePolicy.deleteMarkerAction:
            guard
                let mutation = VoiceChangesTransactions.delete(
                    live.target,
                    revision: session.document.revision,
                    track: track,
                    points: session.projectionCache.lanePoints(track: track, lane: .voice))
            else { return false }
            commit(mutation)
            return true
        default:
            return false
        }
    }

    /// One rendered row activation by its published index: the page maps the row
    /// it published to its typed action, so no QML surface has to read a bridged
    /// row object back across the boundary.
    @discardableResult
    func dispatchActivateMenuRow(index: Int) -> Bool {
        let rows = menuRows.asArray
        guard rows.indices.contains(index) else { return false }
        return activateMenuAction(actionId: rows[index].actionId)
    }

    /// Outside dismissal and the menu's own Escape: no action, no write.
    func dispatchDismissVoiceMenu() {
        guard menu != nil else { return }
        menu = nil
        menuOpen = false
        syncModel(menuRows, [], matches: { $0.matches($1) })
        refreshInteractionPublished()
    }

    /// Dismisses whichever modal surface is open. The press that dismisses
    /// activates neither a row nor a slot.
    func dispatchDismissModal() {
        cancelPicker()
        dismissVoiceMenu()
    }

    // MARK: Internals: capture

    func currentTrack(_ session: DocumentSession) -> Int? {
        guard let track = session.selectedTrack, track >= 0,
            track < session.timeline.tracks.count
        else { return nil }
        return track
    }

    /// `VoiceChangeArea::captureTargetAt`: the marker under the press, or the
    /// snapped tick of the press itself.
    private func captureTarget(at x: Double) -> VoiceTarget? {
        guard let session, let track = currentTrack(session) else { return nil }
        let hit = markerHit(at: x)
        return VoiceChangesTransactions.capture(
            revision: session.document.revision,
            track: track,
            tick: hit?.tick ?? snapTick(at: x),
            occurrence: hit.map(VoiceOccurrence.init))
    }

    /// The page's only document-commit path. Transaction policy validates and
    /// drafts semantic edits; the document owner applies each through its
    /// existing lane operation and therefore remains the history owner.
    private func commit(_ mutation: VoiceLaneMutation) {
        guard let session else { return }
        switch mutation {
        case let .move(track, occurrence, tick):
            session.document.moveLanePoints(
                track: track, lane: .voice,
                moves: [
                    LanePointMove(
                        point: occurrence.point, tick: tick,
                        value: occurrence.value)
                ])
        case let .replace(track, occurrence, value):
            session.document.moveLanePoints(
                track: track, lane: .voice,
                moves: [
                    LanePointMove(
                        point: occurrence.point, tick: occurrence.tick,
                        value: value)
                ])
        case let .insert(track, tick, value):
            session.document.writeLane(
                track: track, lane: .voice, from: tick, through: tick,
                points: [LaneWrite(tick: tick, value: value)])
        case let .delete(track, occurrence):
            session.document.deleteLanePoints(
                track: track, lane: .voice, points: [occurrence.point])
        }
    }

    private func openPicker(_ target: VoiceTarget) {
        releasePickerAudition()
        let filter = ""
        let initial =
            target.occurrence?.value
            ?? VoiceLanePolicy.slot(
                firstProgram: firstProgram(), tick: target.tick,
                points: lanePoints())
        pickerCache.resolve(filter: filter)
        picker = VoiceChangesTransactions.openPicker(
            target: target, filter: filter, program: pickerCache.initialProgram(initial))
        pickerOpen = true
        pickerTitle = picker?.title ?? ""
        pickerFilter = filter
        refreshInteractionPublished()
        publishPicker()
    }

    private func openMenu(_ target: VoiceTarget, anchorX: Double, anchorY: Double) {
        menu = VoiceChangesTransactions.openMenu(target: target)
        menuOpen = true
        menuX = anchorX
        menuY = anchorY
        syncModel(
            menuRows, VoiceChangesProjection.menuRows(for: target), matches: { $0.matches($1) })
        refreshInteractionPublished()
    }

    // MARK: Internals: hover

    /// `VoiceChangeArea::updateHover`: a hovered marker publishes its own tick
    /// and no label; a background hover publishes the snapped tick's slot label.
    private func updateHover(at x: Double) {
        guard plotWidth > 0, plotHeight > 0, session != nil else {
            clearHover()
            return
        }
        let hit = markerHit(at: x)
        publishHoverHintProfile(marker: hit != nil)
        let pad = fontPx(baseFontPx, VoiceChangesPagePolicy.spaceOneFactor)
        if let hit {
            let identity = VoiceOccurrence(hit).text
            let lineX = xForTick(hit.tick)
            let labelX = lineX + pad
            let labelWidth = max(0, plotWidth - lineX)
            guard
                hoverIdentity != identity || hoverVisible || !hoverText.isEmpty
                    || hoverLabelX != labelX || hoverLabelY != 0
                    || hoverLabelWidth != labelWidth || hoverLabelHeight != plotHeight
            else { return }
            hoverIdentity = identity
            hoverTick = Double(hit.tick)
            hoverText = ""
            hoverVisible = false
            publishHoverLabel(x: labelX, y: 0, width: labelWidth, height: plotHeight)
            publishMarkerHover()
            return
        }
        let tick = snapTick(at: x)
        let slot = VoiceLanePolicy.slot(
            firstProgram: firstProgram(), tick: tick,
            points: lanePoints())
        let label = VoiceLanePolicy.hoverLabel(contextLabel(at: slot))
        guard !label.isEmpty else {
            clearHover()
            return
        }
        let lineX = xForTick(tick)
        hoverIdentity = nil
        hoverTick = Double(tick)
        publish(\.hoverText, label)
        publishHoverLabel(
            x: lineX + pad, y: 0, width: max(0, plotWidth - lineX),
            height: plotHeight)
        publish(\.hoverVisible, true)
        publishMarkerHover()
    }

    func clearHover() {
        publishHoverHintProfile(marker: false)
        guard hoverIdentity != nil || hoverVisible || !hoverText.isEmpty || hoverTick != 0
        else { return }
        hoverIdentity = nil
        hoverText = ""
        hoverVisible = false
        hoverTick = 0
        publishHoverLabel(x: 0, y: 0, width: 0, height: 0)
        publishMarkerHover()
    }

    private func publishHoverLabel(x: Double, y: Double, width: Double, height: Double) {
        publish(\.hoverLabelX, x)
        publish(\.hoverLabelY, y)
        publish(\.hoverLabelWidth, width)
        publish(\.hoverLabelHeight, height)
    }

    // MARK: Internals: gesture teardown

    func cancelDrag() {
        guard drag != nil else { return }
        drag = nil
        cursorKind = VoiceCursorKind.arrow.rawValue
        refreshInteractionPublished()
        projectMarkers(markerEntries())
        publishTransient()
    }

    func cancelPan() {
        guard panRevision != nil else { return }
        panRevision = nil
        refreshInteractionPublished()
    }

    /// Re-derives the published interaction gate from the page's own state.
    private func refreshInteractionPublished() {
        let active = drag != nil || panRevision != nil || picker != nil || menu != nil
        publish(\.interactionActive, active)
        publish(\.selectedIdentity, drag?.identity ?? selectedIdentity)
    }
}
