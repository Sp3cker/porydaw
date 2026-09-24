import Foundation

/// NSCondition protects every access to state; the unchecked boundary is
/// confined to this one synchronous wait/signal box.
internal final class ConditionBox<State: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private var state: State

    init(_ state: State) { self.state = state }

    func update(_ body: (inout State) -> Void) {
        condition.lock()
        body(&state)
        condition.signal()
        condition.unlock()
    }

    func wait(while pending: (State) -> Bool, timeout: TimeInterval) -> State {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while pending(state) && condition.wait(until: deadline) {}
        return state
    }
}

internal func awaitValue<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) -> Result<Value, Error>? {
    let result = ConditionBox<Result<Value, Error>?>(nil)
    Thread.detachNewThread {
        Task {
            do {
                let value = try await operation()
                result.update { $0 = .success(value) }
            } catch {
                result.update { $0 = .failure(error) }
            }
        }
    }
    return result.wait(while: { $0 == nil }, timeout: 60)
}
