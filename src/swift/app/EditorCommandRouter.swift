import Foundation
import PorydawCore
import PorydawDocument
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

/// Resolves canonical editor commands against live document selection. The
/// window remains the sole key matcher and text/modal input arbiter.
@MainActor
public struct EditorCommandRouter {
    private unowned let session: DocumentSession
    private unowned let grid: PianoGrid
    private unowned let automation: AutomationPage
    private unowned let rulerMenu: RulerMenuPresenter
    private let drawer: EditorDrawerPresenter?
    private let velocity: VelocityPage?

    public init(
        session: DocumentSession, grid: PianoGrid, automation: AutomationPage,
        rulerMenu: RulerMenuPresenter, drawer: EditorDrawerPresenter? = nil,
        velocity: VelocityPage? = nil
    ) {
        self.session = session
        self.grid = grid
        self.automation = automation
        self.rulerMenu = rulerMenu
        self.drawer = drawer
        self.velocity = velocity
    }

    private var timeSelectionActive: Bool { session.timeSelection?.isActive == true }
    private var pointerGestureActive: Bool {
        grid.interactionActive || grid.scrollbarGrabActive
            || drawer?.resizeActive == true || automation.pointerGestureActive
            || velocity?.hasGesture == true
    }
    private var modalActive: Bool {
        automation.menuOpen || automation.promptOpen || rulerMenu.insertTimePromptOpen
    }

    private func targetsTimeSelection(_ command: EditCommand) -> Bool {
        timeSelectionActive && editCommandPolicy(command).rangeOperation != .none
    }

    public func isAvailable(_ command: EditCommand) -> Bool {
        guard !modalActive,
            !pointerGestureActive || editCommandPolicy(command).survivesPointerGesture
        else { return false }
        if command == .paste || targetsTimeSelection(command) {
            return automation.selectionCommandAvailable(command: command)
        }
        // A time range owns the timeline even for these notes-only rows.
        if timeSelectionActive && (command == .lengthenNote || command == .shortenNote) {
            return false
        }
        if command == .delete && automation.hoverDeleteAvailable() { return true }
        if command == .insertTime {
            return !session.isClosed && session.editCursor < TimeDefaults.maxTick
        }
        return grid.commandAvailable(command: command.rawValue)
    }

    public func route(_ command: EditCommand, autoRepeat: Bool) -> EditKeyDecision {
        guard !modalActive else { return .decline }
        return EditKeyArbiter.decide(
            command: command,
            surface: EditSurfaceState(
                pointerGestureActive: pointerGestureActive,
                timeSelectionActive: timeSelectionActive,
                noteSelectionEmpty: session.selectedNotes.isEmpty,
                origin: .timeline, autoRepeat: autoRepeat,
                commandAvailable: isAvailable(command)))
    }

    /// Runs `.selectAdjacentTrack`: steps the primary track by the command's row.
    public func selectAdjacentTrack(_ command: EditCommand) {
        guard let track = session.selectedTrack else { return }
        session.selectPrimaryTrack(track + editCommandPolicy(command).trackStepWithoutNotes)
    }

    public func perform(_ command: EditCommand) {
        guard isAvailable(command) else { return }
        if command == .paste || targetsTimeSelection(command) {
            // Ownership, not mutation success, decides whether notes may run.
            // An empty or unchanged range never falls through to selected notes.
            _ = automation.consumeSelectionCommand(command: command)
            return
        }
        if command == .insertTime {
            _ = rulerMenu.openInsertTimePromptAtCursor()
            return
        }
        if command == .delete && automation.consumeHoverDelete() { return }
        if command == .pencilMode {
            grid.performCommand(command: command.rawValue)
            automation.isPencilMode = grid.pencilMode
            return
        }
        // Note and standalone commands keep their existing grid executor.
        // Clipboard paste above is document-wide, never selected by focus.
        grid.performCommand(command: command.rawValue)
    }
}

@MainActor
extension ApplicationSession {
    var commandRouter: EditorCommandRouter? {
        guard let workspace else { return nil }
        return EditorCommandRouter(
            session: workspace.session, grid: workspace.grid,
            automation: workspace.automationPage, rulerMenu: workspace.rulerMenu,
            drawer: workspace.drawer, velocity: workspace.velocityPage)
    }
}
