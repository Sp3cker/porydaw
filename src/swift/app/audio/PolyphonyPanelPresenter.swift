import Foundation
import PorydawCore
import PorydawPlaybackNative
import QtBridge
import PorydawAppAudio

@MainActor
@QtBridgeable
public final class PolyphonyChannelRow {
    public var label: String
    public var state: Int

    init(label: String, state: Int) {
        self.label = label
        self.state = state
    }
}

@MainActor
@QtBridgeable
public final class PolyphonyCounterRow {
    public var name: String
    public var dropped: Int
    public var cutOff: Int
    public var tailCut: Int
    public var flash: Bool

    init(name: String, dropped: Int, cutOff: Int, tailCut: Int, flash: Bool) {
        self.name = name
        self.dropped = dropped
        self.cutOff = cutOff
        self.tailCut = tailCut
        self.flash = flash
    }
}

@MainActor
@QtBridgeable
public final class PolyphonyEventRow {
    public var text: String
    public var kind: Int
    public var tick: Double
    public var track: Int
    public var key: Int

    init(text: String, kind: Int, tick: Double, track: Int, key: Int) {
        self.text = text
        self.kind = kind
        self.tick = tick
        self.track = track
        self.key = key
    }
}

/// UI-thread projection of the renderer's diagnostic ring. Poll only while visible.
@MainActor
@QtBridgeable
public final class PolyphonyPanelPresenter {
    public var pcm: QListModel<PolyphonyChannelRow> = QListModel()
    public var cgb: QListModel<PolyphonyChannelRow> = QListModel()
    public var shadowPcm: QListModel<PolyphonyChannelRow> = QListModel()
    public var shadowCgb: QListModel<PolyphonyChannelRow> = QListModel()
    public var counters: QListModel<PolyphonyCounterRow> = QListModel()
    public var events: QListModel<PolyphonyEventRow> = QListModel()

    @QtTracked public var invertChecked = false
    @QtTracked public var showingShadow = false
    @QtTracked public var counterCount = 0
    @QtTracked public var eventCount = 0

    private weak var audio: NativeAudio?
    private var visible = false
    private var seenTotal: UInt32 = 0
    private var eventRows: [PolyphonyEventRow] = []
    private var previousCounters: [(UInt32, UInt32, UInt32)] = []
    private var flashUntil: [ContinuousClock.Instant] = []
    private var trackNames: [String] = []
    private var voiceNames: [String] = []
    private var ticksPerBeat: UInt32 = 24
    private var signatures: [TimeSignature] = []
    private var lastChannelSnapshot: AudioPolySnapshot?
    @QtIgnored public var onJump: ((UInt32, Int, Int, Double) -> Void)?

    public init() {}

    @QtIgnored
    public func attach(audio: NativeAudio?) {
        self.audio = audio
        invertChecked = audio?.polyDebugInvert ?? false
    }

    /// Rebind the selected document, without carrying its diagnostic rows to a new song.
    @QtIgnored
    public func setContext(session: DocumentSession?) {
        trackNames = session.map { document in
            (0..<Int(MAX_TRACKS)).map { document.document.trackName($0) }
        } ?? []
        voiceNames = session?.bankSlots.enumerated().map { index, slot in
            VoiceLanePolicy.label(slot: index, view: slot)
        } ?? []
        ticksPerBeat = UInt32(max(1, session?.document.ticksPerBeat ?? 24))
        signatures = session?.document.timeSignatures ?? []
        clear()
    }

    public func setVisible(showing: Bool) {
        visible = showing
        audio?.setPolyDebugInvert(showing && invertChecked)
        if showing { poll() }
    }

    public func setInvertChecked(checked: Bool) {
        invertChecked = checked
        audio?.setPolyDebugInvert(visible && checked)
        if visible { poll() }
    }

    public func reset() {
        clear()
        audio?.resetPolyStats()
    }

    public func poll() {
        guard visible, let audio else { return }
        update(audio.polySnapshot())
    }

    @QtIgnored
    public func update(_ snapshot: AudioPolySnapshot) {
        showingShadow = snapshot.invert
        let pcmCount = min(Int(snapshot.maxPcmChannels), Int(MAX_PCM_CHANNELS), snapshot.pcm.count)
        if lastChannelSnapshot.map({ Self.sameChannels($0, snapshot) }) != true {
            // A channel repaint is necessary only when a cell's observed state changes.
            pcm.reset(to: makeChannels(snapshot.pcm.prefix(pcmCount), cgb: false, shadow: false))
            cgb.reset(to: makeChannels(snapshot.cgb.prefix(Int(MAX_CGB_CHANNELS)), cgb: true,
                                       shadow: false))
            if snapshot.invert {
                shadowPcm.reset(to: makeChannels(snapshot.pcm.dropFirst(Int(MAX_PCM_CHANNELS))
                    .prefix(Int(MAX_PCM_CHANNELS)), cgb: false, shadow: true))
                shadowCgb.reset(to: makeChannels(snapshot.cgb.dropFirst(Int(MAX_CGB_CHANNELS))
                    .prefix(Int(MAX_CGB_CHANNELS)), cgb: true, shadow: true))
            } else {
                shadowPcm.reset(to: [])
                shadowCgb.reset(to: [])
            }
            lastChannelSnapshot = snapshot
        }

        if snapshot.eventTotal < seenTotal {
            seenTotal = 0
            eventRows.removeAll()
            previousCounters.removeAll()
            flashUntil.removeAll()
            events.reset(to: [])
            eventCount = 0
        }
        let capacity = snapshot.events.count
        if capacity > 0 {
            let first = max(seenTotal, snapshot.eventTotal > UInt32(capacity)
                ? snapshot.eventTotal - UInt32(capacity) : 0)
            if first < snapshot.eventTotal {
                for index in first..<snapshot.eventTotal {
                    eventRows.insert(makeEvent(snapshot.events[Int(index) % capacity]), at: 0)
                }
                if eventRows.count > 500 { eventRows.removeLast(eventRows.count - 500) }
                events.reset(to: eventRows)
                eventCount = eventRows.count
            }
        }
        seenTotal = snapshot.eventTotal

        let now = ContinuousClock.now
        var current: [PolyphonyCounterRow] = []
        let count = min(snapshot.drop.count, snapshot.steal.count, snapshot.tailCut.count)
        if previousCounters.count != count {
            previousCounters = Array(repeating: (0, 0, 0), count: count)
            flashUntil = Array(repeating: now, count: count)
            // A first observation is a baseline, not an increase.
            for i in 0..<count {
                previousCounters[i] = (snapshot.drop[i], snapshot.steal[i], snapshot.tailCut[i])
            }
        }
        for i in 0..<count {
            let drop = snapshot.drop[i], steal = snapshot.steal[i], tail = snapshot.tailCut[i]
            let previous = previousCounters[i]
            if drop > previous.0 || steal > previous.1 || tail > previous.2 {
                flashUntil[i] = now.advanced(by: .seconds(1))
            }
            previousCounters[i] = (drop, steal, tail)
            guard drop != 0 || steal != 0 || tail != 0 else { continue }
            let name = i < trackNames.count ? trackNames[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            current.append(PolyphonyCounterRow(name: name.isEmpty ? "Track \(i + 1)" : name,
                dropped: Int(drop), cutOff: Int(steal), tailCut: Int(tail), flash: now < flashUntil[i]))
        }
        counters.reset(to: current)
        counterCount = current.count
    }

    public func activateEvent(index: Int, devicePixelRatio: Double) {
        guard eventRows.indices.contains(index) else { return }
        let row = eventRows[index]
        guard row.tick >= 0 else { return }
        onJump?(UInt32(row.tick), row.track, row.key, devicePixelRatio)
    }

    @QtIgnored
    public func clear() {
        seenTotal = 0
        eventRows.removeAll()
        previousCounters.removeAll()
        flashUntil.removeAll()
        events.reset(to: [])
        counters.reset(to: [])
        pcm.reset(to: [])
        cgb.reset(to: [])
        shadowPcm.reset(to: [])
        lastChannelSnapshot = nil
        shadowCgb.reset(to: [])
        counterCount = 0
        eventCount = 0
        showingShadow = false
    }

    private static func sameChannels(_ old: AudioPolySnapshot,
                                     _ new: AudioPolySnapshot) -> Bool {
        guard old.maxPcmChannels == new.maxPcmChannels, old.invert == new.invert else {
            return false
        }
        let pcmCount = min(Int(new.maxPcmChannels), Int(MAX_PCM_CHANNELS))
        guard sameChannels(old.pcm.prefix(pcmCount), new.pcm.prefix(pcmCount)),
              sameChannels(old.cgb.prefix(Int(MAX_CGB_CHANNELS)),
                           new.cgb.prefix(Int(MAX_CGB_CHANNELS)))
        else { return false }
        guard new.invert else { return true }
        return sameChannels(old.pcm.dropFirst(Int(MAX_PCM_CHANNELS)).prefix(Int(MAX_PCM_CHANNELS)),
                            new.pcm.dropFirst(Int(MAX_PCM_CHANNELS)).prefix(Int(MAX_PCM_CHANNELS)))
            && sameChannels(old.cgb.dropFirst(Int(MAX_CGB_CHANNELS)).prefix(Int(MAX_CGB_CHANNELS)),
                            new.cgb.dropFirst(Int(MAX_CGB_CHANNELS)).prefix(Int(MAX_CGB_CHANNELS)))
    }

    private static func sameChannels(_ first: ArraySlice<AudioPolyChannel>,
                                     _ second: ArraySlice<AudioPolyChannel>) -> Bool {
        guard first.count == second.count else { return false }
        return zip(first, second).allSatisfy { old, new in
            old.on == new.on && old.releasing == new.releasing
                && old.track == new.track && old.midiKey == new.midiKey
        }
    }

    private func makeChannels(_ channels: ArraySlice<AudioPolyChannel>, cgb isCgb: Bool,
                              shadow: Bool) -> [PolyphonyChannelRow] {
        channels.enumerated().map { index, channel in
            let state = !channel.on ? 0 : shadow ? 3 : channel.releasing ? 2 : 1
            let label: String
            if channel.on {
                let track = Int(channel.track) + 1
                let key = Self.keyName(channel.midiKey)
                label = isCgb ? "\(Self.cgbNames[index])\nT\(track) \(key)" : "T\(track)\n\(key)"
            } else {
                label = isCgb ? "\(Self.cgbNames[index])\n--" : "--"
            }
            return PolyphonyChannelRow(label: label, state: state)
        }
    }

    private func makeEvent(_ event: M4APolyEvent) -> PolyphonyEventRow {
        let tick = event.tick == UInt32.max ? -1 : Double(event.tick)
        let pos = tick < 0 ? "live" : formatPosition(event.tick)
        let voiceIndex = Int(event.program)
        let voice = voiceIndex < voiceNames.count
            ? voiceNames[voiceIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let who = "Trk \(Int(event.trackIndex) + 1)  \(Self.keyName(event.midiKey)) (\(voice.isEmpty ? "voice \(voiceIndex)" : voice))"
        let suffix: String
        switch event.type {
        case 0: suffix = "dropped (no channel available)"
        case 1: suffix = "cut off by Trk \(Int(event.byTrack) + 1)"
        default: suffix = "release tail cut by Trk \(Int(event.byTrack) + 1)"
        }
        return PolyphonyEventRow(text: "\(pos) | \(who): \(suffix)", kind: Int(event.type),
            tick: tick, track: Int(event.trackIndex), key: Int(event.midiKey))
    }

    private func formatPosition(_ tick: UInt32) -> String {
        var start: UInt64 = 0, numerator: UInt64 = 4, denominatorPower = 2, bar: UInt64 = 1
        for signature in signatures where signature.tick <= tick {
            let beat = max(UInt64(1), UInt64(ticksPerBeat) * 4 >> denominatorPower)
            let barLength = numerator * beat
            bar += (UInt64(signature.tick) - start + barLength - 1) / barLength
            start = UInt64(signature.tick)
            numerator = UInt64(max(1, signature.numerator))
            denominatorPower = Int(signature.denominatorPower)
        }
        let beat = max(UInt64(1), UInt64(ticksPerBeat) * 4 >> denominatorPower)
        let length = numerator * beat
        let offset = UInt64(tick) - start
        return "\(bar + offset / length):\(offset % length / beat + 1).\(offset % beat)"
    }

    private static let cgbNames = ["Sq1", "Sq2", "Wave", "Noise"]

    private static func keyName(_ key: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[Int(key) % 12])\(Int(key) / 12 - 1)"
    }
}
