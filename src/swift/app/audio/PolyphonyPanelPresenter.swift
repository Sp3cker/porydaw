import Foundation
import PorydawCore
import PorydawDocument
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

struct PolyphonyCounterValue: Equatable {
    var name: String
    var dropped: Int
    var cutOff: Int
    var tailCut: Int
    var flashAlpha: Double
}

@MainActor
@QtBridgeable
public final class PolyphonyCounterRow {
    public var name: String
    public var dropped: Int
    public var cutOff: Int
    public var tailCut: Int
    public var flashAlpha: Double

    @QtIgnored var current: PolyphonyCounterValue

    init(_ value: PolyphonyCounterValue) {
        current = value
        name = value.name
        dropped = value.dropped
        cutOff = value.cutOff
        tailCut = value.tailCut
        flashAlpha = value.flashAlpha
    }

    @QtIgnored
    func update(_ next: PolyphonyCounterValue) -> Bool {
        guard next != current else { return false }
        current = next
        publish(\.name, next.name)
        publish(\.dropped, next.dropped)
        publish(\.cutOff, next.cutOff)
        publish(\.tailCut, next.tailCut)
        publish(\.flashAlpha, next.flashAlpha)
        return true
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
public final class PolyphonyPanelPresenter: QmlUncreatable {
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
    private var previousCounters: [(UInt32, UInt32, UInt32)] = []
    private var flashUntil: [ContinuousClock.Instant] = []
    private var trackNames: [String] = []
    private var voiceNames: [String] = []
    private var ticksPerBeat: UInt32 = 24
    private var signatures: [PlaybackTimeSignature] = []
    private var lastChannelSnapshot: AudioPolySnapshot?
    @QtIgnored public var onJump: ((UInt32, Int, Int, Double) -> Void)?

    public init() {}

    @QtIgnored
    public func attach(audio: NativeAudio?) {
        self.audio = audio
        audio?.setPolyDebugInvert(visible && invertChecked)
        if visible { poll() }
    }

    /// Rebind the selected document, without carrying its diagnostic rows to a new song.
    @QtIgnored
    public func setContext(session: DocumentSession?) {
        trackNames =
            session.map { document in
                (0..<Int(MAX_TRACKS)).map { document.document.trackName($0) }
            } ?? []
        voiceNames =
            session?.bankSlots.enumerated().map { index, slot in
                VoiceLanePolicy.label(slot: index, view: slot)
            } ?? []
        ticksPerBeat = UInt32(max(1, session?.document.ticksPerBeat ?? 24))
        signatures =
            session?.document.timeSignatures.map {
                PlaybackTimeSignature(
                    tick: $0.tick, numerator: $0.numerator, denominatorPowerOfTwo: $0.denominatorPower)
            } ?? []
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
    public func update(_ snapshot: AudioPolySnapshot, now: ContinuousClock.Instant = .now) {
        showingShadow = snapshot.invert
        let pcmCount = min(Int(snapshot.maxPcmChannels), Int(MAX_PCM_CHANNELS), snapshot.pcm.count)
        if lastChannelSnapshot.map({ Self.sameChannels($0, snapshot) }) != true {
            syncModel(
                pcm, makeChannels(snapshot.pcm.prefix(pcmCount), cgb: false, shadow: false),
                matches: { $0.label == $1.label && $0.state == $1.state })
            syncModel(
                cgb, makeChannels(snapshot.cgb.prefix(Int(MAX_CGB_CHANNELS)), cgb: true, shadow: false),
                matches: { $0.label == $1.label && $0.state == $1.state })
            syncModel(
                shadowPcm,
                snapshot.invert
                    ? makeChannels(
                        snapshot.pcm.dropFirst(Int(MAX_PCM_CHANNELS))
                            .prefix(Int(MAX_PCM_CHANNELS)), cgb: false, shadow: true) : [],
                matches: { $0.label == $1.label && $0.state == $1.state })
            syncModel(
                shadowCgb,
                snapshot.invert
                    ? makeChannels(
                        snapshot.cgb.dropFirst(Int(MAX_CGB_CHANNELS))
                            .prefix(Int(MAX_CGB_CHANNELS)), cgb: true, shadow: true) : [],
                matches: { $0.label == $1.label && $0.state == $1.state })
            lastChannelSnapshot = snapshot
        }

        if snapshot.eventTotal < seenTotal {
            seenTotal = 0
            previousCounters.removeAll()
            flashUntil.removeAll()
            events.update {
                events.replaceSubrange(0..<events.count, with: [])
            }
            publish(\.eventCount, 0)
        }
        let capacity = snapshot.events.count
        if capacity > 0 {
            let first = max(
                seenTotal,
                snapshot.eventTotal > UInt32(capacity)
                    ? snapshot.eventTotal - UInt32(capacity) : 0)
            if first < snapshot.eventTotal {
                events.update {
                    for index in first..<snapshot.eventTotal {
                        events.insert(makeEvent(snapshot.events[Int(index) % capacity]), at: 0)
                    }
                    if events.count > 500 {
                        events.replaceSubrange(500..<events.count, with: [])
                    }
                }
                publish(\.eventCount, events.count)
            }
        }
        seenTotal = snapshot.eventTotal

        var current: [PolyphonyCounterValue] = []
        let count = min(snapshot.drop.count, snapshot.steal.count, snapshot.tailCut.count)
        if previousCounters.count != count {
            previousCounters = Array(repeating: (0, 0, 0), count: count)
            flashUntil = Array(repeating: now, count: count)
            for i in 0..<count {
                previousCounters[i] = (snapshot.drop[i], snapshot.steal[i], snapshot.tailCut[i])
            }
        }
        for i in 0..<count {
            let drop = snapshot.drop[i]
            let steal = snapshot.steal[i]
            let tail = snapshot.tailCut[i]
            let previous = previousCounters[i]
            if drop > previous.0 || steal > previous.1 || tail > previous.2 {
                flashUntil[i] = now.advanced(by: .seconds(1))
            }
            previousCounters[i] = (drop, steal, tail)
            guard drop != 0 || steal != 0 || tail != 0 else { continue }
            let name = i < trackNames.count ? trackNames[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let remaining = now.duration(to: flashUntil[i]).components
            let alpha =
                now < flashUntil[i]
                ? 0.55 * (Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18) : 0
            current.append(
                PolyphonyCounterValue(
                    name: name.isEmpty ? "Track \(i + 1)" : name,
                    dropped: Int(drop), cutOff: Int(steal), tailCut: Int(tail), flashAlpha: alpha))
        }
        syncRetained(counters, current, make: PolyphonyCounterRow.init, update: { $0.update($1) })
        publish(\.counterCount, current.count)
    }

    public func activateEvent(index: Int, devicePixelRatio: Double) {
        guard index >= 0, index < events.count else { return }
        let row = events[index]
        guard row.tick >= 0 else { return }
        onJump?(UInt32(row.tick), row.track, row.key, devicePixelRatio)
    }

    @QtIgnored
    public func clear() {
        seenTotal = 0
        previousCounters.removeAll()
        flashUntil.removeAll()
        events.reset(to: [])
        counters.reset(to: [])
        pcm.reset(to: [])
        cgb.reset(to: [])
        shadowPcm.reset(to: [])
        lastChannelSnapshot = nil
        shadowCgb.reset(to: [])
        publish(\.counterCount, 0)
        publish(\.eventCount, 0)
        publish(\.showingShadow, false)
    }

    private static func sameChannels(
        _ old: AudioPolySnapshot,
        _ new: AudioPolySnapshot
    ) -> Bool {
        guard old.maxPcmChannels == new.maxPcmChannels, old.invert == new.invert else {
            return false
        }
        let pcmCount = min(Int(new.maxPcmChannels), Int(MAX_PCM_CHANNELS))
        guard sameChannelSlice(old.pcm.prefix(pcmCount), new.pcm.prefix(pcmCount)),
            sameChannelSlice(
                old.cgb.prefix(Int(MAX_CGB_CHANNELS)),
                new.cgb.prefix(Int(MAX_CGB_CHANNELS)))
        else { return false }
        guard new.invert else { return true }
        return sameChannelSlice(
            old.pcm.dropFirst(Int(MAX_PCM_CHANNELS)).prefix(Int(MAX_PCM_CHANNELS)),
            new.pcm.dropFirst(Int(MAX_PCM_CHANNELS)).prefix(Int(MAX_PCM_CHANNELS)))
            && sameChannelSlice(
                old.cgb.dropFirst(Int(MAX_CGB_CHANNELS)).prefix(Int(MAX_CGB_CHANNELS)),
                new.cgb.dropFirst(Int(MAX_CGB_CHANNELS)).prefix(Int(MAX_CGB_CHANNELS)))
    }

    private static func sameChannelSlice(
        _ first: ArraySlice<AudioPolyChannel>,
        _ second: ArraySlice<AudioPolyChannel>
    ) -> Bool {
        guard first.count == second.count else { return false }
        for (old, new) in zip(first, second) {
            if old.on != new.on || old.releasing != new.releasing
                || old.track != new.track || old.midiKey != new.midiKey
            {
                return false
            }
        }
        return true
    }

    private func makeChannels(
        _ channels: ArraySlice<AudioPolyChannel>, cgb isCgb: Bool,
        shadow: Bool
    ) -> [PolyphonyChannelRow] {
        channels.enumerated().map { index, channel in
            let state = !channel.on ? 0 : shadow ? 3 : channel.releasing ? 2 : 1
            let label: String
            if channel.on {
                let track = Int(channel.track) + 1
                let key = midiKeyName(Int(channel.midiKey))
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
        let voice =
            voiceIndex < voiceNames.count
            ? voiceNames[voiceIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let who =
            "Trk \(Int(event.trackIndex) + 1)  \(midiKeyName(Int(event.midiKey))) (\(voice.isEmpty ? "voice \(voiceIndex)" : voice))"
        let suffix: String
        switch event.type {
        case 0: suffix = "dropped (no channel available)"
        case 1: suffix = "cut off by Trk \(Int(event.byTrack) + 1)"
        default: suffix = "release tail cut by Trk \(Int(event.byTrack) + 1)"
        }
        return PolyphonyEventRow(
            text: "\(pos) | \(who): \(suffix)", kind: Int(event.type),
            tick: tick, track: Int(event.trackIndex), key: Int(event.midiKey))
    }

    private func formatPosition(_ tick: UInt32) -> String {
        let position = MusicalPosition(tick: tick, signatures: signatures, ticksPerBeat: ticksPerBeat)
        return "\(position.bar):\(position.beat).\(position.fraction)"
    }

    private static let cgbNames = ["Sq1", "Sq2", "Wave", "Noise"]
}
