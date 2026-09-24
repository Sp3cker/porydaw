import PorydawCore
import QtBridge

// Automation lifecycle and owned-state application: the document-derived
// content rebuild, the preview/hover/prompt/selection application helpers,
// the context and interaction-state publications, and the body-scene
// application `configureBody` routes through. The bridge surface, stored
// state and entry points stay in AutomationPage.swift.

/// Mouse-hint profile IDs owned by the shared profile catalog.
enum AutomationHintProfile {
    static let empty = 0
    static let node = 15
    static let originPhantom = 16
    static let sweep = 17
    static let pencil = 18
}

@MainActor
extension AutomationPage {
    /// Rebuilds and applies the document-derived scene values before publishing
    /// primitives, preserving the page's lifecycle and publication order.
    func rebuildContent(selectionOnly: Bool = false) {
        let session = self.session
        let snapshot = session.map {
            AutomationSceneSnapshot.build(
                session: $0, cache: projectionFacts,
                selectedTrack: $0.selectedTrack,
                camera: $0.camera,
                activeParameterIndex: activeParameterIndex,
                ghostPins: ghostPins,
                selection: selection,
                plotWidth: plotWidth,
                plotHeight: plotHeight,
                devicePixelRatio: devicePixelRatio,
                baseFontPx: baseFontPx,
                geometry: geometry, laneRanges: laneRanges)
        } ?? .detached

        guard let active = snapshot.active else {
            parameterLabels = snapshot.parameterLabels
            rows = snapshot.rows
            ghostParameters = snapshot.ghostParameters
            ghostLabels = snapshot.ghostLabels
            selectedParameters = snapshot.selectedParameters
            scaleLabels = snapshot.scaleLabels
            projection = snapshot.projection
            publishTabs(snapshot.catalog)
            publishContent(nil)
            publishOverlays()
            publishReadoutGeometry()
            publishPrompt()
            publishMenuRows()
            publishInteractionState()
            return
        }

        activeParameterIndex = active.parameterIndex
        activeParameter = active.parameter
        trackAvailable = active.trackAvailable
        plotMessage = active.plotMessage
        parameterLabels = snapshot.parameterLabels
        rows = snapshot.rows
        ghostParameters = snapshot.ghostParameters
        ghostLabels = snapshot.ghostLabels
        selectedParameters = snapshot.selectedParameters
        projection = snapshot.projection
        scaleLabels = snapshot.scaleLabels
        publishTabs(snapshot.catalog)
        publishContent(session)
        contentBuildCount &+= 1
        if selectionOnly { selectionBuildCount &+= 1 }
        publishOverlays()
        publishReadoutGeometry()
        publishContext()
    }

    // MARK: Owned state application

    func applyPreviewDraft(_ draft: AutomationPreviewDraft) {
        previewPoints = draft.parameter == activeParameter ? draft.points : []
        previewText = draft.parameter == activeParameter ? draft.text : ""
    }

    @discardableResult
    func applyHover(_ next: AutomationHover?, countingPublication: Bool) -> Bool {
        guard next != hover else { return false }
        hover = next
        publishHoverHintProfile()
        if countingPublication { hoverBuildCount &+= 1 }
        return true
    }

    func hoverHintTargetAtPointer() -> AutomationHoverHintTarget? {
        guard hover != nil, let projection else { return nil }
        return AutomationHover.hintTarget(
            x: hoverX, y: hoverY, lane: projection,
            pointHitRadius: geometry.pointHitRadius)
    }

    func publishHoverHintProfile(
        targetOverride: AutomationHoverHintTarget? = nil,
        pencilModeOverride: Bool? = nil
    ) {
        let pencilMode = pencilModeOverride ?? isPencilMode
        let profile: Int
        if menu != nil {
            profile = AutomationHintProfile.empty
        } else if let hover {
            let target = targetOverride ?? hover.hintTarget
            switch (!pencilMode || hover.nodeMarkersVisible, target) {
            case (true, .originPhantom):
                profile = AutomationHintProfile.originPhantom
            case (true, .node):
                profile = AutomationHintProfile.node
            default:
                profile = pencilMode ? AutomationHintProfile.pencil
                    : AutomationHintProfile.sweep
            }
        } else {
            profile = AutomationHintProfile.empty
        }
        if hoverHintProfile != profile { hoverHintProfile = profile }
    }

    func applyPrompt(_ next: AutomationPromptTransaction?) {
        prompt = next
    }

    func shiftSelection(by delta: Int64) {
        guard let moved = shiftedAutomationSelection(selection, by: delta) else { return }
        selection = moved
    }

    /// Applies the plain context result in the same publication order as the
    /// cursor/playhead path that produced it.
    func publishContext() {
        let presentation = AutomationContextPresentation.resolve(
            editCursor: session?.editCursor,
            playing: playing,
            presentedTick: presentedTick,
            projection: projection,
            activeParameter: activeParameter,
            previousTick: contextTick,
            previousValue: contextValue)
        contextTick = presentation.tick
        contextValue = presentation.value
        if readoutText != presentation.readoutText {
            readoutText = presentation.readoutText
        }
        if readoutVisible != presentation.readoutVisible {
            readoutVisible = presentation.readoutVisible
        }
        if accessibleDescription != presentation.accessibleDescription {
            accessibleDescription = presentation.accessibleDescription
        }
        if presentation.contextChanged { contextChangeCount &+= 1 }
    }

    func publishInteractionState() {
        let active = AutomationInteractionActivity.resolve(
            hasGesture: gesture != nil,
            hasPrompt: prompt != nil,
            hasLaneDelete: laneDelete != nil,
            hasMenu: menu != nil,
            hasBand: band != nil,
            isPanning: panActive,
            hasTapSession: tapGuard != nil)
        let eligibilityChanged = interactionActive != active
            || publishedPointerGestureActive != pointerGestureActive
        if interactionActive != active { interactionActive = active }
        publishedPointerGestureActive = pointerGestureActive
        if eligibilityChanged { onCommandAvailabilityChanged?() }
    }

    func applyBodySceneConfiguration(_ configuration: AutomationBodySceneConfiguration) {
        plotWidth = configuration.plotWidth
        plotHeight = configuration.plotHeight
        devicePixelRatio = configuration.devicePixelRatio
        plotOrigin = configuration.plotOrigin
        dragDistance = configuration.dragDistance
        lastBodyOrigin = configuration.plotOrigin
        lastBodyDragDistance = configuration.dragDistance
        if configuration.fontChanged {
            baseFontPx = configuration.baseFontPx
            if let nextGeometry = configuration.geometry {
                geometry = nextGeometry
            }
            publishTypography()
        }
        if configuration.changed { rebuildContent() }
    }
}
