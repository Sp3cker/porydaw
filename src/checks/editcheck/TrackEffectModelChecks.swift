import PorydawCore

private func effectModelFile() -> MidiFile {
    MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [.meta(type: 0x01, data: Array("effect fixture".utf8))], endTick: 48),
            MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 48),
            MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 48),
            MidiChunk(events: [.channel(status: 0xC2, data0: 3)], endTick: 48),
        ])
}

private func effectModelConfig(track: Int = 0) -> TrackEffectConfig {
    TrackEffectConfig(
        track: track,
        plugin: PluginEffectConfig(
            modulePath: "/fixture/MidiEffect.vst3", classUID: Array(repeating: 7, count: 16),
            name: "MIDI fixture", input: .trackNotes, pacing: .offline, prerollBars: 0))
}

@MainActor
private func expectEffectError(
    _ expected: TrackEffectError, document: SongDocument, report: CheckReport,
    id: String, action: () throws -> Void
) {
    let before = document.state
    let revision = document.revision
    let historyRevision = document.history.revision
    let historyCount = document.history.undoCount
    do {
        try action()
        report.fail(id, "expected \(expected)")
    } catch let error as TrackEffectError {
        report.expectEqual(expected: expected, actual: error, cppID: id, what: "exact effect error")
    } catch {
        report.fail(id, "unexpected effect error: \(error)")
    }
    report.expectEqual(expected: before, actual: document.state, cppID: id, what: "rejection preserves state")
    report.expectEqual(expected: revision, actual: document.revision, cppID: id, what: "rejection does not publish")
    report.expectEqual(
        expected: historyRevision, actual: document.history.revision, cppID: id,
        what: "rejection preserves history revision")
    report.expectEqual(
        expected: historyCount, actual: document.history.undoCount, cppID: id,
        what: "rejection preserves history entries")
}

@MainActor
private func effectLifecycleChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::lifecycle"
    let document = SongDocument(file: effectModelFile())
    let baseline = document.state
    let baselineRevisions = document.revisions
    var publications: [DocumentChange] = []
    document.onChange = { (change: DocumentChange) in publications.append(change) }
    let effectID = try document.addEffect(effectModelConfig())
    let added = document.state
    report.expectEqual(
        expected: [TrackEffect(id: effectID, config: effectModelConfig())], actual: document.effects,
        cppID: id, what: "add stores exactly the configured insert")
    report.expectEqual(
        expected: "add MIDI effect", actual: document.history.step(at: 0)?.label,
        cppID: id, what: "add label")
    report.expect(document.history.undoDocument(), cppID: id, message: "add undo succeeds")
    report.expectEqual(expected: baseline, actual: document.state, cppID: id, what: "add undo restores exact state")
    report.expect(document.history.redoDocument(), cppID: id, message: "add redo succeeds")
    report.expectEqual(expected: added, actual: document.state, cppID: id, what: "add redo restores exact state")

    let blob = PluginStateBlob(component: [1, 2], controller: [3])
    try document.recordPluginState(effectID, state: blob)
    let beforeUpdate = document.state
    var config = effectModelConfig(track: 2)
    config.plugin.input = .none
    config.plugin.pacing = .realtime
    config.plugin.prerollBars = 2
    try document.updateEffect(effectID, config: config)
    let updated = document.state
    report.expectEqual(expected: config, actual: document.effect(onTrack: 2)?.config, cppID: id, what: "update config")
    report.expect(document.effect(onTrack: 0) == nil, cppID: id, message: "update vacates the old track")
    report.expectEqual(
        expected: blob, actual: document.effect(onTrack: 2)?.pluginState, cppID: id, what: "config keeps state")
    report.expectEqual(
        expected: "edit MIDI effect", actual: document.history.step(at: 2)?.label,
        cppID: id, what: "config label")
    report.expect(document.history.undoDocument(), cppID: id, message: "config undo succeeds")
    report.expectEqual(expected: beforeUpdate, actual: document.state, cppID: id, what: "config undo exact state")
    report.expect(document.history.redoDocument(), cppID: id, message: "config redo succeeds")
    report.expectEqual(expected: updated, actual: document.state, cppID: id, what: "config redo exact state")

    try document.removeEffect(effectID)
    let removed = document.state
    report.expect(document.effects.isEmpty, cppID: id, message: "remove drops the insert")
    report.expectEqual(
        expected: "remove MIDI effect", actual: document.history.step(at: 3)?.label,
        cppID: id, what: "remove label")
    report.expect(document.history.undoDocument(), cppID: id, message: "remove undo succeeds")
    report.expectEqual(
        expected: updated, actual: document.state, cppID: id, what: "remove undo restores config and blob")
    report.expect(document.history.redoDocument(), cppID: id, message: "remove redo succeeds")
    report.expectEqual(expected: removed, actual: document.state, cppID: id, what: "remove redo exact state")
    report.expectEqual(
        expected: 10, actual: publications.count, cppID: id, what: "one publication per accepted edit or replay")
    report.expect(
        publications.allSatisfy { (change: DocumentChange) in change.effectsOnly && change.trackRemap == nil },
        cppID: id, message: "every effect-only change is classified without a track remap")
    report.expectEqual(
        expected: baselineRevisions, actual: document.revisions, cppID: id,
        what: "effect edits and replay leave MIDI dependency stamps alone")
}

@MainActor
private func effectValidationChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::validation"
    let document = SongDocument(file: effectModelFile())
    let first = try document.addEffect(effectModelConfig())
    let second = try document.addEffect(effectModelConfig(track: 1))
    expectEffectError(.trackHasEffect(0), document: document, report: report, id: id) {
        try document.addEffect(effectModelConfig())
    }
    expectEffectError(.trackHasEffect(0), document: document, report: report, id: id) {
        try document.addEffect(effectModelConfig(), replacing: second)
    }
    expectEffectError(.unknownEffect, document: document, report: report, id: id) {
        try document.addEffect(effectModelConfig(track: 2), replacing: first)
    }
    for track in [-1, document.engineTracks.usedTrackCount, 99] {
        expectEffectError(.invalidTrack(track), document: document, report: report, id: id) {
            try document.addEffect(effectModelConfig(track: track))
        }
        expectEffectError(.invalidTrack(track), document: document, report: report, id: id) {
            try document.updateEffect(first, config: effectModelConfig(track: track))
        }
    }
    expectEffectError(.trackHasEffect(1), document: document, report: report, id: id) {
        try document.updateEffect(first, config: effectModelConfig(track: 1))
    }
    let missing = EffectID(raw: 999)
    expectEffectError(.unknownEffect, document: document, report: report, id: id) {
        try document.removeEffect(missing)
    }
    expectEffectError(.unknownEffect, document: document, report: report, id: id) {
        try document.updateEffect(missing, config: effectModelConfig())
    }
    expectEffectError(.unknownEffect, document: document, report: report, id: id) {
        try document.recordPluginState(missing, state: PluginStateBlob(component: [], controller: []))
    }
    let empty = SongDocument(file: MidiFile(division: 24, chunks: []))
    expectEffectError(.invalidTrack(0), document: empty, report: report, id: id) {
        try empty.addEffect(effectModelConfig())
    }
}

@MainActor
private func effectReplacementChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::replacement"
    let document = SongDocument(file: effectModelFile())
    let first = try document.addEffect(effectModelConfig())
    try document.recordPluginState(first, state: PluginStateBlob(component: [4], controller: [5]))
    try document.addEffect(effectModelConfig(track: 2))
    let before = document.state
    let count = document.history.undoCount
    var replacementConfig = effectModelConfig()
    replacementConfig.plugin.name = "Replacement fixture"
    let replacement = try document.addEffect(replacementConfig, replacing: first)
    let after = document.state
    report.expect(replacement != first, cppID: id, message: "replacement mints a distinct identity")
    report.expectEqual(
        expected: count + 1, actual: document.history.undoCount, cppID: id, what: "replacement is one step")
    report.expectEqual(
        expected: [0, 2], actual: document.effects.map { (effect: TrackEffect) in effect.config.track },
        cppID: id, what: "replacement retains one insert per track in order")
    report.expectEqual(
        expected: TrackEffect(id: replacement, config: replacementConfig), actual: document.effect(onTrack: 0),
        cppID: id, what: "replacement starts without the removed plugin's blob")
    report.expect(document.history.undoDocument(), cppID: id, message: "replacement undo succeeds")
    report.expectEqual(
        expected: before, actual: document.state, cppID: id, what: "one undo restores removed insert and blob")
    report.expect(document.history.redoDocument(), cppID: id, message: "replacement redo succeeds")
    report.expectEqual(expected: after, actual: document.state, cppID: id, what: "replacement redo exact state")
}

@MainActor
private func effectGestureChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::gestures"
    let original = TrackEffect(
        id: EffectID(raw: 40), config: effectModelConfig(),
        pluginState: PluginStateBlob(component: [6], controller: [7]))
    let document = SongDocument(file: effectModelFile(), effects: [original])
    let group = HistoryGroup()
    var config = original.config
    config.plugin.prerollBars = 1
    try document.updateEffect(original.id, config: config, group: group)
    config.track = 2
    config.plugin.prerollBars = 2
    try document.updateEffect(original.id, config: config, group: group)
    report.expectEqual(
        expected: 1, actual: document.history.undoCount, cppID: id, what: "one group coalesces config updates")
    report.expect(document.history.undoDocument(), cppID: id, message: "gesture undo succeeds")
    report.expectEqual(
        expected: [original], actual: document.effects, cppID: id, what: "gesture undo restores origin and blob")
    report.expect(!document.isDirty, cppID: id, message: "gesture undo restores clean history")
    report.expect(document.history.redoDocument(), cppID: id, message: "gesture redo succeeds")
    report.expectEqual(
        expected: config, actual: document.effect(onTrack: 2)?.config, cppID: id,
        what: "gesture redo restores latest config")
    report.expectEqual(
        expected: original.pluginState, actual: document.effect(onTrack: 2)?.pluginState,
        cppID: id, what: "gesture replay preserves plugin state")
    config.plugin.name = "Separate gesture"
    try document.updateEffect(original.id, config: config, group: HistoryGroup())
    report.expectEqual(
        expected: 2, actual: document.history.undoCount, cppID: id, what: "a new group starts another step")

    let cancelled = SongDocument(file: effectModelFile(), effects: [original])
    let cancelGroup = HistoryGroup()
    try cancelled.updateEffect(original.id, config: config, group: cancelGroup)
    try cancelled.updateEffect(original.id, config: original.config, group: cancelGroup)
    report.expectEqual(
        expected: [original], actual: cancelled.effects, cppID: id, what: "cancelled gesture restores exact insert")
    report.expect(
        cancelled.history.undoCount == 0 && !cancelled.isDirty,
        cppID: id, message: "returning to origin drops the gesture step and dirt")

    let pair = SongDocument(
        file: effectModelFile(),
        effects: [original, TrackEffect(id: EffectID(raw: 41), config: effectModelConfig(track: 1))])
    let pairGroup = HistoryGroup()
    var firstConfig = original.config
    firstConfig.plugin.prerollBars = 1
    try pair.updateEffect(original.id, config: firstConfig, group: pairGroup)
    var secondConfig = effectModelConfig(track: 1)
    secondConfig.plugin.prerollBars = 2
    try pair.updateEffect(EffectID(raw: 41), config: secondConfig, group: pairGroup)
    report.expectEqual(
        expected: 2, actual: pair.history.undoCount, cppID: id,
        what: "one group never merges different effect identities")
}

@MainActor
private func effectConfigDeltaChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::configDelta"
    let original = TrackEffect(
        id: EffectID(raw: 7), config: effectModelConfig(),
        pluginState: PluginStateBlob(component: [1], controller: [2]))
    let document = SongDocument(file: effectModelFile(), effects: [original])
    let baseline = document.state
    var config = original.config
    config.plugin.prerollBars = 1
    try document.updateEffect(original.id, config: config)
    let firstEdited = document.state
    let currentBlob = PluginStateBlob(component: [8, 9], controller: [10])
    try document.recordPluginState(original.id, state: currentBlob)
    let beforeGrouped = document.state
    let group = HistoryGroup()
    config.track = 2
    config.plugin.prerollBars = 2
    try document.updateEffect(original.id, config: config, group: group)
    config.plugin.input = .none
    try document.updateEffect(original.id, config: config, group: group)
    let afterGrouped = document.state
    report.expectEqual(
        expected: 3, actual: document.history.undoCount, cppID: id,
        what: "config, plugin state and grouped config remain independent steps")
    report.expectEqual(
        expected: currentBlob, actual: document.effect(onTrack: 2)?.pluginState, cppID: id,
        what: "grouped config edits retain the newer plugin blob")

    report.expect(document.history.undoDocument(), cppID: id, message: "grouped config undo succeeds")
    report.expectEqual(
        expected: beforeGrouped, actual: document.state, cppID: id,
        what: "grouped config undo restores config without rolling back the newer blob")
    report.expect(document.history.undoDocument(), cppID: id, message: "interleaved plugin state undo succeeds")
    report.expectEqual(
        expected: firstEdited, actual: document.state, cppID: id,
        what: "only plugin state undo restores the older blob while keeping config")
    report.expect(document.history.undoDocument(), cppID: id, message: "first config undo succeeds")
    report.expectEqual(
        expected: baseline, actual: document.state, cppID: id,
        what: "first config undo restores the original config and preserves the older blob")

    report.expect(document.history.redoDocument(), cppID: id, message: "first config redo succeeds")
    report.expectEqual(
        expected: firstEdited, actual: document.state, cppID: id,
        what: "first config redo leaves the older plugin blob unchanged")
    report.expect(document.history.redoDocument(), cppID: id, message: "interleaved plugin state redo succeeds")
    report.expectEqual(
        expected: beforeGrouped, actual: document.state, cppID: id,
        what: "plugin state redo restores the newer blob without changing config")
    report.expect(document.history.redoDocument(), cppID: id, message: "grouped config redo succeeds")
    report.expectEqual(
        expected: afterGrouped, actual: document.state, cppID: id,
        what: "grouped config redo restores its final config and retains the newer blob")
}

@MainActor
private func effectPluginStateChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::pluginState"
    let original = TrackEffect(id: EffectID(raw: 12), config: effectModelConfig())
    let document = SongDocument(file: effectModelFile(), effects: [original])
    let firstBlob = PluginStateBlob(component: [0, 1, 255], controller: [])
    report.expect(!document.isDirty, cppID: id, message: "restored effects start clean")
    try document.recordPluginState(original.id, state: firstBlob)
    report.expectEqual(
        expected: 1, actual: document.history.undoCount, cppID: id, what: "finished plugin edit is exactly one step")
    report.expectEqual(
        expected: "edit plugin settings", actual: document.history.step(at: 0)?.label,
        cppID: id, what: "plugin edit label")
    report.expect(document.isDirty, cppID: id, message: "recorded plugin state dirties history")
    report.expect(document.history.undoDocument(), cppID: id, message: "plugin edit undo succeeds")
    report.expectEqual(
        expected: [original], actual: document.effects, cppID: id, what: "undo restores nil plugin state")
    report.expect(!document.isDirty, cppID: id, message: "plugin undo restores clean history")
    report.expect(document.history.redoDocument(), cppID: id, message: "plugin edit redo succeeds")
    report.expectEqual(
        expected: firstBlob, actual: document.effect(onTrack: 0)?.pluginState, cppID: id,
        what: "redo restores first blob")
    document.history.markSaved(document.history.currentIdentity)
    report.expect(!document.isDirty, cppID: id, message: "saved plugin identity is clean")
    let revision = document.revision
    let historyRevision = document.history.revision
    try document.recordPluginState(original.id, state: firstBlob)
    report.expectEqual(expected: 1, actual: document.history.undoCount, cppID: id, what: "equal blob adds no step")
    report.expectEqual(expected: revision, actual: document.revision, cppID: id, what: "equal blob publishes nothing")
    report.expectEqual(
        expected: historyRevision, actual: document.history.revision, cppID: id, what: "equal blob leaves history alone"
    )
    report.expect(!document.isDirty, cppID: id, message: "equal blob leaves save point clean")
    let secondBlob = PluginStateBlob(component: [], controller: [3, 4])
    try document.recordPluginState(original.id, state: secondBlob)
    report.expectEqual(
        expected: 2, actual: document.history.undoCount, cppID: id, what: "another finished edit adds one step")
    report.expect(document.isDirty, cppID: id, message: "new blob leaves save point")
    report.expect(document.history.undoDocument(), cppID: id, message: "second plugin edit undo succeeds")
    report.expectEqual(
        expected: firstBlob, actual: document.effect(onTrack: 0)?.pluginState, cppID: id,
        what: "undo restores before blob")
    report.expect(!document.isDirty, cppID: id, message: "undo returns to saved blob")
    report.expect(document.history.redoDocument(), cppID: id, message: "second plugin edit redo succeeds")
    report.expectEqual(
        expected: secondBlob, actual: document.effect(onTrack: 0)?.pluginState, cppID: id,
        what: "redo restores after blob")
    report.expect(document.isDirty, cppID: id, message: "redo leaves saved blob")
}

@MainActor
private func effectTrackRemapChecks(_ report: CheckReport) {
    let id = "swiftcore/TrackEffectModel::trackRemaps"
    let first = TrackEffect(
        id: EffectID(raw: 10), config: effectModelConfig(),
        pluginState: PluginStateBlob(component: [1], controller: [2]))
    let last = TrackEffect(
        id: EffectID(raw: 20), config: effectModelConfig(track: 2),
        pluginState: PluginStateBlob(component: [3], controller: [4]))
    let document = SongDocument(file: effectModelFile(), effects: [last, first])
    report.expectEqual(
        expected: [first, last], actual: document.effects, cppID: id, what: "restored inserts sort by engine track")
    let baseline = document.state
    var publications: [DocumentChange] = []
    var observedEffects: [[TrackEffect]] = []
    document.onChange = { [weak document] (change: DocumentChange) in
        publications.append(change)
        observedEffects.append(document?.effects ?? [])
    }
    document.deleteTrack(0)
    var shifted = last
    shifted.config.track = 1
    let deleted = document.state
    report.expectEqual(
        expected: [shifted], actual: document.effects, cppID: id,
        what: "delete removes doomed insert and shifts survivor")
    report.expectEqual(
        expected: 1, actual: document.history.undoCount, cppID: id, what: "delete and effect changes are one step")
    report.expectEqual(
        expected: [[shifted]], actual: observedEffects, cppID: id, what: "observer sees effects already remapped")
    report.expect(
        publications.count == 1 && publications[0].trackRemap?.engineTrackMap == [nil, 0, 1]
            && !publications[0].effectsOnly,
        cppID: id, message: "structural delete publishes once with its full map, not as effects-only")
    report.expect(document.history.undoDocument(), cppID: id, message: "track delete undo succeeds")
    report.expectEqual(
        expected: baseline, actual: document.state, cppID: id,
        what: "track undo restores exact effects with blobs and MIDI")
    report.expect(document.history.redoDocument(), cppID: id, message: "track delete redo succeeds")
    report.expectEqual(expected: deleted, actual: document.state, cppID: id, what: "track redo restores exact deletion")

    let moved = SongDocument(file: effectModelFile(), effects: [first, last])
    report.expect(moved.moveTrack(0, to: 2), cppID: id, message: "track move succeeds")
    var movedFirst = first
    movedFirst.config.track = 2
    report.expectEqual(
        expected: [shifted, movedFirst], actual: moved.effects, cppID: id, what: "move maps and sorts both inserts")
    let movedState = moved.state
    report.expectEqual(
        expected: 1, actual: moved.history.undoCount, cppID: id, what: "move and effect remap are one step")
    report.expect(moved.history.undoDocument(), cppID: id, message: "track move undo succeeds")
    report.expectEqual(expected: baseline, actual: moved.state, cppID: id, what: "move undo restores exact original")
    report.expect(moved.history.redoDocument(), cppID: id, message: "track move redo succeeds")
    report.expectEqual(expected: movedState, actual: moved.state, cppID: id, what: "move redo exact state")

    let expanded = SongDocument(file: effectModelFile(), effects: [first, last])
    report.expectEqual(expected: 3, actual: expanded.addTrack(voice: 4), cppID: id, what: "track add succeeds")
    report.expectEqual(
        expected: [first, last], actual: expanded.effects, cppID: id,
        what: "add remaps existing effects without cloning")
    report.expect(expanded.history.undoDocument(), cppID: id, message: "track add undo succeeds")
    report.expectEqual(
        expected: baseline, actual: expanded.state, cppID: id, what: "add undo preserves original effects")
    report.expectEqual(expected: 3, actual: expanded.duplicateTrack(0), cppID: id, what: "track duplicate succeeds")
    report.expectEqual(
        expected: [first, last], actual: expanded.effects, cppID: id, what: "duplicate does not duplicate its insert")
    let duplicated = expanded.state
    report.expect(expanded.history.undoDocument(), cppID: id, message: "track duplicate undo succeeds")
    report.expectEqual(expected: baseline, actual: expanded.state, cppID: id, what: "duplicate undo exact state")
    report.expect(expanded.history.redoDocument(), cppID: id, message: "track duplicate redo succeeds")
    report.expectEqual(expected: duplicated, actual: expanded.state, cppID: id, what: "duplicate redo exact state")
}

@MainActor
private func effectIdentityChecks(_ report: CheckReport) throws {
    let id = "swiftcore/TrackEffectModel::identities"
    let restored = TrackEffect(id: EffectID(raw: 100), config: effectModelConfig(track: 2))
    let document = SongDocument(file: effectModelFile(), effects: [restored])
    let first = try document.addEffect(effectModelConfig())
    report.expectEqual(
        expected: UInt64(101), actual: first.raw, cppID: id, what: "minting starts past restored maximum")
    report.expect(document.history.undoDocument(), cppID: id, message: "minted effect undo succeeds")
    report.expect(document.history.redoDocument(), cppID: id, message: "minted effect redo succeeds")
    report.expectEqual(
        expected: first, actual: document.effect(onTrack: 0)?.id, cppID: id, what: "redo restores same identity")
    report.expect(document.history.undoDocument(), cppID: id, message: "minted effect can be undone again")
    let second = try document.addEffect(effectModelConfig(track: 1))
    report.expectEqual(
        expected: UInt64(102), actual: second.raw, cppID: id, what: "branch after undo never reuses effect identity")
    report.expect(!document.history.canRedo, cppID: id, message: "new effect edit discards prior redo branch")
    try document.removeEffect(second)
    let third = try document.addEffect(effectModelConfig(track: 1))
    report.expectEqual(expected: UInt64(103), actual: third.raw, cppID: id, what: "removal never recycles identity")
}

/// Checks undoable whole-track inserts, independent plugin state and transactional track remaps.
@MainActor
public func runTrackEffectModelChecks(_ report: CheckReport) {
    do { try effectLifecycleChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::lifecycle", "unexpected error: \(error)")
    }
    do { try effectValidationChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::validation", "unexpected error: \(error)")
    }
    do { try effectReplacementChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::replacement", "unexpected error: \(error)")
    }
    do { try effectGestureChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::gestures", "unexpected error: \(error)")
    }
    do { try effectConfigDeltaChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::configDelta", "unexpected error: \(error)")
    }
    do { try effectPluginStateChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::pluginState", "unexpected error: \(error)")
    }
    effectTrackRemapChecks(report)
    do { try effectIdentityChecks(report) } catch {
        report.fail("swiftcore/TrackEffectModel::identities", "unexpected error: \(error)")
    }
}
