import SwiftGrid
import SwiftGridCommands

// Drives the real sgc_ submission path through the Swift mirror API against
// the executor the C++ harness registered for documentId. Each step mutates
// or probes the fixture document; the C++ side asserts the resulting state.
@MainActor
private func runCommandsCheck(documentId: UInt64) -> Int32 {
    let pipe = SgcCommandPipe(documentId: documentId)

    let added = pipe.submit(.noteAdd(track: 0, key: 60, onTick: 0, durationTicks: 24, velocity: 90))
    guard added.result == .executed, added.noteId != 0 else { return 1 }

    guard pipe.submit(.noteMove(noteId: added.noteId, deltaTicks: 48, deltaKeys: 2)).result
        == .executed else { return 2 }
    guard pipe.submit(.noteResize(noteId: added.noteId, durationTicks: 96)).result
        == .executed else { return 3 }
    guard pipe.submit(.trackRename(track: 0, name: "Lead")).result == .executed else { return 4 }

    // Session intents: executed, no document mutation.
    guard pipe.submit(.selectionSetNotes(noteIds: [added.noteId])).result == .executed
        else { return 5 }
    guard pipe.submit(.trackMute(track: 0, on: true)).result == .executed else { return 6 }
    guard pipe.submit(.trackSolo(track: 1, on: true)).result == .executed else { return 7 }
    guard pipe.submit(.selectionClear).result == .executed else { return 8 }

    // Validation rejections mutate nothing.
    guard pipe.submit(.noteMove(noteId: added.noteId + 100_000, deltaTicks: 1, deltaKeys: 0))
        .result == .rejectedInvalid else { return 9 }
    guard pipe.submit(.noteAdd(track: 99, key: 60, onTick: 0, durationTicks: 24, velocity: 90))
        .result == .rejectedInvalid else { return 10 }

    // No executor bound for this document id.
    let orphan = SgcCommandPipe(documentId: UInt64.max)
    guard orphan.submit(.selectionClear).result == .rejectedUnavailable else { return 11 }

    return 0
}

@_cdecl("sgc_check_swift_submission")
public func sgcCheckSwiftSubmission(_ documentId: UInt64) -> Int32 {
    MainActor.assumeIsolated {
        runCommandsCheck(documentId: documentId)
    }
}
