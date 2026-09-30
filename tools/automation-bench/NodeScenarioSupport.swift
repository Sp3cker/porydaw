import Foundation
import PorydawCore

@testable import PorydawApp

// Shared baselines, preconditions and outcome checks for node and prompt
// scenarios; all run outside the timed region.

/// One written occurrence of the active lane, ordered for multiset comparison.
struct NodeBenchPoint: Equatable, Comparable, CustomStringConvertible {
    let tick: Tick
    let value: Int

    static func < (lhs: NodeBenchPoint, rhs: NodeBenchPoint) -> Bool {
        (lhs.tick, lhs.value) < (rhs.tick, rhs.value)
    }

    var description: String { "\(tick):\(value)" }
}

/// Document facts a scenario compares against, captured after prepare.
struct NodeBenchBaseline {
    let revision: UInt64
    let undoIndex: Int
    let undoCount: Int
    let songBytes: [UInt8]?
    let points: [NodeBenchPoint]
}

/// Per-scenario scratch shared by prepare, run and validate of one sample.
@MainActor
final class NodeBenchScratch {
    var baseline: NodeBenchBaseline?
    var expected: [NodeBenchPoint] = []
    var targetValue = 0
    var displayed = ""
    var previewed = false
    var pressX = 0.0
    var pressY = 0.0
    var releaseX = 0.0
    var releaseY = 0.0
}

@MainActor
func writtenPoints(_ f: BenchFixture) -> [NodeBenchPoint] {
    f.facts().snapshot.sources.map { NodeBenchPoint(tick: $0.tick, value: $0.value) }.sorted()
}

@MainActor
func captureBaseline(_ f: BenchFixture) -> NodeBenchBaseline {
    NodeBenchBaseline(
        revision: f.document.revision,
        undoIndex: f.document.history.undoIndex,
        undoCount: f.document.history.undoCount,
        songBytes: try? f.document.captureSave().bytes,
        points: writtenPoints(f))
}

/// The baseline with every occurrence at `removing` ticks dropped and `adding`
/// written: the exact lane a committed edit must leave.
func edited(
    _ base: [NodeBenchPoint], removing: Set<Tick>,
    adding: [NodeBenchPoint]
) -> [NodeBenchPoint] {
    (base.filter { !removing.contains($0.tick) } + adding).sorted()
}

@MainActor
func occupantValue(at tick: Tick, _ f: BenchFixture) throws -> Int {
    let occupants = f.facts().occupants(at: tick)
    try f.check(occupants.count == 1, "fixture lane holds exactly one occurrence at tick \(tick)")
    return occupants[0].value
}

/// Precondition: the fixture camera maps `tick`'s x back onto `tick`.
@MainActor
func requireTick(_ f: BenchFixture, _ tick: Tick, fine: Bool) throws {
    let projection = f.page.makeProjection(facts: f.facts(), camera: f.page.liveCamera())
    let mapped = projection.tick(atX: f.x(tick), fine: fine)
    try f.check(
        mapped == tick,
        "fixture camera maps tick \(tick) (fine: \(fine)) back to \(mapped)")
}

/// Precondition: the plot maps `value`'s y back onto `value`.
@MainActor
func requireValue(_ f: BenchFixture, _ value: Int) throws {
    let facts = f.facts()
    let projection = f.page.makeProjection(facts: facts, camera: f.page.liveCamera())
    let mapped = projection.value(atY: f.y(value), metadata: facts.metadata)
    try f.check(mapped == value, "plot maps value \(value) back to \(mapped)")
}

@MainActor
func requireEmpty(_ f: BenchFixture, _ tick: Tick) throws {
    try f.check(f.facts().occupants(at: tick).isEmpty, "fixture tick \(tick) is unoccupied")
}

/// Precondition for pointer gestures: the node under `tick` really holds `expected`.
@MainActor
func requireNode(_ f: BenchFixture, _ tick: Tick, _ expected: Int) throws {
    let held = try occupantValue(at: tick, f)
    try f.check(held == expected, "fixture node at \(tick) holds \(expected), found \(held)")
}

/// No gesture, prompt, preview or interaction survives the finished edit.
@MainActor
func expectSettled(_ f: BenchFixture) throws {
    try f.check(f.page.gesture == nil && f.page.frozen == nil, "no gesture or frozen facts remain")
    try f.check(f.page.prompt == nil, "no prompt remains open")
    try f.check(f.page.previewPoints.isEmpty, "the preview is retired")
    try f.check(!f.page.interactionActive, "the page publishes no live interaction")
}

/// Exactly one committed revision and history entry producing `expected`.
@MainActor
func expectCommitted(_ f: BenchFixture, _ scratch: NodeBenchScratch) throws {
    guard let before = scratch.baseline else { throw BenchFailure(description: "no prepared baseline") }
    try f.check(f.runResult, "the edit route reported a commit")
    let after = writtenPoints(f)
    try f.check(
        after == scratch.expected,
        "lane is \(after), expected \(scratch.expected)")
    try f.check(
        f.document.revision == before.revision + 1,
        "one revision: \(before.revision) -> \(f.document.revision)")
    try f.check(
        f.document.history.undoCount == before.undoCount + 1
            && f.document.history.undoIndex == before.undoIndex + 1,
        "one history entry appended")
    try expectSettled(f)
}

/// Nothing written: revision, history and saved song bytes equal the baseline.
@MainActor
func expectUnchanged(_ f: BenchFixture, _ scratch: NodeBenchScratch) throws {
    guard let before = scratch.baseline else { throw BenchFailure(description: "no prepared baseline") }
    try f.check(!f.runResult, "the edit route reported no commit")
    try f.check(f.document.revision == before.revision, "revision unchanged")
    try f.check(
        f.document.history.undoCount == before.undoCount
            && f.document.history.undoIndex == before.undoIndex,
        "history unchanged")
    try f.check(
        before.songBytes != nil && (try? f.document.captureSave().bytes) == before.songBytes,
        "saved song bytes unchanged")
    try f.check(writtenPoints(f) == before.points, "lane occurrences unchanged")
}

/// Midpoint of the two dataset values: a third value distinct from both.
@MainActor
func midValue(_ f: BenchFixture) -> Int { (f.lowValue + f.highValue) / 2 }

/// A production resolver move, committed outside the page, that makes any
/// frozen page transaction stale.
@MainActor
func mutateBehindPage(_ f: BenchFixture) throws {
    let facts = f.facts()
    let current = try occupantValue(at: f.targetTick, f)
    let replacement = current == f.lowValue ? f.highValue : f.lowValue
    guard
        let plan = AutomationNodeResolver.moves([
            .init(
                facts,
                [
                    AutomationNodeMove(
                        parameter: facts.parameter, sourceTick: f.targetTick,
                        tick: f.targetTick, value: replacement)
                ])
        ])
    else { throw BenchFailure(description: "the out-of-page move resolves no plan") }
    try f.check(AutomationCommit.apply(plan, in: f.document), "the out-of-page move commits")
}
