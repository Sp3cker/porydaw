import QtBridge

struct VoiceChangesPublicationScope: OptionSet, Sendable {
    let rawValue: Int

    static let content = Self(rawValue: 1 << 0)
    static let markers = Self(rawValue: 1 << 1)
    static let hover = Self(rawValue: 1 << 2)
    static let transient = Self(rawValue: 1 << 3)
    static let modal = Self(rawValue: 1 << 4)
    static let interaction = Self(rawValue: 1 << 5)
    static let readout = Self(rawValue: 1 << 6)
    static let clear = Self(rawValue: 1 << 7)
    static let capability = Self(rawValue: 1 << 8)
    static let typography = Self(rawValue: 1 << 9)
    static let projection = Self(rawValue: 1 << 10)
}

@MainActor
extension VoiceChangesPage {
    /// The only Voice Changes publication entry. It builds/reuses plain scene
    /// blocks, reconciles value descriptors into stable Qt models, and assigns
    /// every scalar only when its value changed.
    @QtIgnored
    func publish(_ scope: VoiceChangesPublicationScope) {
        guard !scope.isEmpty else { return }
        let publishedState = state
        let capabilityAvailable = onAuditionVoice != nil
        var next = sceneCache
        var spanProjectionChanged = false
        if scope.contains(.clear) {
            next = .detached
        } else if scope.contains(.content) {
            contentBuildCount &+= 1
            next = VoiceChangesScene.build(sceneInput(
                refreshTypography: scope.contains(.typography)))
        } else {
            if scope.contains(.projection) {
                let input = sceneInput()
                let entries = VoiceChangesScene.projectedEntries(input.entries, state: state)
                next.entries = entries
                next.markers = VoiceChangesScene.markerValues(input, entries: entries)
                next.spans = VoiceChangesScene.spanValues(input, entries: entries)
                spanProjectionChanged = true
                next.gridLines = VoiceChangesScene.gridValues(input)
                next.hover = VoiceChangesScene.hoverValue(state)
                next.transient = VoiceChangesScene.transientValue(state)
            } else if scope.contains(.markers) {
                let input = sceneInput()
                let entries = VoiceChangesScene.projectedEntries(input.entries, state: state)
                let entriesChanged = next.entries != entries
                next.entries = entries
                next.markers = VoiceChangesScene.markerValues(input, entries: entries)
                if entriesChanged {
                    next.spans = VoiceChangesScene.spanValues(input, entries: entries)
                    spanProjectionChanged = true
                }
            }
            if scope.contains(.hover) {
                next.hover = VoiceChangesScene.hoverValue(state)
            }
            if scope.contains(.transient) {
                next.transient = VoiceChangesScene.transientValue(state)
            }
            if scope.contains(.readout) {
                next.readout = VoiceChangesScene.readoutValue(state)
            }
            if scope.contains(.modal) {
                next.modal = VoiceChangesScene.modalValues(state)
            }
        }
        sceneCache = next

        let content = scope.contains(.content) || scope.contains(.clear)
        if content { publishBody(state: publishedState) }
        if content || scope.contains(.markers) || scope.contains(.projection) {
            publishMarkers(next.markers)
        }
        if content || scope.contains(.projection) || spanProjectionChanged {
            publishSpans(next.spans)
        }
        if content || scope.contains(.projection) { publishGrid(next.gridLines) }
        if content { publishGutter(next.gutterTexts) }
        if scope.contains(.capability) {
            setPublished(&auditionAvailable, capabilityAvailable)
            setPublished(&auditionDiagnostic,
                         capabilityAvailable ? "" : "Voice audition is unavailable.")
        }
        if content || scope.contains(.readout) { publishReadout(next.readout) }
        if content || scope.contains(.hover) || scope.contains(.projection) {
            publishHover(next.hover)
        }
        if content || scope.contains(.transient) || scope.contains(.projection) {
            publishTransient(next.transient)
        }
        if content || scope.contains(.modal) { publishModal(next.modal) }
        if content || scope.contains(.interaction) { publishInteraction(publishedState) }
        if content { setPublished(&trackAvailable, next.trackAvailable) }
    }

    private func sceneInput(refreshTypography: Bool = false) -> VoiceChangesSceneInput {
        let entries = markerEntries()
        let font = state.view?.baseFontPx ?? baseFontPx
        let type: VoiceTypographyValues
        if !refreshTypography, let typographySnapshot {
            type = typographySnapshot
        } else {
            type = typography.values(
                baseFontPx: font,
                labels: VoiceChangesScene.measurementLabels(entries: entries, bank: state.bank))
            typographySnapshot = type
        }
        let track = state.lane.track ?? 0
        return VoiceChangesSceneInput(
            state: state,
            entries: entries,
            palette: VoiceScenePalette(
                primaryText: palette.primaryText,
                secondaryText: palette.secondaryText,
                gridLineSub1: palette.gridLineSub1,
                gridLineSub2: palette.gridLineSub2,
                gridLineSub3: palette.gridLineSub3,
                gridLineBar: palette.gridLineBar,
                gridLineBeat: palette.gridLineBeat,
                gridLineBeatFine: palette.gridLineBeatFine,
                heldSpan: PaletteMath.hex(PaletteMath.trackIdentityOklab(track), alpha: 18),
                markerLine: PaletteMath.trackIdentityFills[
                    PaletteMath.trackIdentityIndex(track)]),
            typography: type,
            gutterTitle: gutterTitle)
    }

    private func publishBody(state publishedState: borrowing VoiceChangesState) {
        let view = publishedState.view
        setPublished(&plotOrigin, view?.plotOrigin ?? 0)
        setPublished(&plotWidth, view?.plotWidth ?? 0)
        setPublished(&plotHeight, view?.plotHeight ?? 0)
        setPublished(&devicePixelRatio, view?.devicePixelRatio ?? 1)
        let font = view?.baseFontPx ?? baseFontPx
        setPublished(&baseFontPx, font)
        setPublishedVariant(&promptAppearance, PromptAppearance.metrics(base: font))
        setPublishedVariant(&promptFont, PromptAppearance.font(base: font))
        let type = typographySnapshot
            ?? typography.values(baseFontPx: font, labels: ["No voice"])
        setPublishedVariant(&captionFont, type.captionFont.map)
        setPublishedVariant(&titleFont, type.titleFont.map)
    }

    /// Structural rows are published before the booleans and indexes that make
    /// their corresponding surfaces active.
    private func publishSpans(_ values: borrowing [DrawerRectValue]) {
        syncModel(heldSpans, previous: &spanRows, values) {
            VoiceChangesPresentation.rect($0)
        }
    }

    private func publishGrid(_ values: borrowing [DrawerRectValue]) {
        syncModel(gridLines, previous: &gridRows, values) {
            VoiceChangesPresentation.rect($0)
        }
    }

    private func publishGutter(_ values: borrowing [DrawerTextValue]) {
        syncModel(gutterTexts, previous: &gutterRows, values) {
            VoiceChangesPresentation.text($0)
        }
    }

    private func publishMarkers(_ values: borrowing [VoiceMarkerValue]) {
        syncModel(markers, previous: &markerRows, values) { VoiceMarkerHandle($0) }
    }

    private func publishReadout(_ value: borrowing VoiceReadoutValue) {
        setPublished(&contextSlot, value.slot)
        setPublished(&contextBlank, value.blank)
        setPublished(&contextSymbol, value.symbol)
        setPublished(&readoutText, value.text)
        setPublishedRect(&readoutRect, value.rect)
        setPublished(&readoutVisible, sceneCache.trackAvailable)
    }

    private func publishHover(_ value: borrowing VoiceHoverValue) {
        setPublished(&hoverText, value.text)
        setPublishedRect(&hoverLabelRect, value.rect)
        setPublished(&hoverTick, Double(value.tick))
        setPublished(&hoverHintProfile,
                     value.marker ? VoiceHintProfile.marker : VoiceHintProfile.horizontalScroll)
        setPublished(&hoverVisible, value.visible)
    }

    private func publishTransient(_ value: borrowing VoiceTransientValue) {
        setPublished(&previewX, value.x)
        setPublished(&previewTick, Double(value.tick))
        setPublished(&previewVisible, value.visible)
    }

    private func publishModal(_ value: borrowing VoiceModalValues) {
        syncModel(pickerRows, previous: &pickerRowDescriptors, value.pickerRows) {
            VoicePickerRowHandle($0)
        }
        syncModel(menuRows, previous: &menuRowDescriptors, value.menuRows) {
            VoiceMenuRowHandle($0)
        }
        setPublished(&pickerTitle, value.pickerTitle)
        setPublished(&pickerFilter, value.pickerFilter)
        setPublished(&pickerHasMatch, value.pickerHasMatch)
        setPublished(&menuX, value.menuX)
        setPublished(&menuY, value.menuY)
        setPublished(&pickerOpen, value.pickerOpen)
        setPublished(&pickerIndex, value.pickerIndex)
        setPublished(&menuOpen, value.menuOpen)
    }

    private func publishInteraction(_ publishedState: borrowing VoiceChangesState) {
        setPublished(&selectedIdentity,
                     publishedState.pointerMode.drag?.identity
                         ?? publishedState.selectedOccurrence?.text ?? "")
        setPublished(&cursorKind, publishedState.pointerMode.activeDrag == nil ? 0 : 3)
        setPublished(&interactionActive, publishedState.interactionActive)
    }

    @QtIgnored
    func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }

    @QtIgnored
    func setPublishedRect(_ storage: inout [String: QVariantSettable],
                          _ value: borrowing DrawerRectValue) {
        let next = VoiceMarkerHandle.rect(value.x, value.y, value.width, value.height)
        if !VoiceMarkerHandle.rectMatches(storage, next) { storage = next }
    }

    @QtIgnored
    func setPublishedVariant(_ storage: inout [String: QVariantSettable],
                             _ value: [String: QVariantSettable]) {
        guard storage.count != value.count || storage.contains(where: { key, current in
            guard let next = value[key] else { return true }
            return String(describing: current) != String(describing: next)
        }) else { return }
        storage = value
    }
}
