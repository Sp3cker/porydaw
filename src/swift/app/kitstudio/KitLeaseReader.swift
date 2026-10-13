import PorydawDocument
import PorydawVoicegroup

/// Reads live lease kits; the orphan scan excludes subgroups already covered by another tab.
@MainActor
enum KitLeaseReader {
    static func readKits(
        lease: ProjectBankLease, service: ProjectService, selectedSlot: Int? = nil,
        includeEmpty: Bool = true, excludingSubgroups: Set<String> = [],
        consume: ((Int, KitEditValue) throws -> Void)? = nil
    ) async throws -> [Int: KitEditValue] {
        let seedSlot: Int?
        if includeEmpty, let selectedSlot, (0..<128).contains(selectedSlot) {
            seedSlot = selectedSlot
        } else {
            seedSlot = (0..<128).first { (slot: Int) -> Bool in
                let view = lease.slotViews[slot]
                return (includeEmpty && view.kind == .none)
                    || ((view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit)
                        && !excludingSubgroups.contains(view.voice?.symbol ?? ""))
            }
        }
        guard let seedSlot else { return [:] }
        let seed = try await service.readKit(lease: lease, slot: seedSlot)
        var values: [Int: KitEditValue] = [:]
        if let consume {
            try consume(seedSlot, seed)
        } else {
            values.reserveCapacity(128)
            values[seedSlot] = seed
        }
        var visited = excludingSubgroups
        if !includeEmpty { visited.insert(lease.slotViews[seedSlot].voice?.symbol ?? "") }
        for slot in 0..<128 where slot != seedSlot {
            if Task.isCancelled {
                if consume != nil { try Task.checkCancellation() }
                return values
            }
            let view = lease.slotViews[slot]
            if includeEmpty, view.kind == .none {
                values[slot] = KitEditValue(
                    voicegroup: seed.voicegroup, slot: slot, parent: nil, subgroupSymbol: "",
                    children: [], tableName: nil, table: nil)
            } else if view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit {
                if !includeEmpty, !visited.insert(view.voice?.symbol ?? "").inserted { continue }
                let value = try await service.readKit(lease: lease, slot: slot)
                if let consume { try consume(slot, value) } else { values[slot] = value }
            }
        }
        return values
    }
}
