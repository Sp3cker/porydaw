import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
extension ApplicationSession {
    func connectPolyphonyJump() {
        polyphony.onJump = { [weak self] tick, track, key, dpr in
            guard let session = self?.workspace?.session else { return }
            let previousNotes = session.selectedNoteOrder
            session.selectPrimaryTrack(track)
            guard let note = session.document.notes(in: track).last(where: {
                $0.tick <= tick && Int($0.pitch) == key
                    && UInt64(tick) < UInt64($0.tick) + UInt64($0.duration)
            }) else {
                session.setSelectedNotes(previousNotes)
                return
            }
            session.setSelectedNotes([note.id])
            _ = session.mutateCamera { $0.ensureKeyVisible(key) }
            session.editCursor = tick
            _ = session.mutateCamera { $0.ensureTickVisible(UInt64(tick), dpr: dpr) }
        }
    }

    func connectVoiceAudition() {
        voiceList.onAuditionVoice = { [weak self] voice, key, velocity in
            guard (0..<128).contains(voice), (0..<128).contains(key),
                  (0..<128).contains(velocity) else { return }
            self?.audio?.previewVoice(program: UInt8(voice), key: UInt8(key),
                                      velocity: UInt8(velocity))
        }
        voiceList.onVoicegroupChangeRequested = { [weak self] arg in
            guard let self, let session = self.selectedDocument else { return }
            Task { [weak self, weak session] in
                guard let session else { return }
                do {
                    try await session.selectVoicegroup(arg)
                } catch ProjectServiceError.operationFailed(let message) {
                    self?.lastSaveError = message
                } catch {
                    self?.lastSaveError = String(describing: error)
                }
                if self?.selectedDocument === session {
                    self?.voiceList.refresh(from: session)
                }
            }
        }
        voiceList.onNewVoicegroupRequested = { [weak self] in
            self?.voiceList.presentNewVoicegroup()
        }
        voiceList.onNewVoicegroupFailed = { [weak self] message in
            self?.lastSaveError = message
        }
        voiceList.onStatusMessage = { [weak self] message in
            self?.statusMessage(message: message)
        }
        voiceList.onSaveRequested = { [weak self] in self?.requestSave() }
        voiceList.onPickerSampleInfoRequested = { [weak self] in
            guard let self, let service = self.catalogService,
                  let session = self.selectedDocument else { return }
            self.voiceList.pickerInfoRevision += 1
            let revision = self.voiceList.pickerInfoRevision
            self.voiceList.pickerSampleInfo = [:]
            Task { [weak self, weak session] in
                let info = await service.pickerSampleInfo()
                guard let self, let session, self.selectedDocument === session,
                      self.catalogService === service,
                      self.voiceList.pickerInfoRevision == revision else { return }
                self.voiceList.pickerSampleInfo = info
                self.voiceList.pickerInfoRevision += 1
            }
        }
        voiceList.onSampleAuditionRequested = { [weak self] symbol, kind, adsr in
            guard let self, let service = self.catalogService,
                  let session = self.selectedDocument else { return }
            self.audio?.auditionSampleOff()
            self.pickerAuditionRevision += 1
            let revision = self.pickerAuditionRevision
            Task { [weak self, weak session] in
                let sound = await service.pickerSound(symbol: symbol, kind: kind)
                guard let self, let session, self.selectedDocument === session,
                      self.catalogService === service,
                      self.pickerAuditionRevision == revision,
                      let audio = self.audio, let sound else { return }
                let chosen = AudioADSR(
                    attack: UInt8(truncatingIfNeeded: adsr.attack),
                    decay: UInt8(truncatingIfNeeded: adsr.decay),
                    sustain: UInt8(truncatingIfNeeded: adsr.sustain),
                    release: UInt8(truncatingIfNeeded: adsr.release))
                switch sound {
                case let .sample(bytes, frequency, loopStart, looped, toneKey, envelope):
                    let envelope = envelope.map {
                        AudioADSR(attack: $0.0, decay: $0.1, sustain: $0.2, release: $0.3)
                    } ?? chosen
                    _ = audio.auditionSample(samples: bytes, frequency: frequency,
                                             loopStart: loopStart, looped: looped,
                                             key: 60, adsr: envelope, toneKey: toneKey)
                case let .wave(bytes, envelope):
                    let envelope = envelope.map {
                        AudioADSR(attack: $0.0, decay: $0.1, sustain: $0.2, release: $0.3)
                    } ?? chosen
                    _ = audio.auditionWave(wave16: bytes, key: 60, adsr: envelope)
                }
            }
        }
        voiceList.onSampleAuditionStopRequested = { [weak self] in
            self?.pickerAuditionRevision += 1
            self?.audio?.auditionSampleOff()
        }
    }

    func playImpl() {
        guard let audio, audio.songLoaded else { return }
        if audio.transport == AudioTransportState.stopped.rawValue,
           let session = workspace?.session {
            publishSeek(tick: session.editCursor, timeline: session.timeline, startPlayback: true)
            transportBar.refresh()
        } else {
            audio.play()
            refreshTransportPresentation()
        }
    }

    func playPauseImpl() {
        guard let audio, audio.songLoaded else { return }
        if audio.transport == SharedPlayheadPolicy.playingTransport {
            audio.pause()
            refreshTransportPresentation()
        } else if let session = workspace?.session {
            publishSeek(tick: session.editCursor, timeline: session.timeline, startPlayback: true)
            transportBar.refresh()
        } else {
            transportBar.refresh()
        }
    }

    func stopImpl() {
        audio?.stop()
        // Stop's rewind comes from the audio service; this presents whatever
        // sample and transport the service reports now. No tick is synthesized.
        refreshTransportPresentation()
    }

    func goToStartImpl() {
        guard let workspace else { return }
        let session = workspace.session
        session.editCursor = 0
        _ = session.mutateCamera { $0.setHScroll($0.snapshot.minHScroll) }
        if let audio, audio.songLoaded,
           audio.transport != AudioTransportState.stopped.rawValue {
            publishSeek(tick: 0, timeline: session.timeline, startPlayback: false)
        } else {
            playhead.refreshImmediate()
        }
        transportBar.refresh()
    }

    func publishSeek(tick: Tick, timeline: PlaybackTimeline, startPlayback: Bool) {
        guard let audio else { return }
        let target = timeline.sample(for: tick)
        audio.seek(sample: target)
        if startPlayback {
            audio.play()
        }
        playhead.observe(sample: target, transport: audio.transport)
    }

    /// Fork commitEditCursor egress: commits seek paused/playing playback to
    /// the cursor; stopped commits only move the cursor, background tabs never seek.
    func seekToTick(_ tick: Tick, in origin: DocumentWorkspace) {
        guard workspace === origin, let audio, audio.songLoaded,
            audio.transport != AudioTransportState.stopped.rawValue
        else { return }
        publishSeek(tick: tick, timeline: origin.session.timeline, startPlayback: false)
        transportBar.refresh()
    }

    private func refreshTransportPresentation() {
        playhead.refreshImmediate()
        transportBar.refresh()
    }

    func resyncTransportAfterEngineTransition() {
        guard let audio, audio.songLoaded else { return }
        guard transportBar.state != Int(audio.transport) + 1 else { return }
        refreshTransportPresentation()
    }
}
