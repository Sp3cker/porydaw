import Foundation
import PorydawCore

@testable import PorydawApp

// Value-prompt scenarios through the real AutomationPage form route: open,
// draft, accept; opening happens in prepare unless the open itself is timed.

/// The inline prompt's displayed text for a stored value.
@MainActor
private func displayedText(_ f: BenchFixture, stored: Int) throws -> String {
    guard let prompt = f.page.prompt else { throw BenchFailure(description: "no prompt is open") }
    return String(stored - prompt.prompt.storedOffset)
}

@MainActor
func promptScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []

    /// Opens the existing-node prompt on the source node.
    @MainActor func openExisting(_ f: BenchFixture) throws {
        try requireNode(f, f.sourceTick, f.lowValue)
        try f.check(
            f.page.openPrompt(tick: f.sourceTick, value: f.lowValue),
            "the existing-node prompt opens")
        try f.check(f.page.prompt?.forExistingNode == true, "the prompt captured the node")
    }

    /// Opens the insertion prompt at `tick`.
    @MainActor func openInsertion(_ f: BenchFixture, _ tick: Tick) throws {
        try f.check(
            f.page.openInsertionPrompt(tick: Int(tick), value: f.lowValue),
            "the insertion prompt opens")
        try f.check(f.page.prompt?.forExistingNode == false, "the prompt captured an insertion")
    }

    /// The form route: the draft text, then acceptance.
    @MainActor func accept(_ f: BenchFixture, _ scratch: NodeBenchScratch) {
        f.page.updatePromptDraft(draft: scratch.displayed)
        f.runResult = f.page.acceptPromptDraft()
    }

    // Opening the node prompt freezes its facts and writes nothing.
    let open = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.openExisting",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                open.baseline = captureBaseline(f)
            },
            run: { f in
                _ = f.page.openPrompt(tick: f.sourceTick, value: f.lowValue)
                f.runResult = false
            },
            validate: { f in
                try f.check(
                    f.page.promptOpen && f.page.prompt?.forExistingNode == true,
                    "the node prompt is open on the captured node")
                try f.check(
                    f.page.promptDraft == (try displayedText(f, stored: f.lowValue)),
                    "the draft starts at the node's displayed value")
                try expectUnchanged(f, open)
            }))

    // Accepting a new value rewrites the captured node at its own tick.
    let update = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.acceptExistingValue",
            prepare: { f in
                try openExisting(f)
                update.displayed = try displayedText(f, stored: f.highValue)
                let base = captureBaseline(f)
                update.baseline = base
                update.expected = edited(
                    base.points, removing: [f.sourceTick],
                    adding: [NodeBenchPoint(tick: f.sourceTick, value: f.highValue)])
            },
            run: { f in accept(f, update) },
            validate: { f in try expectCommitted(f, update) }))

    // Accepting the value the node already holds changes nothing.
    let same = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.acceptSameValueNoOp",
            prepare: { f in
                try openExisting(f)
                same.displayed = try displayedText(f, stored: f.lowValue)
                same.baseline = captureBaseline(f)
            },
            run: { f in accept(f, same) },
            validate: { f in
                try expectUnchanged(f, same)
                try expectSettled(f)
            }))

    // A draft outside the prompt's domain keeps the form open with its error.
    let invalid = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.invalidDraftRejected",
            prepare: { f in
                try openExisting(f)
                guard let prompt = f.page.prompt else { throw BenchFailure(description: "no prompt is open") }
                invalid.displayed = String(prompt.prompt.maximum + 1)
                invalid.baseline = captureBaseline(f)
            },
            run: { f in accept(f, invalid) },
            validate: { f in
                try expectUnchanged(f, invalid)
                try f.check(f.page.prompt != nil && f.page.promptOpen, "the invalid draft keeps the prompt open")
                try f.check(!f.page.promptError.isEmpty, "the invalid draft publishes its error")
            }))

    // The document moved on after the prompt captured its revision.
    let stale = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.staleAcceptRejected",
            prepare: { f in
                try openExisting(f)
                stale.displayed = try displayedText(f, stored: f.highValue)
                try mutateBehindPage(f)
                stale.baseline = captureBaseline(f)
            },
            run: { f in accept(f, stale) },
            validate: { f in
                try expectUnchanged(f, stale)
                try expectSettled(f)
            }))

    // The insertion prompt writes one node at the empty tick it captured.
    let insert = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.insertEmptyTick",
            prepare: { f in
                try requireEmpty(f, f.emptyTick)
                try openInsertion(f, f.emptyTick)
                insert.displayed = try displayedText(f, stored: f.highValue)
                let base = captureBaseline(f)
                insert.baseline = base
                insert.expected = edited(
                    base.points, removing: [],
                    adding: [NodeBenchPoint(tick: f.emptyTick, value: f.highValue)])
            },
            run: { f in accept(f, insert) },
            validate: { f in try expectCommitted(f, insert) }))

    // An insertion at an occupied tick with a new value replaces the occupant.
    let occupied = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.insertOccupiedOverwrite",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try openInsertion(f, f.sourceTick)
                occupied.displayed = try displayedText(f, stored: midValue(f))
                let base = captureBaseline(f)
                occupied.baseline = base
                occupied.expected = edited(
                    base.points, removing: [f.sourceTick],
                    adding: [NodeBenchPoint(tick: f.sourceTick, value: midValue(f))])
            },
            run: { f in accept(f, occupied) },
            validate: { f in try expectCommitted(f, occupied) }))

    // An insertion duplicating the occupant's own value at that tick is no edit.
    let duplicate = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "prompt.insertDuplicateNoOp",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try openInsertion(f, f.sourceTick)
                duplicate.displayed = try displayedText(f, stored: f.lowValue)
                duplicate.baseline = captureBaseline(f)
            },
            run: { f in accept(f, duplicate) },
            validate: { f in
                try expectUnchanged(f, duplicate)
                try expectSettled(f)
            }))

    for insertion in [false, true] {
        let scratch = NodeBenchScratch()
        scenarios.append(
            BenchScenario(
                name: insertion ? "prompt.overwriteDuplicateOccupants" : "prompt.editDuplicateOccurrence",
                applies: { f in
                    guard case .controlChange(_, let controller) = f.parameter else { return false }
                    return Xcmd.descriptor(forLane: controller) == nil
                },
                prepare: { f in
                    guard case .controlChange(_, let controller) = f.parameter,
                        let source = f.facts().occupants(at: f.sourceTick).first?.lanePoint
                    else {
                        throw BenchFailure(description: "Missing CC occurrence")
                    }
                    f.document.insertRawEvent(
                        chunk: source.chunk,
                        event: .channel(tick: f.sourceTick, status: 0xB0, data0: controller, data1: UInt8(f.highValue)))
                    try f.check(f.facts().occupants(at: f.sourceTick).count == 2, "Two same-tick occupants staged")
                    if insertion {
                        try openInsertion(f, f.sourceTick)
                    } else {
                        try f.check(
                            f.page.openPrompt(tick: f.sourceTick, value: f.highValue), "Duplicate-node prompt opens")
                    }
                    scratch.displayed = try displayedText(f, stored: midValue(f))
                    let base = captureBaseline(f)
                    scratch.baseline = base
                    scratch.expected = edited(
                        base.points, removing: [f.sourceTick],
                        adding: [NodeBenchPoint(tick: f.sourceTick, value: midValue(f))]
                            + (insertion ? [] : [NodeBenchPoint(tick: f.sourceTick, value: f.lowValue)]))
                },
                run: { f in accept(f, scratch) },
                validate: { f in try expectCommitted(f, scratch) }))
    }

    return scenarios
}
