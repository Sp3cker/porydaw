import PorydawPlaybackNative

private func withKeysplitEngine(_ report: CheckReport, cppID: String,
                                _ check: (UnsafeMutablePointer<M4AEngine>) -> Void) {
    guard let engine = PlaybackCheckEngine() else {
        report.fail(cppID, "M4A engine initialization failed")
        return
    }
    let voices = UnsafeMutablePointer<ToneData>.allocate(capacity: 128)
    let sub = UnsafeMutablePointer<ToneData>.allocate(capacity: 128)
    let split = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    voices.initialize(repeating: ToneData(), count: 128)
    sub.initialize(repeating: ToneData(), count: 128)
    split.initialize(repeating: 0, count: 128)
    defer {
        m4a_engine_set_voicegroup(engine.pointer, nil)
        voices.deinitialize(count: 128)
        sub.deinitialize(count: 128)
        split.deinitialize(count: 128)
        voices.deallocate()
        sub.deallocate()
        split.deallocate()
    }
    voices[5].type = UInt8(VOICE_KEYSPLIT)
    voices[5].subGroup = UnsafeMutableRawPointer(sub)
    voices[5].keySplitTable = split
    m4a_engine_set_voicegroup(engine.pointer, voices)
    check(engine.pointer)
}

internal func checkMidiEngineBounds(_ report: CheckReport) {
    let programID = "midienginecheck/MidiEngineBoundsTest::programChangesRejectOutOfRangeValues"
    withKeysplitEngine(report, cppID: programID) { engine in
        m4a_engine_program_change(engine, 0, 5)
        report.expectEqual(expected: UInt8(5), actual: engine.pointee.tracks.0.currentProgram,
                           cppID: programID, what: "valid program selects keysplit voice")
        m4a_engine_program_change(engine, 0, 128)
        m4a_engine_program_change(engine, 0, 255)
        report.expectEqual(expected: UInt8(5), actual: engine.pointee.tracks.0.currentProgram,
                           cppID: programID, what: "invalid programs retain selection")
    }

    let keyID = "midienginecheck/MidiEngineBoundsTest::noteOnsRejectOutOfRangeKeys"
    withKeysplitEngine(report, cppID: keyID) { engine in
        m4a_engine_program_change(engine, 0, 5)
        m4a_engine_note_on(engine, 0, 128, 100)
        m4a_engine_note_on(engine, 0, 255, 100)
        m4a_engine_note_off(engine, 0, 255)
        withUnsafePointer(to: &engine.pointee.pcmChannels) { storage in
            let channels = UnsafeRawPointer(storage).assumingMemoryBound(to: M4APCMChannel.self)
            for index in 0..<Int(TOTAL_PCM_CHANNELS) {
                report.expect(channels[index].status & playbackCheckChannelOn == 0,
                              cppID: keyID, message: "PCM channel \(index) remains off")
            }
        }
    }
}
