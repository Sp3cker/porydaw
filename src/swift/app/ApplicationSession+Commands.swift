import Foundation
import PorydawCore
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
        commandRouter?.perform(command)
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
              let workspace else {
            return EditKeyDecision.decline.rawValue
        }
        let available: Bool
        switch command {
        case .moveEventUp, .moveEventDown:
            available = eventList.model.row(at: eventList.currentRow)?.eventIndex != nil
        default:
            available = commandRouter?.isAvailable(command) ?? false
        }
        return EditKeyArbiter.decide(command: command, surface: EditSurfaceState(
            pointerGestureActive: eventList.pointerDown,
            timeSelectionActive: workspace.session.timeSelection?.isActive == true,
            noteSelectionEmpty: workspace.session.selectedNotes.isEmpty,
            origin: .eventList, autoRepeat: autoRepeat,
            commandAvailable: available)).rawValue
    }

    func performEventListCommandImpl(command: Int) {
        guard let command = EditCommand(rawValue: command), eventList.attached else { return }
        switch command {
        case .selectAll: eventList.selectAll()
        case .delete: eventList.deleteSelected()
        case .moveEventUp: eventList.moveEvent(delta: -1)
        case .moveEventDown: eventList.moveEvent(delta: 1)
        default: commandRouter?.perform(command)
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

    func requestSaveImpl() {
        guard let session = workspace?.session, !saveInProgress else { return }
        saveInProgress = true
        lastSaveError = ""
        Task { [weak self] in
            do {
                try await session.save()
            } catch {
                self?.lastSaveError = String(describing: error)
                self?.saveInProgress = false
                return
            }
            await self?.refreshVoicegroupCatalog()
            self?.saveInProgress = false
        }
    }

    func requestUndoImpl() {
        guard let session = workspace?.session else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task { [weak self] in
            do {
                _ = try await session.undo()
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.refreshDocumentState()
            }
        }
    }

    func requestRedoImpl() {
        guard let session = workspace?.session else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task { [weak self] in
            do {
                _ = try await session.redo()
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.refreshDocumentState()
            }
        }
    }
}
