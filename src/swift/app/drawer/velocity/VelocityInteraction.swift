import PorydawCore

// Pointer, prompt and gesture machinery for the drawer's Velocity section: the
// four pointer entries, the local Escape and cancellation seam, the Set Velocity
// prompt, hover resolution, and the frozen gesture that previews, cancels and
// commits at most one document transaction per completed interaction.
//
// Ownership: an extension of the page, never a separate object. The Qt-facing
// methods stay declared on `VelocityPage` — `@QtBridgeable` registers class-body
// members only — and each one is a one-line forward into a `dispatch*` entry
// here. This file reads and writes the page's own gesture, prompt and hover state
// and publishes through the page's own apply paths: it holds no session, no cache
// and no bridge type of its own.

@MainActor
extension VelocityPage {
    // MARK: Page seam

    func dispatchEscape() -> Bool {
        if prompt != nil {
            cancelPrompt()
            return true
        }
        guard gesture != nil else { return false }
        cancelSectionInteraction()
        return true
    }

    func dispatchCancelSectionInteraction() {
        cancelGesture()
        cancelPrompt()
    }

    // MARK: Pointer input

    @discardableResult
    func dispatchPointerPress(x: Double, y: Double, surface: Int, button: Int,
                              modifiers: Int) -> Bool {
        guard let session, let input = VelocityInputSurface(rawValue: surface) else { return false }
        if prompt != nil { cancelPrompt() }
        if gesture != nil { cancelGesture() }
        selectionBeforePress = session.selectedNoteOrder
        pressedNote = nil
        switch input {
        case .ruler:
            guard button == VelocityQtButton.left, axis.inRuler(x: x, rulerWidth: rulerWidth)
            else { return false }
            guard !contextUnsupported else { return true }
            let unlock = detentsUnlocked(modifiers: modifiers, allowShift: false)
            let velocity = unlock
                ? Int(clampVelocity(axis.yToVelocity(y)))
                : axis.rulerVelocityAt(y: y, labelHeight: axis.geometry.labelHeight)
            guard velocity >= 1 else { return true }
            beginGesture(kind: .relative, x: x, y: y, detentUnlock: unlock,
                         notes: VelocityScene.selectedTrackNotes(session), modifiers: modifiers)
            guard gesture != nil else { return true }
            for note in gesture!.notes { gesture?.preview[note.noteID] = UInt8(velocity) }
            finishGesture(commit: !gesture!.preview.isEmpty)
        case .plot:
            if button == VelocityQtButton.middle {
                // The shared camera's pan, requested from the band that renders
                // its projection: one delta per move, clamped by the camera.
                beginGesture(kind: .pan, x: x, y: y, detentUnlock: false, notes: [],
                             modifiers: modifiers)
                return true
            }
            if button == VelocityQtButton.right {
                beginGesture(kind: .pendingBand, x: x, y: y, detentUnlock: false, notes: [],
                             modifiers: modifiers)
                if let hit = projection.hitTest(x: x, y: y, includeStems: true,
                                                handles: publishedHandles) {
                    pressedNote = hit
                }
                if let pressed = pressedNote, !isControl(modifiers),
                   !selectionBeforePress.contains(pressed)
                {
                    setSelection([pressed])
                }
                return true
            }
            guard button == VelocityQtButton.left else { return false }
            let unlock = detentsUnlocked(modifiers: modifiers, allowShift: true)
            if isShift(modifiers) {
                guard !contextUnsupported else { return true }
                beginGesture(kind: .ramp, x: x, y: y, detentUnlock: unlock,
                             notes: VelocityScene.selectedTrackNotes(session), modifiers: modifiers)
                updateRampPreview(x: x, y: y)
                return true
            }
            let hit = projection.hitTest(x: x, y: y, includeStems: true,
                                         handles: publishedHandles)
            pressedNote = hit
            if hit == nil {
                guard !contextUnsupported else { return true }
                beginGesture(kind: .paint, x: x, y: y, detentUnlock: unlock, notes: [],
                             modifiers: modifiers)
                paintBetween(fromX: x, fromY: y, toX: x, toY: y)
                return true
            }
            if isControl(modifiers) {
                var selection = selectionBeforePress
                if let hit, !selection.contains(hit) { selection.append(hit) }
                setSelection(selection)
            } else if let hit, !selectionBeforePress.contains(hit) {
                setSelection([hit])
            }
            // Selection is presentation state and stays available; the velocity
            // gesture itself needs the exact map, so an unknown context refuses
            // to freeze one.
            guard !contextUnsupported else { return true }
            beginGesture(kind: .relative, x: x, y: y, detentUnlock: unlock,
                         notes: VelocityScene.selectedTrackNotes(session), modifiers: modifiers)
        }
        return true
    }

    @discardableResult
    func dispatchPointerMove(x: Double, y: Double, buttons: Int) -> Bool {
        guard session != nil else { return false }
        _ = buttons
        guard gesture != nil else {
            updateHover(x: x, y: y)
            return true
        }
        switch gesture!.kind {
        case .relative:
            gesture?.bandX = x
            gesture?.bandY = y
            VelocityGesturePolicy.applyRelative(&gesture!, y: y)
            gesture?.previousX = x
            gesture?.previousY = y
            publishHandles(projectHandles())
        case .paint:
            paintBetween(fromX: gesture!.previousX, fromY: gesture!.previousY, toX: x, toY: y)
            gesture?.previousX = x
            gesture?.previousY = y
        case .ramp:
            updateRampPreview(x: x, y: y)
        case .pendingBand:
            if abs(x - gesture!.pressX) + abs(y - gesture!.pressY) >= dragDistance {
                gesture?.kind = .band
                gesture?.bandX = x
                gesture?.bandY = y
                updateBandPreview(x: x, y: y)
            }
        case .band:
            updateBandPreview(x: x, y: y)
        case .pan:
            let delta = x - gesture!.previousX
            gesture?.previousX = x
            gesture?.previousY = y
            if delta != 0, let session {
                session.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
        }
        return true
    }

    @discardableResult
    func dispatchPointerRelease(x: Double, y: Double, button: Int) -> Bool {
        guard session != nil, let live = gesture else { return false }
        if button == VelocityQtButton.middle {
            finishGesture(commit: false)
            return true
        }
        if button == VelocityQtButton.right {
            // The secondary release resolves the band selection and never
            // commits: a band replaces the selection (or extends it under the
            // modifier), and a stationary secondary press toggles the pressed
            // note or clears an empty selection.
            switch live.kind {
            case .band:
                var selection = live.controlPress ? selectionBeforePress : []
                for id in live.bandPreview where !selection.contains(id) { selection.append(id) }
                finishGesture(commit: false)
                setSelection(selection)
            case .pendingBand:
                if live.controlPress {
                    var selection = session?.selectedNoteOrder ?? []
                    if let pressed = pressedNote {
                        if selection.contains(pressed) {
                            selection.removeAll { $0 == pressed }
                        } else {
                            selection.append(pressed)
                        }
                    }
                    finishGesture(commit: false)
                    setSelection(selection)
                } else if pressedNote == nil {
                    finishGesture(commit: false)
                    setSelection([])
                } else {
                    finishGesture(commit: false)
                }
            default:
                finishGesture(commit: false)
            }
            return true
        }
        guard button == VelocityQtButton.left else { return true }
        switch live.kind {
        case .paint:
            let commit = !live.notes.isEmpty && !live.preview.isEmpty
            if !commit { setSelection([]) }
            finishGesture(commit: commit)
        case .ramp:
            finishGesture(commit: live.previousX != live.pressX || live.previousY != live.pressY)
        case .relative:
            if !live.relativeActivated {
                if live.controlPress {
                    var selection = selectionBeforePress
                    if let pressed = pressedNote {
                        if selection.contains(pressed) {
                            selection.removeAll { $0 == pressed }
                        } else {
                            selection.append(pressed)
                        }
                    }
                    setSelection(selection)
                } else if let pressed = pressedNote {
                    setSelection([pressed])
                } else {
                    setSelection([])
                }
            }
            finishGesture(commit: live.relativeActivated)
        case .pendingBand, .band, .pan:
            finishGesture(commit: false)
        }
        return true
    }

    func dispatchPointerLeave() {
        hovered = nil
        guard gesture == nil else { return }
        refreshAxisAndHandles()
    }

    // MARK: Prompt

    @discardableResult
    func dispatchOpenSelectedVelocityPrompt() -> Bool {
        guard let session, !contextUnsupported else { return false }
        let notes = VelocityScene.selectedTrackNotes(session)
        guard !notes.isEmpty else { return false }
        cancelGesture()
        let ids = notes.map(\.id)
        let before = notes.map(\.velocity)
        let initial = Int(notes[0].velocity)
        prompt = VelocityPromptState(revision: session.document.revision,
                                     track: session.selectedTrack ?? -1,
                                     noteIDs: ids, beforeValues: before, initialValue: initial,
                                     draft: String(initial))
        setPublished(&promptOpen, true)
        setPublished(&promptDraft, String(initial))
        setPublished(&promptError, "")
        setPublished(&promptInitialValue, initial)
        refreshInteractionPublished()
        publishHandles(projectHandles())
        return true
    }

    func dispatchUpdatePromptDraft(draft text: String) {
        guard var live = prompt else { return }
        live.draft = String(text.prefix(4))
        live.error = VelocityPromptPolicy.error(draft: live.draft)
        prompt = live
        setPublished(&promptDraft, live.draft)
        setPublished(&promptError, live.error)
    }

    @discardableResult
    func dispatchAcceptPrompt() -> Bool {
        guard let session, let live = prompt else { return false }
        guard let value = VelocityPromptPolicy.value(draft: live.draft) else {
            setPublished(&promptError, VelocityPromptPolicy.error(draft: live.draft))
            return false
        }
        prompt = nil
        setPublished(&promptOpen, false)
        setPublished(&promptDraft, "")
        setPublished(&promptError, "")
        refreshInteractionPublished()
        defer { publishHandles(projectHandles()) }
        guard live.revision == session.document.revision,
              live.track == (session.selectedTrack ?? -1)
        else { return false }
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(live.noteIDs.count)
        for id in live.noteIDs {
            guard session.projectionCache.note(id, in: live.track) != nil else { return false }
            updates.append(NoteVelocity(noteID: id, velocity: value))
        }
        guard !updates.isEmpty else { return false }
        commitVelocities(updates, expectedRevision: live.revision)
        onVelocityAccepted?(UInt8(value))
        return true
    }

    func dispatchCancelPrompt() {
        guard prompt != nil else { return }
        prompt = nil
        setPublished(&promptOpen, false)
        setPublished(&promptDraft, "")
        setPublished(&promptError, "")
        refreshInteractionPublished()
        publishHandles(projectHandles())
    }

    // MARK: Gesture plumbing

    func promptRevisionMismatch(_ session: DocumentSession) -> Bool {
        guard let prompt else { return false }
        return prompt.revision != session.document.revision
            || prompt.track != (session.selectedTrack ?? -1)
    }

    private func isShift(_ modifiers: Int) -> Bool {
        modifiers & VelocityModifier.shift != 0
    }

    private func isControl(_ modifiers: Int) -> Bool {
        modifiers & VelocityModifier.control != 0
    }

    /// `keymap::Registry::matchesModifier`: the binding is exactly Control, with
    /// Shift admitted only where production admits it (`allowShift`).
    private func detentUnlocked(modifiers: Int, allowShift: Bool) -> Bool {
        KeybindingRegistry().matchesModifier(
            modifiers, "velocity.detent_unlock", allowShift: allowShift)
    }

    /// The page's whole unlock rule: a disabled detent set unlocks everything,
    /// otherwise the held modifier decides. `VelocityArea::detentsUnlocked`.
    private func detentsUnlocked(modifiers: Int, allowShift: Bool) -> Bool {
        !detentsEnabled || detentUnlocked(modifiers: modifiers, allowShift: allowShift)
    }

    /// Re-derives the published interaction gate from the page's own state.
    func refreshInteractionPublished() {
        let active = gesture != nil || prompt != nil
        if interactionActive != active { interactionActive = active }
    }

    func dispatchSetUseDetents(enabled: Bool) {
        guard detentsEnabled != enabled else { return }
        cancelGesture()
        detentsEnabled = enabled
        refreshAxisAndHandles()
    }

    func dispatchToggleDetents() {
        setUseDetents(enabled: !detentsEnabled)
    }

    private func beginGesture(kind: VelocityGestureKind, x: Double, y: Double,
                              detentUnlock: Bool, notes: [Note], modifiers: Int) {
        paintCandidates = kind == .paint ? VelocityScene.selectedTrackNotes(session) : []
        gesture = VelocityGestureState(
            kind: kind, revision: session?.document.revision ?? 0,
            track: session?.selectedTrack ?? -1, notes: freeze(notes), axis: axis,
            detentUnlock: detentUnlock, activationDistance: geometry.dragActivationDistance,
            pressX: x, pressY: y, controlPress: isControl(modifiers))
        refreshInteractionPublished()
        publishHandles(projectHandles())
    }

    private func freeze(_ notes: [Note]) -> [VelocityFrozenNote] {
        let resolve = VelocityScene.contextResolver(session)
        return notes.map { freeze($0, map: resolve($0.tick, Int($0.pitch)).map) }
    }

    private func freeze(_ note: Note, map: VelocityMap) -> VelocityFrozenNote {
        VelocityFrozenNote(noteID: note.id, tick: note.tick, duration: note.duration,
                           pitch: note.pitch, velocity: note.velocity,
                           map: map, exactOrigin: note.velocity)
    }

    private func cancelGesture() {
        guard let gesture else { return }
        let selectionBefore = selectionBeforePress
        self.gesture = nil
        paintCandidates = []
        pressedNote = nil
        selectionBeforePress = []
        if let session, gesture.track == (session.selectedTrack ?? -1),
           session.selectedNoteOrder != selectionBefore {
            session.setSelectedNotes(selectionBefore)
        }
        refreshInteractionPublished()
        publishHandles(projectHandles())
        publishTransient()
    }

    /// Release: one semantic document operation, or none when the gesture
    /// committed nothing or its captured revision moved under it.
    private func finishGesture(commit: Bool) {
        guard let live = gesture else { return }
        gesture = nil
        paintCandidates = []
        pressedNote = nil
        selectionBeforePress = []
        if commit, let session, live.revision == session.document.revision {
            commitVelocities(VelocityGesturePolicy.updates(live),
                             expectedRevision: live.revision)
        }
        refreshInteractionPublished()
        publishHandles(projectHandles())
        publishTransient()
    }

    /// The page's single document-commit path. Transaction policies only build
    /// frozen payloads; document ownership and history stay with the session.
    private func commitVelocities(_ updates: [NoteVelocity], expectedRevision: UInt64) {
        guard let session, !updates.isEmpty else { return }
        _ = session.document.setVelocities(updates, expectedRevision: expectedRevision)
    }

    private func setSelection(_ ids: [NoteID]) {
        guard let session else { return }
        session.setSelectedNotes(ids)
        rebuildContent()
    }

    private func updateRampPreview(x: Double, y: Double) {
        guard gesture != nil else { return }
        let camera = session?.camera
        let dpr = devicePixelRatio
        VelocityGesturePolicy.applyRamp(&gesture!, x: x, y: y, hitRadius: geometry.hitRadius) { note in
            camera?.displayX(tick: Double(note.tick), origin: 0, dpr: dpr) ?? 0
        }
        gesture?.previousX = x
        gesture?.previousY = y
        publishHandles(projectHandles())
        publishTransient()
    }

    /// One paint step. The first step freezes the selection; later steps add the
    /// notes the swept column reaches, exactly like `paintSelectedNodesBetween`.
    private func paintBetween(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        guard gesture != nil else { return }
        let radius = geometry.hitRadius
        let deltaX = toX - fromX
        let resolve = VelocityScene.contextResolver(session)
        for note in paintCandidates where gesture?.frozenNote(note.id) == nil {
            let x = projection.xForDisplayTick(Double(note.tick))
            let inSpan = deltaX == 0
                ? abs(x - toX) <= radius
                : (x >= min(fromX, toX) - radius && x <= max(fromX, toX) + radius)
            if inSpan {
                gesture?.append(freeze(note, map: resolve(note.tick, Int(note.pitch)).map))
            }
        }
        guard !gesture!.notes.isEmpty else { return }
        let updates = VelocityGesturePolicy.paint(
            axis: gesture!.axis, detentUnlock: gesture!.detentUnlock,
            candidates: gesture!.notes.map {
                (note: $0, x: projection.xForDisplayTick(Double($0.tick)))
            },
            from: (fromX, fromY), to: (toX, toY), hitRadius: radius)
        guard !updates.isEmpty else { return }
        for update in updates { gesture?.preview[update.noteID] = UInt8(update.velocity) }
        publishHandles(projectHandles())
    }

    private func updateBandPreview(x: Double, y: Double) {
        guard var live = gesture else { return }
        live.bandX = x
        live.bandY = y
        let minX = min(live.pressX, x)
        let maxX = max(live.pressX, x)
        let minY = min(live.pressY, y)
        let maxY = max(live.pressY, y)
        let radius = geometry.hitRadius
        var hits: [NoteID] = []
        for handle in publishedHandles {
            let x0 = handle.x - radius
            let y0 = handle.y - radius
            if x0 + 2 * radius >= minX, x0 <= maxX, y0 + 2 * radius >= minY, y0 <= maxY {
                hits.append(handle.noteID)
            }
        }
        live.bandPreview = hits
        gesture = live
        publishHandles(projectHandles())
        publishTransient()
    }

    private func updateHover(x: Double, y: Double) {
        let hit = projection.hitTest(x: x, y: y, includeStems: false,
                                     handles: publishedHandles)
        guard hit != hovered else { return }
        hovered = hit
        refreshAxisAndHandles()
    }
}
