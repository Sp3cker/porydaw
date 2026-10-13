import PorydawDocument
import PorydawVoicegroup

/// Reads live lease kits; the orphan scan excludes subgroups already covered by another tab.
@MainActor
enum KitLeaseReader {
    static func readKits(
        lease: ProjectBankLease, service: ProjectService, selectedSlot: Int? = nil
    ) async throws -> [Int: KitEditValue] {
        let seedSlot =
            selectedSlot.flatMap { (slot: Int) -> Int? in
                (0..<128).contains(slot) ? slot : nil
            }
            ?? lease.slotViews.indices.first { (slot: Int) -> Bool in
                let view = lease.slotViews[slot]
                return view.kind == .none || view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit
        }
        guard let seedSlot else { return [:] }
        // The reader owns the -G identity, which is not the lease's display name.
        let seed = try await service.readKit(lease: lease, slot: seedSlot)
        var values: [Int: KitEditValue] = [:]
        values.reserveCapacity(128)
        values[seedSlot] = seed
        for slot in lease.slotViews.indices where slot != seedSlot {
            if Task.isCancelled { return values }
            let view = lease.slotViews[slot]
            if view.kind == .none {
                values[slot] = KitEditValue(
                    voicegroup: seed.voicegroup, slot: slot, parent: nil, subgroupSymbol: "",
                    children: [], tableName: nil, table: nil)
            } else if view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit {
                values[slot] = try await service.readKit(lease: lease, slot: slot)
            }
        }
        return values
    }

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
