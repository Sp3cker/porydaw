import Foundation

/// Note traversal order for the track arpeggiator.
public enum ArpeggiatorMode: Int, CaseIterable, Sendable {
    case up = 0
    case down, upDown, manual, poly, custom
}

/// Optional chord member played before each selected note group.
public enum ArpeggiatorInsert: Int, Sendable {
    case off = 0
    case lowest, highest
}

/// Pure, unsaved settings for one generated loop.
public struct ArpeggiatorSettings: Equatable, Sendable {
    public var mode: ArpeggiatorMode = .up
    public var insert: ArpeggiatorInsert = .off
    public var rateNumerator: Int = 1
    public var rateDenominator: Int = 16
    public var octaves: Int = 1
    public var transpose: Int = 0
    public var masterVelocity: Int = 100
    public var accentAmount: Int = 25
    public var shuffle: Int = 0
    public var gate: Int = 80
    public var steps: Int = 16
    public var enabledSteps: UInt32 = .max
    public var accentSteps: UInt32 = 0
    public var restartOnNoteOn: Bool = true
    public var customPattern: String = "1234----"
    public var seed: UInt64 = 1

    public init() {}
}

/// Generated absolute notes, pad clock positions, and effective hardware timing.
public struct ArpeggiatorResult: Equatable, Sendable {
    public let notes: [NewNote]
    public let droppedPitchCount: Int
    public let stepTicks: [Tick]
    public let stepIndices: [Int]
    public let quantumTicks: Tick
    public let quantumClocks: Int
    public let stepClocks: Int
    public let shuffleClocks: Int
    /// Effective durations in hardware clocks, parallel to `notes`.
    public let gateClocks: [Int]
}

/// Invalid parameters or an unsupported exact clock representation.
public enum ArpeggiatorError: Error, LocalizedError, Equatable {
    case invalidSettings(String)
    case invalidRange(String)
    case unsupportedTiming(String)
    case outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidSettings(let reason), .invalidRange(let reason), .unsupportedTiming(let reason): reason
        case .outputTooLarge: "Arpeggiator output exceeds the 65,536 note or clock-event limit."
        }
    }
}

/// Deterministic generation on the document/GBA common integer clock lattice.
public enum Arpeggiator {
    /// Checks settings and rate/Insert clock compatibility without enumerating a loop.
    /// Loop markers, retrigger boundaries, and emitted gate durations are checked by `generate`.
    public static func supportsTiming(
        ticksPerBeat: UInt32, playbackSettings: PlaybackSettings, settings: ArpeggiatorSettings
    ) -> Bool {
        guard ticksPerBeat > 0 else { return false }
        do {
            try validate(settings)
            _ = try Timing(division: ticksPerBeat, playback: playbackSettings, settings: settings)
            return true
        } catch {
            return false
        }
    }

    /// Generates one loop without changing source notes or document state.
    /// - Throws: `ArpeggiatorError` for invalid settings, unsupported timing, or oversized output.
    public static func generate(
        notes: [Note], track: Int, start: Tick, end: Tick, ticksPerBeat: UInt32,
        playbackSettings: PlaybackSettings, settings: ArpeggiatorSettings
    ) throws -> ArpeggiatorResult {
        try validate(settings)
        guard track >= 0, start < end, ticksPerBeat > 0 else {
            throw ArpeggiatorError.invalidRange("A nonnegative track, positive PPQ, and nonempty loop are required.")
        }
        let timing = try Timing(division: ticksPerBeat, playback: playbackSettings, settings: settings)
        let first = Int64(start)
        let last = Int64(end)
        guard first % timing.quantumTicks == 0, last % timing.quantumTicks == 0 else {
            throw ArpeggiatorError.invalidRange(
                "Loop markers must lie on the shared \(timing.quantumTicks)-tick / \(timing.quantumClocks)-clock lattice."
            )
        }
        var source = Source(notes: notes, track: track, start: first, end: last)
        var restarts: [Int64] = []
        if settings.restartOnNoteOn {
            for note in source.notes where Int64(note.tick) >= first {
                // The restart must not precede the source onset that supplies its chord.
                let tick = ((Int64(note.tick) + timing.quantumTicks - 1) / timing.quantumTicks) * timing.quantumTicks
                if tick > first, tick < last, restarts.last != tick {
                    restarts.append(tick)
                    guard restarts.count <= limit else { throw ArpeggiatorError.outputTooLarge }
                }
            }
        }
        restarts.append(last)
        var output = Output(track: track, end: last, timing: timing, settings: settings)
        var stepTicks: [Tick] = []
        var stepIndices: [Int] = []
        var segmentStart = first
        var noteCursor = 0
        var random = settings.seed
        let custom = Array(settings.customPattern).filter { $0 != "-" }
        var clockEvents = 0
        for segmentEnd in restarts {
            var ordinal: Int64 = 0
            var pad = 0
            if settings.restartOnNoteOn { noteCursor = 0 }
            while true {
                let tick = segmentStart + ordinal * timing.stepTicks + (ordinal % 2 == 1 ? timing.shuffleTicks : 0)
                if tick >= segmentEnd { break }
                let nextOrdinal = ordinal + 1
                let nextTick =
                    segmentStart + nextOrdinal * timing.stepTicks
                    + (nextOrdinal % 2 == 1 ? timing.shuffleTicks : 0)
                let slotEnd = min(nextTick, segmentEnd)
                clockEvents += 1
                guard clockEvents <= limit else { throw ArpeggiatorError.outputTooLarge }
                stepTicks.append(Tick(tick))
                stepIndices.append(pad)
                let enabled = settings.enabledSteps & (UInt32(1) << pad) != 0
                let accented = settings.accentSteps & (UInt32(1) << pad) != 0
                let chord = source.chord(at: tick, octaves: settings.octaves, manual: settings.mode == .manual)
                if settings.insert != .off {
                    let quanta = (slotEnd - tick) / timing.quantumTicks
                    guard quanta >= 2 else {
                        throw ArpeggiatorError.unsupportedTiming(
                            "Insert requires at least two shared clock quanta in every step, including retrigger and loop boundaries."
                        )
                    }
                    let middle = tick + (quanta / 2) * timing.quantumTicks
                    _ = try timing.duration(
                        target: Double(middle - tick) * Double(min(settings.gate, 100)) / 100, maximum: middle - tick)
                    _ = try timing.duration(
                        target: Double(slotEnd - middle) * Double(min(settings.gate, 100)) / 100,
                        maximum: slotEnd - middle)
                    let secondChord = source.chord(
                        at: middle, octaves: settings.octaves, manual: settings.mode == .manual)
                    let selected = select(
                        secondChord, cursor: noteCursor, mode: settings.mode, custom: custom, random: &random)
                    if enabled {
                        clockEvents += 1
                        guard clockEvents <= limit else { throw ArpeggiatorError.outputTooLarge }
                        let sorted = chord.sorted { $0.pitch < $1.pitch }
                        let inserted = settings.insert == .lowest ? sorted.first : sorted.last
                        try output.emit(inserted.map { [$0] } ?? [], at: tick, slotEnd: middle, accented: accented)
                        try output.emit(selected, at: middle, slotEnd: slotEnd, accented: accented)
                    }
                } else {
                    let selected = select(
                        chord, cursor: noteCursor, mode: settings.mode, custom: custom, random: &random)
                    _ = try timing.duration(
                        target: Double(slotEnd - tick) * Double(min(settings.gate, 100)) / 100, maximum: slotEnd - tick)
                    if enabled { try output.emit(selected, at: tick, slotEnd: slotEnd, accented: accented) }
                }
                noteCursor += 1
                pad += 1
                if pad == settings.steps {
                    pad = 0
                    if !settings.restartOnNoteOn { noteCursor = 0 }
                }
                ordinal = nextOrdinal
            }
            segmentStart = segmentEnd
        }
        try output.finish()
        let gates = output.notes.map { (note: NewNote) -> Int in
            Int(Int64(note.duration) / timing.quantumTicks * timing.quantumClocks)
        }
        return ArpeggiatorResult(
            notes: output.notes, droppedPitchCount: output.dropped,
            stepTicks: stepTicks, stepIndices: stepIndices,
            quantumTicks: Tick(timing.quantumTicks), quantumClocks: Int(timing.quantumClocks),
            stepClocks: Int(timing.stepTicks / timing.quantumTicks * timing.quantumClocks),
            shuffleClocks: Int(timing.shuffleTicks / timing.quantumTicks * timing.quantumClocks), gateClocks: gates
        )
    }

    private static let limit = 65_536

    private static func validate(_ settings: ArpeggiatorSettings) throws {
        guard (1...4).contains(settings.octaves), (-12...12).contains(settings.transpose),
            (0...100).contains(settings.masterVelocity), (-100...100).contains(settings.accentAmount),
            (0...99).contains(settings.shuffle), (10...101).contains(settings.gate),
            (1...32).contains(settings.steps), settings.rateNumerator > 0, settings.rateDenominator > 0
        else {
            throw ArpeggiatorError.invalidSettings(
                "Invalid octave, transpose, velocity, accent, shuffle, gate, steps, or rate setting.")
        }
        guard settings.customPattern.count <= 8,
            settings.customPattern.allSatisfy({ "123456789R-".contains($0) })
        else {
            throw ArpeggiatorError.invalidSettings(
                "Custom pattern must contain at most eight characters: 1–9, R, or -.")
        }
    }

    private struct Member {
        let pitch: Int
        let velocity: Int
    }

    private static func select(
        _ chord: [Member], cursor: Int, mode: ArpeggiatorMode, custom: [Character], random: inout UInt64
    ) -> [Member] {
        guard !chord.isEmpty else { return [] }
        switch mode {
        case .poly: return chord
        case .up, .manual: return [chord[cursor % chord.count]]
        case .down: return [chord[chord.count - 1 - cursor % chord.count]]
        case .upDown:
            let period = max(1, chord.count * 2 - 2)
            let index = cursor % period
            return [chord[index < chord.count ? index : period - index]]
        case .custom:
            guard !custom.isEmpty else { return [] }
            let token = custom[cursor % custom.count]
            if token == "R" {
                random &+= 0x9E37_79B9_7F4A_7C15
                var value = random
                value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
                value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
                value ^= value >> 31
                return [chord[Int(value % UInt64(chord.count))]]
            }
            guard let number = token.wholeNumberValue, number <= chord.count else { return [] }
            return [chord[number - 1]]
        }
    }

    private struct Source {
        let notes: [Note]
        private var next = 0
        private var active: [[Int]] = Array(repeating: [], count: 128)

        init(notes: [Note], track: Int, start: Int64, end: Int64) {
            self.notes = notes.filter { note in
                note.track == track && note.pitch < 128 && note.velocity > 0 && Int64(note.tick) < end
                    && (note.endTick.map { $0 > UInt64(start) } ?? true)
            }.sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                if lhs.onIndex != rhs.onIndex { return lhs.onIndex < rhs.onIndex }
                if lhs.chunk != rhs.chunk { return lhs.chunk < rhs.chunk }
                return lhs.id.rawValue < rhs.id.rawValue
            }
        }

        mutating func chord(at tick: Int64, octaves: Int, manual: Bool) -> [Member] {
            while next < notes.count, Int64(notes[next].tick) <= tick {
                active[Int(notes[next].pitch)].append(next)
                next += 1
            }
            var indices: [Int] = []
            for pitch in 0..<128 {
                while let index = active[pitch].last,
                    let end = notes[index].endTick, end <= UInt64(tick)
                {
                    active[pitch].removeLast()
                }
                if let index = active[pitch].last { indices.append(index) }
            }
            if manual { indices.sort() }
            var expanded: [Member] = []
            expanded.reserveCapacity(indices.count * octaves)
            for octave in 0..<octaves {
                for index in indices {
                    expanded.append(
                        Member(pitch: Int(notes[index].pitch) + octave * 12, velocity: Int(notes[index].velocity)))
                }
            }
            if !manual { expanded.sort { $0.pitch < $1.pitch } }
            return expanded
        }
    }

    private struct Timing {
        let quantumTicks: Int64
        let quantumClocks: Int64
        let stepTicks: Int64
        let shuffleTicks: Int64
        private let lowFixedClocks: [Int64]

        init(division: UInt32, playback: PlaybackSettings, settings: ArpeggiatorSettings) throws {
            let clocks: Int64 = playback.extendedClocks ? 48 : 24
            var a = Int64(division)
            var b = clocks
            while b != 0 { (a, b) = (b, a % b) }
            quantumTicks = Int64(division) / a
            quantumClocks = clocks / a
            var rateGCD = Int64(settings.rateNumerator)
            var remainder = Int64(settings.rateDenominator)
            while remainder != 0 { (rateGCD, remainder) = (remainder, rateGCD % remainder) }
            let numerator = Int64(settings.rateNumerator) / rateGCD
            let denominator = Int64(settings.rateDenominator) / rateGCD
            guard (4 * clocks) % denominator == 0 else {
                throw ArpeggiatorError.unsupportedTiming("Rate must be an exact positive number of hardware clocks.")
            }
            let (stepClocks, overflow) = numerator.multipliedReportingOverflow(by: 4 * clocks / denominator)
            guard !overflow else {
                throw ArpeggiatorError.unsupportedTiming("Rate duration exceeds the document clock range.")
            }
            guard stepClocks > 0, stepClocks % quantumClocks == 0 else {
                throw ArpeggiatorError.unsupportedTiming("Rate does not fit the shared document/GBA clock lattice.")
            }
            let quanta = stepClocks / quantumClocks
            let minimum: Int64 = settings.insert == .off ? 1 : 2
            guard quanta >= minimum else {
                throw ArpeggiatorError.unsupportedTiming("Insert requires at least two shared clock quanta per step.")
            }
            let (ticks, ticksOverflow) = quanta.multipliedReportingOverflow(by: quantumTicks)
            guard !ticksOverflow, ticks <= Int64(UInt32.max) else {
                throw ArpeggiatorError.unsupportedTiming("Rate duration exceeds the document tick range.")
            }
            stepTicks = ticks
            // A 100% shuffle delays the odd onset by a whole step before bounding.
            let requested = (Double(quanta) * Double(settings.shuffle) / 100).rounded()
            let offset = min(Int64(requested), quanta - minimum)
            shuffleTicks = offset * quantumTicks
            var fixed: [Int64] = []
            for clock in 1..<96 where Int64(clock) % quantumClocks == 0 {
                let duration = Int64(clock) / quantumClocks * quantumTicks
                let effective = mid2agbEffectiveDuration(
                    duration, division: division, extendedClocks: playback.extendedClocks, exactGate: playback.exactGate
                )
                if effective == clock { fixed.append(Int64(clock)) }
            }
            lowFixedClocks = fixed
        }

        func duration(target: Double, maximum: Int64) throws -> Int64 {
            let maximumClocks = maximum / quantumTicks * quantumClocks
            let targetClocks = target / Double(quantumTicks) * Double(quantumClocks)
            var best: Int64?
            var distance = Double.infinity
            func consider(_ clock: Int64) {
                guard clock > 0, clock <= maximumClocks else { return }
                let delta = abs(Double(clock) - targetClocks)
                if delta < distance || (delta == distance && clock > (best ?? 0)) {
                    best = clock
                    distance = delta
                }
            }
            for clock in lowFixedClocks { consider(clock) }
            let minimumLarge = (96 + quantumClocks - 1) / quantumClocks
            let maximumLarge = maximumClocks / quantumClocks
            if minimumLarge <= maximumLarge {
                let nearest = Int64((targetClocks / Double(quantumClocks)).rounded())
                consider(min(max(nearest, minimumLarge), maximumLarge) * quantumClocks)
            }
            guard let best else {
                throw ArpeggiatorError.unsupportedTiming(
                    "No positive gate duration fits this slot on the shared lattice under the current Exact Gate policy."
                )
            }
            return best / quantumClocks * quantumTicks
        }
    }

    private struct Output {
        let track: Int
        let end: Int64
        let timing: Timing
        let settings: ArpeggiatorSettings
        var notes: [NewNote] = []
        var dropped = 0
        private var lastByPitch: [Int?] = Array(repeating: nil, count: 128)
        private var pendingTie: Range<Int> = 0..<0

        init(track: Int, end: Int64, timing: Timing, settings: ArpeggiatorSettings) {
            self.track = track
            self.end = end
            self.timing = timing
            self.settings = settings
        }

        mutating func emit(_ members: [Member], at tick: Int64, slotEnd: Int64, accented: Bool) throws {
            var sounding: [Member] = []
            var seen: Set<Int> = []
            for member in members {
                let pitch = member.pitch + settings.transpose
                guard (0...127).contains(pitch) else {
                    dropped += 1
                    continue
                }
                let master = Double(member.velocity) * Double(settings.masterVelocity) / 100
                let accent = accented ? Double(100 + settings.accentAmount) / 100 : 1
                let velocity = Int((master * accent).rounded())
                guard velocity > 0, seen.insert(pitch).inserted else { continue }
                sounding.append(Member(pitch: pitch, velocity: min(127, velocity)))
            }
            guard !sounding.isEmpty else { return }
            if settings.gate == 101 { try resolveTie(until: tick) }
            let beginning = notes.count
            let maximum = slotEnd - tick
            let duration = try timing.duration(
                target: Double(maximum) * Double(min(settings.gate, 100)) / 100, maximum: maximum)
            for member in sounding {
                guard notes.count < Arpeggiator.limit else { throw ArpeggiatorError.outputTooLarge }
                if let previous = lastByPitch[member.pitch] {
                    let available = tick - Int64(notes[previous].tick)
                    if Int64(notes[previous].duration) > available {
                        notes[previous].duration = Tick(
                            try timing.duration(target: Double(available), maximum: available))
                    }
                }
                lastByPitch[member.pitch] = notes.count
                notes.append(
                    NewNote(
                        track: track, tick: Tick(tick), pitch: UInt8(member.pitch), duration: Tick(duration),
                        velocity: UInt8(member.velocity)))
            }
            if settings.gate == 101 { pendingTie = beginning..<notes.count }
        }

        private mutating func resolveTie(until tick: Int64) throws {
            for index in pendingTie {
                let maximum = tick - Int64(notes[index].tick)
                notes[index].duration = Tick(try timing.duration(target: Double(maximum), maximum: maximum))
            }
            pendingTie = 0..<0
        }

        mutating func finish() throws {
            if settings.gate == 101 { try resolveTie(until: end) }
        }
    }
}
