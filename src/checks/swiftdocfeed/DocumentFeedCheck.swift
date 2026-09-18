import SwiftGrid
import SwiftGridDocumentFeed

@MainActor
private func runDocumentFeedCheck() -> Int32 {
    let firstId = UInt64.max - 1
    let secondId = UInt64.max
    var firstSlot = SgdDelivery()
    var secondSlot = SgdDelivery()
    return withUnsafeMutablePointer(to: &firstSlot) { firstEndpoint in
        withUnsafeMutablePointer(to: &secondSlot) { secondEndpoint in
            sgd_register_feed(firstId, firstEndpoint)
            sgd_register_feed(secondId, secondEndpoint)
            defer {
                sgd_unregister_feed(firstId)
                sgd_unregister_feed(secondId)
            }
            var first: DocumentFeed? = DocumentFeed(documentId: firstId)
            var second: DocumentFeed? = DocumentFeed(documentId: secondId)
            weak let releasedFirst = first
            var firstNotifications = 0
            var secondNotifications = 0
            first!.onDocument = { _ in firstNotifications += 1 }
            second!.onDocument = { _ in secondNotifications += 1 }
            guard first!.connect(), second!.connect(), !first!.connect() else { return 1 }
            guard firstNotifications == 0, secondNotifications == 0 else { return 2 }
            // Failed recipients must not clear the real binding when destroyed.
            var duplicate: DocumentFeed? = DocumentFeed(documentId: firstId)
            guard !duplicate!.connect() else { return 3 }
            duplicate = nil
            guard firstEndpoint.pointee.fn != nil else { return 4 }

            var note = SgdNote(trackIndex: 1, key: 72, onTick: UInt32.max - 64,
                               durationTicks: 32, velocity: 99)
            var signature = SgdTimeSignature(startTick: 0, numerator: 0, denomPow2: 255)
            var header = SgdDocumentHeader(documentId: firstId, revision: 0, ticksPerBeat: 480,
                                           trackCount: 2, noteCount: 1, timeSignatureCount: 1)
            withUnsafePointer(to: &header) { headerPointer in
                withUnsafePointer(to: &note) { notePointer in
                    withUnsafePointer(to: &signature) { signaturePointer in
                        let slot = firstEndpoint.pointee
                        slot.fn!(headerPointer, notePointer, signaturePointer, slot.context)
                    }
                }
            }
            // The call-scoped source storage can change without changing the accepted value.
            note.key = 1
            signature.denomPow2 = 2
            guard first!.appliedRevision == 0, firstNotifications == 1,
                  first!.document?.notes.first?.key == 72,
                  first!.document?.notes.first?.onTick == UInt32.max - 64,
                  first!.document?.signatures.first?.numerator == 0,
                  first!.document?.signatures.first?.denomPow2 == 255 else { return 5 }

            header.noteCount = 0
            header.timeSignatureCount = 0
            guard !first!.apply(header: header, notes: nil, signatures: nil),
                  firstNotifications == 1, first!.document?.notes.first?.key == 72 else { return 6 }
            header.revision = 7
            guard first!.apply(header: header, notes: nil, signatures: nil),
                  firstNotifications == 2, first!.document?.notes == [] else { return 7 }
            header.revision = 6
            guard !first!.apply(header: header, notes: nil, signatures: nil),
                  first!.appliedRevision == 7, firstNotifications == 2 else { return 8 }
            header.documentId = secondId
            header.revision = 100
            guard !first!.apply(header: header, notes: nil, signatures: nil),
                  first!.appliedRevision == 7, firstNotifications == 2 else { return 9 }
            header.revision = 0
            guard second!.apply(header: header, notes: nil, signatures: nil),
                  second!.appliedRevision == 0, secondNotifications == 1 else { return 10 }
            header.documentId = firstId
            header.revision = 8
            guard first!.apply(header: header, notes: nil, signatures: nil),
                  !second!.apply(header: header, notes: nil, signatures: nil),
                  firstNotifications == 3, secondNotifications == 1 else { return 11 }
            header.documentId = secondId
            header.revision = 1
            guard second!.apply(header: header, notes: nil, signatures: nil),
                  secondNotifications == 2, first!.appliedRevision == 8 else { return 12 }

            sgd_unregister_feed(firstId)
            first = nil
            guard releasedFirst == nil, firstEndpoint.pointee.fn == nil,
                  firstEndpoint.pointee.context == nil else { return 13 }
            // A fresh mount has no revision history from the closed receiver.
            let remount = DocumentFeed(documentId: firstId - 1)
            header.documentId = firstId - 1
            header.revision = 0
            guard remount.apply(header: header, notes: nil, signatures: nil),
                  remount.appliedRevision == 0, second!.appliedRevision == 1 else { return 14 }
            // Receiver destruction also clears a still-registered endpoint.
            second = nil
            guard secondEndpoint.pointee.fn == nil, secondEndpoint.pointee.context == nil else { return 15 }
            guard !remount.connect() else { return 16 }
            return 0
        }
    }
}

@_cdecl("sgd_check_swift_guard")
public func sgdCheckSwiftGuard() -> Int32 {
    MainActor.assumeIsolated {
        runDocumentFeedCheck()
    }
}
