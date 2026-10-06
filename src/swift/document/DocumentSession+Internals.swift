import Foundation
import PorydawCore
import PorydawProject

@MainActor
extension DocumentSession {

    // MARK: - Internals

    internal func requireOpen() throws {
        if isClosed {
            throw ProjectServiceError.serviceClosed
        }
    }

    internal func adoptBank(_ result: AppliedBankEdit) {
        let next = service.bankViews.state(for: result)
        if next !== sharedBank {
            sharedBank.detach(self)
            sharedBank = next
            next.attach(self)
        }
        service.bankViews.publish(result)
    }

    internal func sharedBankDidChange(_ state: SharedBankState) {
        guard !isClosed, state === sharedBank else { return }
        if bankPersistenceInFlight || document.history.bankTransitionInFlight {
            pendingBankNotification = true
        } else {
            publishChange([.bank, .dirty])
        }
    }

    internal func flushPendingBankNotification() {
        guard pendingBankNotification, !isClosed else { return }
        pendingBankNotification = false
        publishChange([.bank, .dirty])
    }

    internal func publishChange(
        _ domains: SessionChangeDomains,
        trackRemap: TrackRemap? = nil,
        editEffects: DocumentEditEffects = DocumentEditEffects()
    ) {
        guard !domains.isEmpty else { return }
        if stateChangeDepth > 0 {
            pendingDomains.formUnion(domains)
            pendingEditEffects.formUnion(editEffects)
            if let trackRemap {
                pendingTrackRemap =
                    pendingTrackRemap.map {
                        composeTrackRemaps($0, followedBy: trackRemap)
                    } ?? trackRemap
            }
            return
        }
        if domains.contains(.selection) { emitSelectionTransition() }
        onChange?(
            SessionChange(
                revision: document.revision,
                trackRemap: trackRemap,
                domains: domains, editEffects: editEffects))
    }

    internal func flushStateChanges() {
        guard !pendingDomains.isEmpty else { return }
        let domains = pendingDomains
        let trackRemap = pendingTrackRemap
        let editEffects = pendingEditEffects
        pendingDomains = []
        pendingTrackRemap = nil
        pendingEditEffects = DocumentEditEffects()
        if domains.contains(.selection) { emitSelectionTransition() }
        onChange?(
            SessionChange(
                revision: document.revision,
                trackRemap: trackRemap,
                domains: domains, editEffects: editEffects))
    }

    private func emitSelectionTransition() {
        let previous = publishedTrackTime
        let next = trackTimeSelection
        publishedTrackTime = next
        let transition = SelectionTransition(previousTrackTime: previous, trackTime: next)
        for observer in Array(selectionTransitionObservers.values) {
            observer(transition)
        }
    }

    /// A batch may contain successive structural document mutations. Compose
    /// their old-to-new mappings instead of publishing an ambiguous last remap.
    private func composeTrackRemaps(
        _ first: TrackRemap,
        followedBy second: TrackRemap
    ) -> TrackRemap {
        let chunks = first.chunkMap.map { intermediate -> Int? in
            guard let intermediate, second.chunkMap.indices.contains(intermediate) else {
                return nil
            }
            return second.chunkMap[intermediate]
        }
        let tracks = first.engineTrackMap.map { intermediate -> Int? in
            guard let intermediate,
                second.engineTrackMap.indices.contains(intermediate)
            else {
                return nil
            }
            return second.engineTrackMap[intermediate]
        }
        return TrackRemap(
            chunkMap: chunks, engineTrackMap: tracks,
            newChunkCount: second.newChunkCount,
            newEngineTrackCount: second.newEngineTrackCount)
    }

    /// Repairs playback and cached reads before viewport callbacks, then reconciles
    /// selection and publishes the completed document transition.
    internal func handleDocumentChange(_ change: DocumentChange) {
        withStateChanges {
            let nextTimeline = timelineBuilder.build(state: document.state, sampleRate: timeline.sampleRate)
            let reconciledChange = change.reconcilingPlaybackBounds(from: timeline, to: nextTimeline)
            timeline = consume nextTimeline
            projectionCache.documentDidChange(reconciledChange)
            if let remap = change.trackRemap {
                onViewportRepair?(.trackRemap(remap))
            }
            let priorScope = selectedTracks
            let priorPrimary = selectedTrack
            let priorNotes = selectedNoteOrder
            let priorTimeSelection = timeSelection
            let survivingSelection = selectedNoteOrder.filter { document.note($0) != nil }
            if survivingSelection.count != selectedNoteOrder.count {
                selectedNoteOrder = survivingSelection
                selectedNotes = Set(survivingSelection)
                publishChange([.selection])
            }
            if let remap = change.trackRemap {
                // Session playback masks follow engine-track identity through edits
                // and the inverse remaps history publishes on undo.
                mutedTracks = Set(
                    mutedTracks.compactMap { track in
                        remap.engineTrackMap.indices.contains(track)
                            ? remap.engineTrackMap[track] : nil
                    })
                soloedTracks = Set(
                    soloedTracks.compactMap { track in
                        remap.engineTrackMap.indices.contains(track)
                            ? remap.engineTrackMap[track] : nil
                    })
            }
            if let remap = change.trackRemap {
                let mappedPrimary = priorPrimary.flatMap { track -> Int? in
                    guard remap.engineTrackMap.indices.contains(track) else { return nil }
                    return remap.engineTrackMap[track]
                }
                let primaryDeleted = priorPrimary != nil && mappedPrimary == nil
                let nextPrimary =
                    mappedPrimary
                    ?? priorPrimary.map {
                        min($0, max(0, document.engineTracks.usedTrackCount - 1))
                    }
                changingPrimaryInternally = true
                selectedTrack = nextPrimary
                changingPrimaryInternally = false
                selectedTracks = Set(
                    priorScope.compactMap { track in
                        remap.engineTrackMap.indices.contains(track)
                            ? remap.engineTrackMap[track] : nil
                    })
                if let selectedTrack { selectedTracks.insert(selectedTrack) }
                if var selection = timeSelection {
                    switch selection.scope {
                    case let .tracks(stored):
                        if primaryDeleted {
                            timeSelection = nil
                        } else {
                            var mapped = Set(
                                stored.compactMap { track -> Int? in
                                    if remap.engineTrackMap.indices.contains(track) {
                                        return remap.engineTrackMap[track]
                                    }
                                    return (0..<16).contains(track) ? track : nil
                                })
                            if let selectedTrack { mapped.insert(selectedTrack) }
                            selection.scope = .tracks(mapped)
                            timeSelection = selection
                            selectedTracks = Set(
                                mapped.filter {
                                    (0..<document.engineTracks.usedTrackCount).contains($0)
                                })
                        }
                    case .lanes:
                        selection.lanes = Set(
                            selection.lanes.compactMap { parameter -> AutomationParameter? in
                                guard let track = parameter.track,
                                    remap.engineTrackMap.indices.contains(track),
                                    let destination = remap.engineTrackMap[track]
                                else { return nil }
                                if case let .controlChange(_, controller) = parameter {
                                    return .controlChange(track: destination, controller: controller)
                                }
                                return .pitchBend(track: destination)
                            })
                        timeSelection = selection.lanes.isEmpty && !selection.tempo ? nil : selection
                    }
                }
            }
            onViewportRepair?(.scaleFold)
            onViewportRepair?(.timeDomain)
            onPlayback?(timeline)
            var domains: SessionChangeDomains = [.document, .dirty, .history]
            if selectedNoteOrder != priorNotes || selectedTrack != priorPrimary
                || selectedTracks != priorScope || timeSelection != priorTimeSelection
            {
                domains.insert(.selection)
            }
            publishChange(domains, trackRemap: change.trackRemap, editEffects: reconciledChange.editEffects)
        }
    }
}
