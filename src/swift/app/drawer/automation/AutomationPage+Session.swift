import Foundation
import PorydawCore
import PorydawDocument
import QtBridge

@MainActor
extension AutomationPage {
    // MARK: Check-facing state

    @QtIgnored public var hasGesture: Bool { gesture != nil }
    @QtIgnored public var hasPrompt: Bool { prompt != nil }
    @QtIgnored public var hasMenu: Bool { menu != nil }
    @QtIgnored public var hasBand: Bool { band != nil }
    @QtIgnored public var isPanning: Bool { panActive }
    @QtIgnored public var isDraggingNodes: Bool { if case .node = gesture { return true }; return false }
    @QtIgnored public var isSweeping: Bool { if case .sweep = gesture { return true }; return false }
    @QtIgnored public var isPainting: Bool { if case .pencil = gesture { return true }; return false }
    @QtIgnored public var laneCount: Int { projection?.eventCount ?? 0 }
    @QtIgnored public var hasClipboard: Bool { clipboard.read() != nil }
    @QtIgnored public var frozenRevision: UInt64? { frozen?.revision }
    @QtIgnored public var menuRowActions: [Int] { menu?.rows.map(\.actionId) ?? [] }
    @QtIgnored public var menuTargetIsPoint: Bool { if case .point = menu?.target { return true }; return false }
    @QtIgnored public var promptForExistingNode: Bool { prompt?.forExistingNode ?? false }
    @QtIgnored public var tapTempoSession: AutomationTapTempoSession { tapSession }
    @QtIgnored public var publishedTabs: [AutomationTabHandle] { tabSnapshots }
    @QtIgnored public var publishedNodes: [AutomationNodeHandle] { nodeSnapshots }
    @QtIgnored public var publishedMenuRows: [AutomationMenuRowHandle] { menuRowSnapshots }

    /// The first catalog index whose parameter satisfies `predicate`, so a lane
    /// reads the same selector order the page publishes.
    @QtIgnored
    public func firstCatalogIndex(matching predicate: (AutomationParameter) -> Bool) -> Int? {
        AutomationCatalog.parameters(track: activeTrack() ?? 0)
            .firstIndex(where: predicate)
    }

    /// One catalog index's written-event count, read from the current document.
    @QtIgnored
    public func catalogEventCount(_ parameter: AutomationParameter) -> Int {
        guard let session else { return 0 }
        return projectionFacts.snapshot(parameter, session: session).eventCount
    }

    /// The ghost-pinned catalog indexes, comma-separated, in selector order.
    @QtIgnored public var firstGhostText: String {
        let track = activeTrack() ?? 0
        return AutomationCatalog.parameters(track: track).enumerated()
            .filter { ghostParameters.contains($0.element) }
            .map { String($0.offset) }
            .joined(separator: ",")
    }

    /// The live document revision the owner reads: the fact a refused or
    /// cancelled interaction must leave untouched.
    @QtIgnored public var documentRevision: UInt64 { session?.document.revision ?? 0 }

    /// The selected track the page presents, or `nil` while none is.
    @QtIgnored public var activeTrackIndex: Int? { activeTrack() }

    /// The written-event count of one track's active parameter, read from the
    /// current document exactly as the row stack reads it.
    @QtIgnored
    public func laneEventCount(track: Int) -> Int {
        guard let session, let lane = activeParameter.lane else {
            return activeParameter.isTempo ? session?.document.state.tempo.count ?? 0 : 0
        }
        return session.document.lanePoints(track: track, lane: lane).count
    }

    /// The active parameter's written-event ticks in the current document.
    @QtIgnored public var activeLaneTicks: [Tick] {
        guard let session else { return [] }
        return projectionFacts.snapshot(activeParameter, session: session).sources.map(\.tick)
    }

    /// The active parameter's written `tick:value` pairs, in document order.
    @QtIgnored public var activeLaneValues: [String] {
        guard let session else { return [] }
        return projectionFacts.snapshot(activeParameter, session: session)
            .sources.map { "\($0.tick):\($0.value)" }
    }

    /// The selector index of one parameter in the current catalog, or -1.
    @QtIgnored
    public func catalogIndex(of parameter: AutomationParameter) -> Int {
        AutomationCatalog.parameters(track: activeTrack() ?? 0).firstIndex(of: parameter) ?? -1
    }

    /// The document's tick-zero tempo in whole BPM, or `nil` when it has none.
    @QtIgnored public var tempoBpmAtTickZero: Int? {
        guard let session,
            let point = session.document.state.tempo.first(where: { $0.tick == 0 })
        else {
            return nil
        }
        return Int(
            TimeDefaults.tempoBPM(
                forMicrosecondsPerQuarterNote: point.microsecondsPerQuarterNote
            ).rounded())
    }

    /// Whether the accepted clipboard holds points for the active parameter, which
    /// is exactly the lane menu's Paste availability.
    @QtIgnored public var laneClipAvailable: Bool { laneClipPoints(activeParameter) != nil }

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication precedes the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        if let selectionTransitionToken, let previousSession = self.session {
            previousSession.removeSelectionTransitionObserver(selectionTransitionToken)
        }
        self.session = session
        selectionTransitionToken = session.addSelectionTransitionObserver { [weak self] _ in
            guard let self else { return }
            self.rebuildContent(selectionOnly: true)
            self.onCommandAvailabilityChanged?()
        }
        self.palette = palette
        refreshPromptStyles()
        contextTick = session.editCursor
        lastPresentation = nil
        rebuildContent()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        if let selectionTransitionToken, let session {
            session.removeSelectionTransitionObserver(selectionTransitionToken)
        }
        selectionTransitionToken = nil
        session = nil
        projection = nil
        rows = []
        selectedParameters = []
        ghostPins = []
        ghostParameters = []
        ghostLabels = []
        laneClipboardPoints = []
        menu = nil
        laneDelete = nil
        band = nil
        gesture = nil
        frozen = nil
        frozenCamera = nil
        tapSession.reset()
        tapGuard = nil
        publishMenuRows()
        publishPrompt()
        publishTapTempo()
        publishContent(nil)
        publishInteractionState()
    }
}
