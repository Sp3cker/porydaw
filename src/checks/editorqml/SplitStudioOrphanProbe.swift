import PorydawApp
import QtBridge

@MainActor
@QtBridgeable
public final class SplitStudioOrphanProbe: QmlInstantiableStatus {
    public var ready: Bool = false
    public var names: [String] = []
    public var failure: String = ""
    @QtTracked public var session: ApplicationSession?
    private var task: Task<Void, Never>?

    public init() {}
    public func componentComplete() {}

    public func scan() {
        task?.cancel()
        ready = false
        names = []
        failure = ""
        guard let session else {
            failure = "No application session is attached"
            ready = true
            return
        }
        task = Task { [weak self] in
            do {
                let names = try await session.orphanSplitStudioSamples()
                guard let self, !Task.isCancelled else { return }
                self.names = names
                self.ready = true
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.failure = String(describing: error)
                self.ready = true
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        session = nil
    }
}
