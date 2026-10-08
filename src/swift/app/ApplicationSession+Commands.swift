import Foundation
import PorydawCore
import PorydawDocument
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
extension ApplicationSession {
    func gridCommandAvailableImpl(command: Int) -> Bool {
        guard let command = EditCommand(rawValue: command) else { return false }
        return commandRouter?.isAvailable(command) ?? false
    }

    func performGridCommandImpl(command: Int) {
        guard let command = EditCommand(rawValue: command) else { return }
        performRouted(command)
    }

    private func performRouted(_ command: EditCommand) {
        if let refusal = commandRouter?.perform(command) { publishStatusMessage(message: refusal) }
    }

    func selectAdjacentGridTrack(_ command: EditCommand) {
        commandRouter?.selectAdjacentTrack(command)
    }

    func routeGridKeyImpl(command: Int, autoRepeat: Bool) -> Int {
        guard let command = EditCommand(rawValue: command) else {
            return EditKeyDecision.decline.rawValue
        }
        return commandRouter?.route(command, autoRepeat: autoRepeat).rawValue
            ?? EditKeyDecision.decline.rawValue
    }

    func releaseGridKeyImpl(autoRepeat: Bool) -> Bool {
        guard !autoRepeat, let workspace else { return false }
        return workspace.grid.finishKeyboardTransposeAudition()
    }

    func routeEventListCommandImpl(command: Int, autoRepeat: Bool) -> Int {
        guard let command = EditCommand(rawValue: command), eventList.attached,
            eventList.visible, !eventList.editing, !eventList.menuOpen,
            let workspace
        else {
            return EditKeyDecision.decline.rawValue
        }
        let available: Bool
        switch command {
        case .moveEventUp, .moveEventDown:
            available = eventList.model.row(at: eventList.currentRow)?.eventIndex != nil
        default:
            available = commandRouter?.isAvailable(command) ?? false
        }
        return EditKeyArbiter.decide(
            command: command,
            surface: EditSurfaceState(
                pointerGestureActive: eventList.pointerDown,
                timeSelectionActive: workspace.session.timeSelection?.isActive == true,
                noteSelectionEmpty: workspace.session.selectedNotes.isEmpty,
                origin: .eventList, autoRepeat: autoRepeat,
                commandAvailable: available)
        ).rawValue
    }

    func performEventListCommandImpl(command: Int) {
        guard let command = EditCommand(rawValue: command), eventList.attached else { return }
        switch command {
        case .selectAll: eventList.selectAll()
        case .delete: eventList.deleteSelected()
        case .moveEventUp: eventList.moveEvent(delta: -1)
        case .moveEventDown: eventList.moveEvent(delta: 1)
        default: performRouted(command)
        }
    }

    func handleGridEscapeImpl() -> Bool {
        if workspace?.drawer.resizeActive == true {
            workspace?.drawer.cancelResize()
            return true
        }
        if workspace?.velocityPage.handleEscape() == true {
            return true
        }
        return workspace?.grid.handleEscape() ?? false
    }

    func cancelGridInputImpl(reason: Int) {
        // An installed workspace's cancel already covers the drawer it owns, so
        // the empty presenter is cancelled only when no document is present.
        if let workspace {
            workspace.cancel(reason: reason)
            cancelTimeSigPrompt()
            closeTimeSigMenu()
        } else {
            emptyDrawerPresenter.inputCancelled(reason: reason)
        }
    }

    func publishLastSaveError(_ message: String) {
        publish(\.lastSaveError, message)
        if !message.isEmpty { onStatusMessage?(message) }
    }

    func publishSaveState(inProgress: Bool, error: String? = nil) {
        publish(\.saveInProgress, inProgress)
        if let error { publishLastSaveError(error) }
        onSaveStateChanged?()
    }

    func requestSaveImpl() {
        guard let session = workspace?.session, !saveInProgress else { return }
        publishSaveState(inProgress: true, error: "")
        Task { [weak self] in
            do {
                try await session.save()
            } catch is SaveConflictError {
                // Nothing was written; the prompt takes the answer.
                self?.publishSaveState(inProgress: false)
                self?.presentSaveConflict(session: session, closeTabId: nil)
                return
            } catch {
                self?.publishSaveState(inProgress: false, error: String(describing: error))
                return
            }
            await self?.refreshVoicegroupCatalog()
            self?.publishSaveState(inProgress: false)
        }
    }
}
