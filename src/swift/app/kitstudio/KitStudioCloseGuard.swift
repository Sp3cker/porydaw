@MainActor
public final class KitStudioCloseGuard {
    public enum Source { case window, tab, project, quit, retarget }
    private struct Request {
        let source: Source
        let proceed: () -> Void
        let cancel: () -> Void
    }
    private enum State {
        case idle
        case prompt(Request)
        case saving(Request)
    }
    private var state: State = .idle
    public var onChanged: (() -> Void)?
    public var onSave: (() -> Void)?
    public var promptOpen: Bool {
        if case .prompt = state { return true }
        return false
    }
    public var saving: Bool {
        if case .saving = state { return true }
        return false
    }

    /// Runs a clean continuation immediately; dirty requests wait for an explicit answer.
    public func request(source: Source, dirty: Bool, proceed: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
        guard case .idle = state else {
            // Busy requests cancel immediately; the original continuation remains owned here.
            cancel()
            return
        }
        guard dirty else {
            proceed()
            return
        }
        state = .prompt(Request(source: source, proceed: proceed, cancel: cancel))
        onChanged?()
    }

    /// Answers Save (0), Discard (1), or Cancel (2); Save retains the continuation.
    public func answer(_ answer: Int) {
        guard case .prompt(let request) = state else { return }
        switch answer {
        case 0:
            state = .saving(request)
            onChanged?()
            onSave?()
        case 1:
            state = .idle
            onChanged?()
            request.proceed()
        case 2:
            state = .idle
            onChanged?()
            request.cancel()
        default: break
        }
    }

    /// A failed save reopens the same question instead of completing a close.
    public func saveSettled(success: Bool) {
        guard case .saving(let request) = state else { return }
        state = success ? .idle : .prompt(request)
        onChanged?()
        if success { request.proceed() }
    }

    /// Releases pending continuations during application disposal.
    public func reset() {
        state = .idle
        onChanged?()
    }
}
