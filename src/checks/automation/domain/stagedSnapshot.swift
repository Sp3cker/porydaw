import Foundation
import PorydawCore

@testable import PorydawDocument

// The staged-gesture snapshot triple: serialized song bytes, revision and
// undo index/count captured before a gesture stage and compared mid-grab.
@MainActor
public struct DrawerAutomationStagedSnapshot: Equatable {
    public let revision: UInt64
    public let bytes: [UInt8]
    public let undoIndex: Int
    public let undoCount: Int
    public init(_ document: SongDocument) {
        revision = document.revision
        // Check harness convention is try!: a throw must surface, never read as empty bytes.
        bytes = try! document.captureSave().bytes
        undoIndex = document.history.undoIndex
        undoCount = document.history.undoCount
    }
}
