import Foundation

public enum Xcmd {
    public static let selectorController: UInt8 = 0x1E
    public static let payloadController: UInt8 = 0x1D
    public static let alternatePayloadController: UInt8 = 0x1F
    public static let echoVolumeLane: UInt8 = 0xFB
    public static let echoLengthLane: UInt8 = 0xFC

    public struct Descriptor: Equatable, Sendable {
        public let lane: UInt8
        public let selector: UInt8
        public let minimum: UInt8
        public let maximum: UInt8
        public let defaultValue: UInt8
        public let mnemonic: String
        public let displayName: String
    }

    private static let echoVolumeDescriptor =
        Descriptor(lane: echoVolumeLane, selector: 0x08, minimum: 0, maximum: 127,
                   defaultValue: 0, mnemonic: "xIECV", displayName: "Echo volume")
    private static let echoLengthDescriptor =
        Descriptor(lane: echoLengthLane, selector: 0x09, minimum: 0, maximum: 127,
                   defaultValue: 0, mnemonic: "xIECL", displayName: "Echo length")
    public static let descriptors = [echoVolumeDescriptor, echoLengthDescriptor]
    private static let descriptorsByLane =
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.lane, $0) })
    private static let descriptorsBySelector =
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.selector, $0) })

    public struct Event: Equatable, Sendable {
        public var index: UInt64
        public var tick: Tick
        public var stream: UInt8
        public var controller: UInt8
        public var value: UInt8
        public var channel: UInt8

        public init(index: UInt64, tick: Tick, stream: UInt8, controller: UInt8,
                    value: UInt8, channel: UInt8 = 0) {
            self.index = index
            self.tick = tick
            self.stream = stream
            self.controller = controller
            self.value = value
            self.channel = channel
        }
    }

    public struct Point: Equatable, Sendable {
        public let lane: UInt8
        public let tick: Tick
        public let value: UInt8
        public let index: UInt64
        public let stream: UInt8
        public let channel: UInt8
    }

    public struct Projection: Equatable, Sendable {
        public let points: [Point]
        public let consumed: [UInt64]
    }

    public enum TrafficKind: Equatable, Sendable {
        case completeEchoPoints
        case danglingSelector
        case unknownSelectorEpoch
        case strayPayloads
    }

    public enum ExportClass: Equatable, Sendable {
        case supported
        case notExported
        case needsReview
    }

    public struct TrafficBlock: Equatable, Sendable {
        public let kind: TrafficKind
        public let exportClass: ExportClass
        public let stream: UInt8
        public let selector: UInt8
        public let payloadCount: Int
        public let firstTick: Tick
        public let lastTick: Tick
    }

    public struct TrafficAssessment: Equatable, Sendable {
        public let echoVolumePoints: Int
        public let echoLengthPoints: Int
        public let blocks: [TrafficBlock]
    }

    public struct PointWrite: Equatable, Sendable {
        public var tick: Tick
        public var lane: UInt8
        public var value: Int
        public var stream: UInt8
        public var channel: UInt8

        public init(tick: Tick, lane: UInt8, value: Int, stream: UInt8, channel: UInt8) {
            self.tick = tick
            self.lane = lane
            self.value = value
            self.stream = stream
            self.channel = channel
        }
    }

    public struct Relocation: Equatable, Sendable {
        public var index: UInt64
        public var tick: Tick
        public var channel: UInt8

        public init(index: UInt64, tick: Tick, channel: UInt8) {
            self.index = index
            self.tick = tick
            self.channel = channel
        }
    }

    public struct Emission: Equatable, Sendable {
        public let tick: Tick
        public let controller: UInt8
        public let value: UInt8
        public let sourceIndex: UInt64?
        public let channel: UInt8
    }

    public struct Patch: Equatable, Sendable {
        public let removeEvents: [UInt64]
        public let inserts: [Emission]
    }

    internal struct PointKey: Hashable {
        let stream: UInt8
        let tick: Tick
        let lane: UInt8
    }

    public static func descriptor(forLane lane: UInt8) -> Descriptor? {
        descriptorsByLane[lane]
    }

    public static func descriptor(forSelector selector: UInt8) -> Descriptor? {
        descriptorsBySelector[selector]
    }

    internal static func traffic(in chunk: MidiChunk, stream: UInt8) -> [Event] {
        var result: [Event] = []
        result.reserveCapacity(chunk.events.count)
        for (index, event) in chunk.events.enumerated() {
            guard case let .channel(status, controller, value) = event.payload,
                  status >> 4 == 0xB else { continue }
            result.append(Event(index: UInt64(index), tick: event.tick, stream: stream,
                                controller: controller, value: value, channel: status & 0x0F))
        }
        return result
    }

    public static func project(_ events: [Event]) -> Projection {
        let parsed = parse(events)
        var points: [Point] = []
        points.reserveCapacity(parsed.events.count)
        for block in parsed.blocks {
            guard let descriptor = descriptor(forSelector: block.selector),
                  !block.payloads.isEmpty else { continue }
            for ordinal in block.payloads {
                let event = parsed.events[ordinal].source
                points.append(Point(lane: descriptor.lane, tick: event.tick, value: event.value,
                                    index: event.index, stream: event.stream,
                                    channel: event.channel))
            }
        }
        var consumed = Set<UInt64>()
        consumed.reserveCapacity(parsed.events.count)
        for event in parsed.events { consumed.insert(event.source.index) }
        return Projection(points: points, consumed: consumed.sorted())
    }

    public static func assess(_ events: [Event]) -> TrafficAssessment {
        let parsed = parse(events)
        var volume = 0
        var length = 0
        var result: [TrafficBlock] = []
        result.reserveCapacity(parsed.blocks.count)
        for block in parsed.blocks {
            let kind: TrafficKind
            let exportClass: ExportClass
            let descriptor = descriptor(forSelector: block.selector)
            if block.selectorOrdinal == nil {
                kind = .strayPayloads
                exportClass = .needsReview
            } else if descriptor == nil {
                kind = .unknownSelectorEpoch
                exportClass = .notExported
            } else if block.payloads.isEmpty {
                kind = .danglingSelector
                exportClass = .needsReview
            } else {
                kind = .completeEchoPoints
                exportClass = .supported
                if descriptor?.lane == echoVolumeLane { volume += block.payloads.count }
                else { length += block.payloads.count }
            }
            result.append(TrafficBlock(kind: kind, exportClass: exportClass,
                                       stream: block.stream, selector: block.selector,
                                       payloadCount: block.payloads.count,
                                       firstTick: block.firstTick, lastTick: block.lastTick))
        }
        return TrafficAssessment(echoVolumePoints: volume, echoLengthPoints: length,
                                 blocks: result)
    }

    public static func rewrite(_ events: [Event], removing identities: [UInt64],
                               writing writes: [PointWrite]) -> Patch? {
        let parsed = parse(events)
        var writesByKey: [PointKey: (order: Int, write: PointWrite)] = [:]
        writesByKey.reserveCapacity(writes.count)
        for (order, write) in writes.enumerated() {
            guard descriptor(forLane: write.lane) != nil else { return nil }
            let key = PointKey(stream: write.stream, tick: write.tick, lane: write.lane)
            if let previous = writesByKey[key] {
                writesByKey[key] = (previous.order, write)
            } else {
                writesByKey[key] = (order, write)
            }
        }
        let normalized = writesByKey.values.sorted { $0.order < $1.order }.map(\.write)
        var removedIdentities = Set<UInt64>()
        removedIdentities.reserveCapacity(identities.count)
        var touched = Set<Int>()
        for identity in identities {
            guard let ordinal = parsed.indexOf[identity] else { return nil }
            let event = parsed.events[ordinal]
            let block = parsed.blocks[event.block]
            guard !event.isSelector, descriptor(forSelector: block.selector) != nil,
                  !block.payloads.isEmpty else { return nil }
            removedIdentities.insert(identity)
            touched.insert(event.block)
        }
        for (blockIndex, block) in parsed.blocks.enumerated() {
            for write in normalized where write.stream == block.stream &&
                write.tick >= block.firstTick && write.tick <= block.lastTick {
                guard descriptor(forSelector: block.selector) != nil,
                      !block.payloads.isEmpty else { return nil }
                touched.insert(blockIndex)
            }
        }
        var removals = Set<UInt64>()
        var emissions: [Emission] = []
        for blockIndex in touched.sorted() {
            let block = parsed.blocks[blockIndex]
            rebuildKnown(block, parsed: parsed, removals: &removals, emissions: &emissions) {
                _, event, selector, output in
                guard let lane = descriptor(forSelector: selector)?.lane,
                      !removedIdentities.contains(event.index),
                      writesByKey[PointKey(stream: event.stream, tick: event.tick,
                                           lane: lane)] == nil else { return }
                appendPoint(to: &output, tick: event.tick, selector: selector,
                            value: event.value, channel: event.channel)
            }
        }
        for write in normalized {
            guard let descriptor = descriptor(forLane: write.lane) else { return nil }
            appendPoint(to: &emissions, tick: write.tick, selector: descriptor.selector,
                        value: UInt8(min(max(write.value, Int(descriptor.minimum)),
                                         Int(descriptor.maximum))), channel: write.channel)
        }
        return finish(removals, emissions)
    }

    public static func reconcile(_ events: [Event], removing removals: [UInt64],
                                 moving moves: [Relocation], copying copies: [Relocation]) -> Patch? {
        let parsed = parse(events)
        enum Kind: Equatable { case remove, move, copy }
        struct Operation { let kind: Kind; let relocation: Relocation? }
        struct Request { let identity: UInt64; let operation: Operation }
        var requests: [Request] = []
        requests.reserveCapacity(removals.count + moves.count + copies.count)
        for identity in removals {
            requests.append(Request(identity: identity,
                                    operation: Operation(kind: .remove, relocation: nil)))
        }
        for relocation in moves {
            requests.append(Request(identity: relocation.index,
                                    operation: Operation(kind: .move, relocation: relocation)))
        }
        for relocation in copies {
            requests.append(Request(identity: relocation.index,
                                    operation: Operation(kind: .copy, relocation: relocation)))
        }
        var operations: [Int: Operation] = [:]
        operations.reserveCapacity(requests.count)
        for request in requests {
            guard let ordinal = parsed.indexOf[request.identity] else { return nil }
            if let old = operations[ordinal],
               old.kind != request.operation.kind || old.relocation != request.operation.relocation {
                return nil
            }
            operations[ordinal] = request.operation
        }

        struct BlockOperation { var kind: Kind?; var affected = 0; var mixed = false }
        var blockOperations = Array(repeating: BlockOperation(), count: parsed.blocks.count)
        for (ordinal, operation) in operations {
            let event = parsed.events[ordinal]
            let block = parsed.blocks[event.block]
            let knownGlue = event.isSelector && descriptor(forSelector: block.selector) != nil &&
                !block.payloads.isEmpty
            if knownGlue { continue }
            blockOperations[event.block].affected += 1
            if let kind = blockOperations[event.block].kind, kind != operation.kind {
                blockOperations[event.block].mixed = true
            } else { blockOperations[event.block].kind = operation.kind }
        }
        for index in parsed.blocks.indices {
            let block = parsed.blocks[index]
            let operation = blockOperations[index]
            let memberCount = block.payloads.count + (block.selectorOrdinal == nil ? 0 : 1)
            if operation.affected > 0 &&
                (descriptor(forSelector: block.selector) == nil || block.payloads.isEmpty) &&
                (operation.mixed || operation.affected != memberCount) { return nil }
        }
        for (ordinal, operation) in operations where operation.kind != .remove {
            guard let relocation = operation.relocation else { return nil }
            let source = parsed.events[ordinal]
            for blockIndex in parsed.blocks.indices where blockIndex != source.block {
                let block = parsed.blocks[blockIndex]
                guard block.stream == source.source.stream,
                      block.firstTick <= relocation.tick && relocation.tick <= block.lastTick else {
                    continue
                }
                let blockOperation = blockOperations[blockIndex]
                var survives = blockOperation.affected == 0 || blockOperation.kind == .copy
                if descriptor(forSelector: block.selector) != nil && !block.payloads.isEmpty,
                   blockOperation.affected > 0 {
                    survives = block.payloads.contains { ordinal in
                        operations[ordinal]?.kind != .remove && operations[ordinal]?.kind != .move
                    }
                }
                if survives { return nil }
            }
        }

        var removed = Set<UInt64>()
        var emitted: [Emission] = []
        for blockIndex in parsed.blocks.indices {
            let blockOperation = blockOperations[blockIndex]
            guard blockOperation.affected > 0 else { continue }
            let block = parsed.blocks[blockIndex]
            let known = descriptor(forSelector: block.selector) != nil && !block.payloads.isEmpty
            if known {
                rebuildKnown(block, parsed: parsed, removals: &removed, emissions: &emitted) {
                    ordinal, event, selector, output in
                    guard let operation = operations[ordinal] else {
                        appendPoint(to: &output, tick: event.tick, selector: selector,
                                    value: event.value, channel: event.channel)
                        return
                    }
                    if operation.kind == .remove { return }
                    if operation.kind == .copy {
                        appendPoint(to: &output, tick: event.tick, selector: selector,
                                    value: event.value, channel: event.channel)
                    }
                    if let relocation = operation.relocation {
                        appendPoint(to: &output, tick: relocation.tick, selector: selector,
                                    value: event.value, channel: relocation.channel)
                    }
                }
            } else {
                guard let kind = blockOperation.kind else { return nil }
                let members = ([block.selectorOrdinal].compactMap { $0 } + block.payloads)
                if kind != .copy { for ordinal in members { removed.insert(parsed.events[ordinal].source.index) } }
                if kind != .remove {
                    for ordinal in members {
                        guard let relocation = operations[ordinal]?.relocation else { return nil }
                        emitted.append(Emission(tick: relocation.tick, controller: 0, value: 0,
                                                sourceIndex: parsed.events[ordinal].source.index,
                                                channel: relocation.channel))
                    }
                }
            }
        }
        return finish(removed, emitted)
    }

    public static func canonicalizeForExport(_ events: [Event]) -> Patch {
        let parsed = parse(events)
        var removed = Set<UInt64>()
        var emitted: [Emission] = []
        for block in parsed.blocks {
            if descriptor(forSelector: block.selector) != nil && !block.payloads.isEmpty {
                rebuildKnown(block, parsed: parsed, removals: &removed, emissions: &emitted) {
                    _, event, selector, output in
                    appendPoint(to: &output, tick: event.tick, selector: selector,
                                value: event.value, channel: event.channel)
                }
            } else if descriptor(forSelector: block.selector) != nil,
                      let selector = block.selectorOrdinal {
                removed.insert(parsed.events[selector].source.index)
            }
        }
        return finish(removed, emitted)
    }
}

private extension Xcmd {
    struct ParsedEvent { let source: Event; let block: Int; let isSelector: Bool }
    struct Block {
        var stream: UInt8
        var selector: UInt8 = 0
        var selectorOrdinal: Int?
        var payloads: [Int] = []
        var firstTick: Tick
        var lastTick: Tick
    }
    struct Parsed {
        var events: [ParsedEvent]
        var blocks: [Block]
        var indexOf: [UInt64: Int]
    }

    static func parse(_ events: [Event]) -> Parsed {
        var parsed = Parsed(events: [], blocks: [], indexOf: [:])
        parsed.events.reserveCapacity(events.count)
        parsed.blocks.reserveCapacity(events.count)
        parsed.indexOf.reserveCapacity(events.count)
        var open: [UInt8: Int] = [:]
        for event in events where event.controller == selectorController ||
            event.controller == payloadController || event.controller == alternatePayloadController {
            let isSelector = event.controller == selectorController
            let blockIndex: Int
            if isSelector {
                blockIndex = parsed.blocks.count
                parsed.blocks.append(Block(stream: event.stream, selector: event.value,
                                           selectorOrdinal: nil, firstTick: event.tick,
                                           lastTick: event.tick))
                open[event.stream] = blockIndex
            } else if let existing = open[event.stream] {
                blockIndex = existing
            } else {
                blockIndex = parsed.blocks.count
                parsed.blocks.append(Block(stream: event.stream, firstTick: event.tick,
                                           lastTick: event.tick))
                open[event.stream] = blockIndex
            }
            let ordinal = parsed.events.count
            parsed.events.append(ParsedEvent(source: event, block: blockIndex,
                                             isSelector: isSelector))
            if parsed.indexOf[event.index] == nil { parsed.indexOf[event.index] = ordinal }

            if isSelector { parsed.blocks[blockIndex].selectorOrdinal = ordinal }
            else {
                parsed.blocks[blockIndex].payloads.append(ordinal)
                parsed.blocks[blockIndex].firstTick = min(parsed.blocks[blockIndex].firstTick,
                                                          event.tick)
                parsed.blocks[blockIndex].lastTick = max(parsed.blocks[blockIndex].lastTick,
                                                         event.tick)
            }
        }
        return parsed
    }

    static func rebuildKnown(
        _ block: Block, parsed: Parsed, removals: inout Set<UInt64>,
        emissions: inout [Emission],
        emit: (Int, Event, UInt8, inout [Emission]) -> Void
    ) {
        if let selector = block.selectorOrdinal {
            removals.insert(parsed.events[selector].source.index)
        }
        for ordinal in block.payloads {
            let event = parsed.events[ordinal].source
            removals.insert(event.index)
            emit(ordinal, event, block.selector, &emissions)
        }
    }
    static func appendPoint(to emissions: inout [Emission], tick: Tick, selector: UInt8,
                            value: UInt8, channel: UInt8) {
        emissions.append(Emission(tick: tick, controller: selectorController, value: selector,
                                  sourceIndex: nil, channel: channel))
        emissions.append(Emission(tick: tick, controller: payloadController, value: value,
                                  sourceIndex: nil, channel: channel))
    }

    static func finish(_ removals: Set<UInt64>, _ emissions: [Emission]) -> Patch {
        let ordered = emissions.enumerated().sorted {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset :
                $0.element.tick < $1.element.tick
        }.map(\.element)
        return Patch(removeEvents: removals.sorted(), inserts: ordered)
    }
}
