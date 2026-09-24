import Foundation
import PorydawProject
import Synchronization

private enum ActorCheckError: Error {
    case expected
}

private struct CounterState: Sendable {
    var indices: [Int] = []
}

private final class ActorCheckCounter: Sendable {
    private let state = Mutex(CounterState())

    func append(_ index: Int) -> Int {
        // Keep the read and append separate: a concurrently executing run
        // can observe the same pre-increment count as another operation.
        let previous = state.withLock { $0.indices.count }
        state.withLock { $0.indices.append(index) }
        return previous
    }

    var appendedIndices: [Int] { state.withLock { $0.indices } }
}

private struct ParallelState: Sendable {
    var values: [Int?]
    var completed = 0
    var succeeded = true
}

private final class ParallelActorResults: Sendable {
    private let box: ConditionBox<ParallelState>

    init(count: Int) {
        box = ConditionBox(ParallelState(values: Array(repeating: nil, count: count)))
    }

    func record(_ outcome: Result<Int, Error>?, at index: Int) {
        box.update { state in
            if case .success(let value) = outcome {
                state.values[index] = value
            } else {
                state.succeeded = false
            }
            state.completed += 1
        }
    }

    func wait() -> [Int]? {
        let state = box.wait(while: { $0.completed < $0.values.count }, timeout: 15)
        guard state.completed == state.values.count, state.succeeded else { return nil }
        return state.values.compactMap { $0 }
    }
}

internal func runProjectStoreActorSuite(_ report: CheckReport) {
    let projectRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ProjectStore(projectRoot: projectRoot)
    let id = "projectstore-actor"

    // A01: the actor's executor returns the operation's value.
    let roundTrip = awaitValue { try await store.run { 40 + 2 } }
    report.expect(roundTrip?.success == 42, cppID: "\(id)/A01",
                  message: "actor init and run round-trip returns 42")

    // A02: an operation's original error case crosses the actor boundary.
    let thrown: Result<Int, Error>? = awaitValue {
        try await store.run { throw ActorCheckError.expected }
    }
    if case .failure(ActorCheckError.expected) = thrown {
        report.pass("\(id)/A02", row: "run propagates its error case")
    } else {
        report.fail("\(id)/A02", "run did not propagate the expected error case")
    }

    // A03: independent threads race for the actor; the counter's separate
    // read/append steps expose overlapping operations without racing on data.
    let count = 32
    let counter = ActorCheckCounter()
    let parallel = ParallelActorResults(count: count)
    for index in 0..<count {
        Thread.detachNewThread {
            parallel.record(awaitValue {
                try await store.run { counter.append(index) }
            }, at: index)
        }
    }
    let returned = parallel.wait()
    report.expect(returned?.sorted() == Array(0..<count)
                      && counter.appendedIndices.sorted() == Array(0..<count),
                  cppID: "\(id)/A03",
                  message: "concurrent run calls serialize counter mutation and preserve each index")

    // A04: a suspended outer operation must allow its nested run to proceed.
    let nested = awaitValue {
        try await store.run { try await store.run { 42 } }
    }
    report.expect(nested?.success == 42, cppID: "\(id)/A04",
                  message: "nested run completes without deadlock")

    // A05: value results survive the asynchronous boundary without mutation.
    let input = [3, 1, 4, 1, 5]
    let first = awaitValue { try await store.run { input } }
    let second = awaitValue { try await store.run { input } }
    report.expect(first?.success == input && second?.success == input,
                  cppID: "\(id)/A05",
                  message: "equal array input round-trips as equal value data")
}

private extension Result {
    var success: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
