import PorydawDocument
import PorydawVoicegroup

/// Reads live lease kits for Split Studio and the orphan scan.
@MainActor
enum KitLeaseReader {
    static func visitKits(
        lease: ProjectBankLease, service: ProjectService, excluding: inout Set<String>,
        consume: (KitEditValue) throws -> Void
    ) async throws {
        for (slot, view) in lease.slotViews.enumerated()
        where view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit {
            guard let symbol = view.voice?.symbol, excluding.insert(symbol).inserted else { continue }
            let kit = try await service.readKit(lease: lease, slot: slot)
            try Task.checkCancellation()
            try consume(kit)
        }
    }
}
