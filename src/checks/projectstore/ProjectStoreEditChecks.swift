import Foundation
import PorydawProject

private func editExpect(_ row: String, _ condition: Bool, _ report: CheckReport, _ detail: String) {
    report.expect(condition, cppID: "projectstore-edit/\(row)", message: "\(row): \(detail)")
}

private func editFail(_ rows: [String], _ report: CheckReport, _ detail: String) {
    for row in rows { report.fail("projectstore-edit/\(row)", detail) }
}

private func editExternally(root: URL, fence: TimeInterval) throws -> VgVoice? {
    let writer = VoicegroupSource()
    var error: String?
    guard writer.open(projectRoot: root.path, voicegroupArg: "_fixture_rich", error: &error),
          var voice = writer.voiceAt(slot: 0) else { return nil }
    voice.release = voice.release == 3 ? 4 : 3
    guard writer.setVoice(slot: 0, voice: voice), try writer.save() else { return nil }
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: fence)],
                                          ofItemAtPath: writer.filePath)
    return voice
}

internal func runProjectStoreEditSuite(_ report: CheckReport) {
    do {
        try withTempProjectCopy(prefix: "projectstore-edit") { root in
            let store = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await store.open() }
            guard case .success = opened else {
                editFail(["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09"],
                         report, "fixture project failed to open: \(String(describing: opened))")
                return
            }
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success(let first) = loaded,
                  let original = first.slotViews.first?.voice else {
                editFail(["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09"],
                         report, "fixture slot 0 failed to load: \(String(describing: loaded))")
                return
            }

            var changed = original
            changed.key = original.key == 60 ? 61 : 60
            let scalarEdit: VoicegroupEditOperation = .set(.init(slot: 0, value: changed, expected: original))
            let setResult = awaitValue { try await store.applyVoicegroupEdit(lease: first, operation: scalarEdit) }
            guard case .success(.applied(let edited, let scalarToken)) = setResult else {
                editFail(["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09"],
                         report, "fixture scalar edit failed: \(String(describing: setResult))")
                return
            }
            editExpect("E01", edited.bankToken != first.bankToken && edited.dirty &&
                       edited.slotViews[0].voice?.key == changed.key &&
                       first.slotViews[0].voice == original && !first.dirty && scalarToken == nil,
                       report, "scalar edit replaces the bank and leaves the original lease unchanged")

            let stale = awaitValue { try await store.applyVoicegroupEdit(lease: edited, operation: scalarEdit) }
            let afterStale = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            if case .success(.conflict(let id)) = stale,
               case .success(let current) = afterStale {
                editExpect("E02", id == edited.id && current.bankToken == edited.bankToken &&
                           current.slotViews[0].voice == changed, report,
                           "stale expected voice conflicts without changing the published bank")
            } else {
                editExpect("E02", false, report,
                           "stale edit or subsequent reload failed: \(String(describing: stale))")
            }

            guard let blank = edited.slotViews.firstIndex(where: { $0.kind == .none }) else {
                editFail(["E03", "E04", "E05", "E06", "E07", "E08", "E09"], report,
                         "fixture contains no blank slot to materialize")
                return
            }
            let blankVoice = VgVoice(macro: .square1, sustain: 15)
            let insert = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: edited, operation: .set(.init(slot: blank, value: blankVoice, expected: nil)))
            }
            guard case .success(.applied(let materialized, let maybeToken)) = insert,
                  let token = maybeToken else {
                editFail(["E03", "E04", "E05", "E06", "E07", "E08", "E09"], report,
                         "blank-slot insertion failed or omitted its token: \(String(describing: insert))")
                return
            }
            editExpect("E03", materialized.bankToken != edited.bankToken && materialized.dirty &&
                       materialized.slotViews[blank].kind == .editable &&
                       materialized.slotViews[blank].voice == blankVoice &&
                       edited.slotViews[blank].kind == .none, report,
                       "blank slot \(blank) materializes with Square 1 sustain 15 and a token")

            let reverted = awaitValue {
                try await store.revertBlankSlot(lease: materialized, materializationToken: token)
            }
            guard case .success(.applied(let restored, let revertedToken)) = reverted else {
                editFail(["E04", "E05", "E06", "E07", "E08", "E09"], report,
                         "blank-slot revert failed: \(String(describing: reverted))")
                return
            }
            editExpect("E04", restored.bankToken != materialized.bankToken &&
                       restored.slotViews[blank].kind == .none &&
                       restored.slotViews[blank].voice == nil &&
                       materialized.slotViews[blank].voice == blankVoice && revertedToken == nil,
                       report, "revert republishes the empty slot without minting a token")

            let spent = awaitValue { try await store.revertBlankSlot(lease: restored, materializationToken: token) }
            if case .success(.conflict(let id)) = spent {
                editExpect("E05", id == restored.id, report, "spent token conflicts")
            } else {
                editExpect("E05", false, report, "spent token must conflict: \(String(describing: spent))")
            }
            let unknown = awaitValue {
                try await store.revertBlankSlot(lease: restored, materializationToken: UInt64.max)
            }
            if case .success(.conflict(let id)) = unknown {
                editExpect("E06", id == restored.id, report, "unknown token conflicts")
            } else {
                editExpect("E06", false, report, "unknown token must conflict: \(String(describing: unknown))")
            }
            let outside = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: restored, operation: .set(.init(slot: 128, value: blankVoice, expected: nil)))
            }
            if case .success(.conflict(let id)) = outside {
                editExpect("E07", id == restored.id, report, "out-of-range slot conflicts")
            } else {
                editExpect("E07", false, report,
                           "out-of-range slot must conflict: \(String(describing: outside))")
            }

            let previewed = awaitValue { try await store.preview(lease: restored) }
            if case .success(let preview?) = previewed {
                editExpect("E08", preview.id == restored.id && preview.bankToken != 0 &&
                           preview.slotViews[blank].kind == .none, report,
                           "preview returns an adopted bank with the requested source identity")
            } else {
                editExpect("E08", false, report, "preview failed: \(String(describing: previewed))")
            }

            do {
                try withTempProjectCopy(prefix: "projectstore-edit") { otherRoot in
                    let otherStore = ProjectStore(projectRoot: otherRoot)
                    let foreignStore = ProjectStore(projectRoot: root)
                    let otherOpen = awaitValue { try await otherStore.open() }
                    let foreignOpen = awaitValue { try await foreignStore.open() }
                    let otherLoad = awaitValue { try await otherStore.loadBank(voicegroupArg: "_fixture_rich") }
                    guard case .success = otherOpen, case .success = foreignOpen,
                          case .success(let otherLease) = otherLoad else {
                        editExpect("E09", false, report, "fresh or second project failed to open its bank")
                        return
                    }
                    let attempted = awaitValue {
                        try await foreignStore.applyVoicegroupEdit(lease: otherLease, operation: scalarEdit)
                    }
                    let afterAttempt = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
                    if case .failure(let error as VoicegroupStoreError) = attempted,
                       case .operationFailed(let message) = error,
                       case .success(let current) = afterAttempt {
                        editExpect("E09",
                                   message == "Voicegroup is not loaded: \(otherLease.id.sourceRelativePath)" &&
                                   current.bankToken == restored.bankToken &&
                                   current.slotViews[0].voice == changed, report,
                                   "foreign lease into an unloaded store throws without changing the original bank")
                    } else {
                        editExpect("E09", false, report,
                                   "foreign edit or reload failed: \(String(describing: attempted))")
                    }
                }
            } catch {
                editExpect("E09", false, report, "cannot prepare second fixture copy: \(error)")
            }

            do {
                try withTempProjectCopy(prefix: "projectstore-edit") { expiryRoot in
                    let expiryStore = ProjectStore(projectRoot: expiryRoot)
                    guard case .success = awaitValue({ try await expiryStore.open() }),
                          case .success(let base) = awaitValue({
                              try await expiryStore.loadBank(voicegroupArg: "_fixture_rich")
                          }),
                          let externalValue = try editExternally(root: expiryRoot, fence: 3600),
                          case .success(let fresh) = awaitValue({
                              try await expiryStore.loadBank(voicegroupArg: "_fixture_rich")
                          }),
                          let blankSlot = fresh.slotViews.firstIndex(where: { $0.kind == .none }) else {
                        editExpect("E10", false, report, "expiry fixture failed to reload an external change")
                        return
                    }
                    let blankValue = VgVoice(macro: .square1, sustain: 15)
                    guard case .success(.applied(let materialized, let maybeToken)) = awaitValue({
                        try await expiryStore.applyVoicegroupEdit(
                            lease: fresh,
                            operation: .set(.init(slot: blankSlot, value: blankValue, expected: nil)))
                    }), let liveToken = maybeToken,
                          case .success(let saved?) = awaitValue({
                              try await expiryStore.saveVoicegroup(lease: materialized)
                          }),
                          let replacedValue = try editExternally(root: expiryRoot, fence: 7200) else {
                        editExpect("E10", false, report, "blank-slot insertion minted no token or failed to save")
                        return
                    }
                    let replaced = awaitValue {
                        try await expiryStore.loadBank(voicegroupArg: "_fixture_rich")
                    }
                    let expired = awaitValue {
                        try await expiryStore.revertBlankSlot(lease: saved, materializationToken: liveToken)
                    }
                    guard case .success(let current) = replaced, case .success(.conflict(let id)) = expired else {
                        editExpect("E10", false, report,
                                   "reload or expired-token revert misbehaved: \(String(describing: expired))")
                        return
                    }
                    editExpect("E10", fresh.bankToken != base.bankToken &&
                               fresh.slotViews[0].voice == externalValue && !saved.dirty &&
                               current.bankToken != saved.bankToken && current.slotViews[0].voice == replacedValue &&
                               current.slotViews[blankSlot].voice == blankValue && id == saved.id, report,
                               "an external byte change to a clean bank reloads it and burns its minted tokens")

                    guard let pendingSlot = current.slotViews.firstIndex(where: { $0.kind == .none }),
                          case .success(.applied(let pending, let maybePendingToken)) = awaitValue({
                              try await expiryStore.applyVoicegroupEdit(
                                  lease: current,
                                  operation: .set(.init(slot: pendingSlot, value: blankValue, expected: nil)))
                          }), let pendingToken = maybePendingToken else {
                        editExpect("E11", false, report, "second blank-slot insertion minted no token")
                        return
                    }
                    let sourcePath = URL(filePath: current.sourcePath)
                    let baseline = try Data(contentsOf: sourcePath)
                    guard try editExternally(root: expiryRoot, fence: 10800) != nil else {
                        editExpect("E11", false, report, "overlapping external edit failed to write")
                        return
                    }
                    let overlapped = awaitValue {
                        try await expiryStore.loadBank(voicegroupArg: "_fixture_rich")
                    }
                    try baseline.write(to: sourcePath)
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date(timeIntervalSinceNow: 14400)], ofItemAtPath: sourcePath.path)
                    let retained = awaitValue {
                        try await expiryStore.loadBank(voicegroupArg: "_fixture_rich")
                    }
                    let undone = awaitValue {
                        try await expiryStore.revertBlankSlot(lease: pending, materializationToken: pendingToken)
                    }
                    if case .failure(let conflict) = overlapped, conflict is VoicegroupStoreError,
                       case .success(let kept) = retained,
                       case .success(.applied(let restored, _)) = undone {
                        editExpect("E11", kept.dirty && kept.slotViews[pendingSlot].voice == blankValue &&
                                   !restored.dirty && restored.slotViews[pendingSlot].voice == nil, report,
                                   "an external change overlapping pending edits fails visibly and keeps them")
                    } else {
                        editExpect("E11", false, report,
                                   "overlap reload or retained revert misbehaved: \(String(describing: undone))")
                    }
                }
            } catch {
                editExpect("E10", false, report, "cannot prepare expiry fixture: \(error)")
            }
        }
    } catch {
        editFail(["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09"],
                 report, "cannot prepare edit fixture: \(error)")
    }
}
