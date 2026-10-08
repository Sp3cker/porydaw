import PorydawDocument

/// Owns history-command preparation and replay without knowing which tab is selected.
@MainActor
final class HistoryNavigation {
    enum Request {
        case undo
        case redo
        case jump(toIndex: Int)
    }

    struct Availability {
        let canUndo: Bool
        let canRedo: Bool
        let canJump: Bool
    }

    private var jumpInFlight = false
    private let prepare: (Availability) -> Void
    private let reportFailure: (String) -> Void
    private let refreshAvailability: () -> Void

    init(
        prepare: @escaping (Availability) -> Void,
        reportFailure: @escaping (String) -> Void,
        refreshAvailability: @escaping () -> Void
    ) {
        self.prepare = prepare
        self.reportFailure = reportFailure
        self.refreshAvailability = refreshAvailability
    }

    func availability(
        for session: DocumentSession?, bankTransitionInFlight: Bool
    ) -> Availability {
        guard let session, !bankTransitionInFlight, !jumpInFlight else {
            return Availability(canUndo: false, canRedo: false, canJump: false)
        }
        let history = session.document.history
        return Availability(canUndo: history.canUndo, canRedo: history.canRedo, canJump: true)
    }

    func request(
        _ request: Request, session: DocumentSession, bankTransitionInFlight: Bool
    ) {
        var available = availability(for: session, bankTransitionInFlight: bankTransitionInFlight)
        let isJump: Bool
        switch request {
        case .undo:
            guard available.canUndo else { return }
            isJump = false
        case .redo:
            guard available.canRedo else { return }
            isJump = false
        case .jump:
            guard available.canJump else { return }
            isJump = true
        }
        if isJump {
            jumpInFlight = true
            available = availability(for: session, bankTransitionInFlight: bankTransitionInFlight)
        }
        prepare(available)
        Task { [weak self] in
            defer {
                if isJump {
                    self?.jumpInFlight = false
                    self?.refreshAvailability()
                }
            }
            do {
                switch request {
                case .undo: _ = try await session.undo()
                case .redo: _ = try await session.redo()
                case .jump(let target): _ = try await session.jump(toIndex: target)
                }
            } catch {
                self?.reportFailure(String(describing: error))
                if !isJump { self?.refreshAvailability() }
            }
        }
    }
}
