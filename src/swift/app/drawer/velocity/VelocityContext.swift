import Foundation
import PorydawCore

// Velocity maps resolve from the published bank's owned per-key native facts.
// A split without a note key is keyless; absent or invalid child facts never
// silently borrow the top-level or first-child map.

// MARK: - Voice/value context

/// `drawerContextTick`: the shared playhead's tick rounded to the nearest whole
/// tick, the context position drawer pages resolve voices at.
func velocityContextTick(_ tick: Double) -> Tick {
    guard tick.isFinite, tick > 0 else { return 0 }
    guard tick < Double(TimeDefaults.maxTick) else { return TimeDefaults.maxTick }
    return Tick((tick + 0.5).rounded(.down))
}

/// What the page knows about the active voice's velocity mapping.
public enum VelocityContextStatus: Int, Sendable {
    /// The voice resolves to an exact `VelocityMap`.
    case resolved = 0
    /// No program at this tick, or the program's slot publishes no parsed voice
    /// (blank, read-only and broken lines publish none).
    case unresolvedVoice = 1
    /// A split context without a note key.
    case keysplitSubvoice = 2
    /// Missing subgroup/table, invalid key, or a nested/invalid child.
    case invalidSubvoice = 3
}

/// One resolved voice context plus where it came from. `endTick` is the next
/// voice change's tick, or `nil` when the context runs to the song's end.
public struct VelocityVoiceContext: Sendable {
    public var status: VelocityContextStatus
    public var map: VelocityMap
    public var slot: Int
    public var endTick: Tick?
    public var symbol: String

    public init(status: VelocityContextStatus,
                map: VelocityMap = VelocityMap(voiceKind: .unresolved),
                slot: Int = -1, endTick: Tick? = nil, symbol: String = "") {
        self.status = status
        self.map = map
        self.slot = slot
        self.endTick = endTick
        self.symbol = symbol
    }

    /// Exact-map editing is available only for a resolved context.
    public var editable: Bool { status == .resolved }

    public var diagnostic: String {
        switch status {
        case .resolved:
            return ""
        case .unresolvedVoice:
            return "No parsed voice publishes program \(slot); exact velocity editing is "
                + "unavailable for this context."
        case .keysplitSubvoice:
            return "Program \(slot) is a keysplit/drumkit voice; select a note to resolve its key."
        case .invalidSubvoice:
            return "Program \(slot) has no valid subvoice for this note key."
        }
    }
}

/// The stable identity used to decide whether a context presentation changed.
struct VelocityContextKey: Equatable {
    var slot: Int
    var status: Int
    var playing: Bool

    init(context: VelocityVoiceContext, playing: Bool) {
        slot = context.slot
        status = context.status.rawValue
        self.playing = playing
    }
}

/// Pure program-span and per-note mapping over published bank facts.
public enum VelocityContextPolicy {
    /// The track's first program, then the last voice change at or before
    /// `tick`; the returned end tick is the next change.
    public static func slot(firstProgram: Int, tick: Tick,
                            voiceChanges: [LanePoint]) -> (slot: Int, endTick: Tick?) {
        var slot = firstProgram
        var endTick: Tick?
        for change in voiceChanges where change.tick <= tick {
            slot = change.value
        }
        for change in voiceChanges where change.tick > tick {
            endTick = change.tick
            break
        }
        return (slot, endTick)
    }

    /// The top-level voice kind a bank macro names, or `nil` for a keysplit or
    /// drumkit macro whose resolution needs subvoice data.
    public static func voiceKind(macro: Int32) -> VoiceKind? {
        switch macro {
        case BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
             BankVoiceMacro.directSoundAlt:
            return .directSound
        case BankVoiceMacro.square1, BankVoiceMacro.square1Alt:
            return .square1
        case BankVoiceMacro.square2, BankVoiceMacro.square2Alt:
            return .square2
        case BankVoiceMacro.programmableWave, BankVoiceMacro.programmableWaveAlt:
            return .wave
        case BankVoiceMacro.noise, BankVoiceMacro.noiseAlt:
            return .noise
        default:
            return nil
        }
    }

    /// One context from the published bank slots.
    public static func resolve(slot: Int, endTick: Tick?, slots: [BankSlotView], key: Int? = nil)
        -> VelocityVoiceContext
    {
        guard slot >= 0, slots.indices.contains(slot), let voice = slots[slot].voice else {
            return VelocityVoiceContext(status: .unresolvedVoice, slot: slot, endTick: endTick)
        }
        let macro: Int32
        if voice.macro == BankVoiceMacro.keysplit || voice.macro == BankVoiceMacro.keysplitAll {
            guard let key else {
                return VelocityVoiceContext(status: .keysplitSubvoice,
                                            map: VelocityMap(voiceKind: .keyless),
                                            slot: slot, endTick: endTick, symbol: voice.symbol)
            }
            guard let child = slots[slot].subvoiceMacro(forKey: key) else {
                return VelocityVoiceContext(status: .invalidSubvoice,
                                            map: VelocityMap(voiceKind: .invalid),
                                            slot: slot, endTick: endTick, symbol: voice.symbol)
            }
            macro = child
        } else {
            macro = voice.macro
        }
        guard let kind = voiceKind(macro: macro) else {
            return VelocityVoiceContext(status: .invalidSubvoice,
                                        map: VelocityMap(voiceKind: .invalid),
                                        slot: slot, endTick: endTick, symbol: voice.symbol)
        }
        return VelocityVoiceContext(status: .resolved, map: VelocityMap(voiceKind: kind),
                                    slot: slot, endTick: endTick, symbol: voice.symbol)
    }

    /// Resolves the program span and its value mapping in one pure operation.
    static func resolve(firstProgram: Int, tick: Tick, voiceChanges: [LanePoint],
                        slots: [BankSlotView], key: Int? = nil) -> VelocityVoiceContext {
        let span = slot(firstProgram: firstProgram, tick: tick, voiceChanges: voiceChanges)
        return resolve(slot: span.slot, endTick: span.endTick, slots: slots, key: key)
    }

    /// Resolves the context presented by a selection. Compatible PSG notes keep
    /// their intrinsic map; other resolved selections use the continuous domain.
    static func presentation(selectedNotes: [Note], effectiveTick: Tick,
                             resolve: (Tick, Int?) -> VelocityVoiceContext) -> VelocityVoiceContext {
        guard let first = selectedNotes.first else { return resolve(effectiveTick, nil) }
        let source = resolve(first.tick, Int(first.pitch))
        guard source.status == .resolved else { return source }
        var compatible = source.map.isPSG
        for note in selectedNotes.dropFirst() {
            let context = resolve(note.tick, Int(note.pitch))
            guard context.status == .resolved else { return context }
            if !context.map.compatible(with: source.map) { compatible = false }
        }
        return compatible ? source : continuous(from: source)
    }

    /// A selection that cannot share one intrinsic map uses the continuous
    /// 1–127 domain while retaining its source span and identity.
    private static func continuous(from source: VelocityVoiceContext) -> VelocityVoiceContext {
        var resolved = source
        resolved.map = VelocityMap(voiceKind: .unresolved)
        return resolved
    }
}
