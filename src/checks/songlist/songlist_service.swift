import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// Fixture-backed ProjectService song-listing checks: the staged decomp
// project gains one unregistered stray (.mid only) and one partial
// registration (song_table.inc row, no songs.h define), then the typed
// listing must carry both with SongInfo identity and full metadata — the
// feed SongListPresenter consumes.
//
// Controller registration: call runSongListServiceChecks(report,
// fixtureRoot:) from the projectSession suite inside swift_core_check.

@MainActor
internal func runSongListServiceChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongList::serviceFeed"
    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-songlist-test")

    // A stray: a .mid with no song_table.inc entry. A partial: a table row
    // with no songs.h define (ld/charmap/debug don't apply to this fixture).
    // The shared session fixture intentionally offsets songs.h constants by
    // one for its own tests. Align this staged project's constants with the
    // song-table indices so a complete row and a partial row coexist.
    // The mid-less filler at index 9 keeps the partial at index 10.
    let songsDir = projectDir + "/sound/songs/midi"
    guard let midiBytes = try? makeMidiFixture().encoded() else {
        report.fail(id, "fixture MIDI failed to encode")
        return
    }
    do {
        try Data(midiBytes).write(to: URL(fileURLWithPath: songsDir + "/mus_stray_test.mid"))
        try Data(midiBytes).write(to: URL(fileURLWithPath: songsDir + "/mus_partial_test.mid"))
        let tablePath = projectDir + "/sound/song_table.inc"
        let table = try String(contentsOfFile: tablePath, encoding: .utf8)
        try (table + "\n    song mus_filler_test, MUSIC_PLAYER_BGM, 0\n" +
             "    song mus_partial_test, MUSIC_PLAYER_BGM, 0\n")
            .write(toFile: tablePath, atomically: true, encoding: .utf8)
        let names = ["mus_session_test", "mus_session_test2"] +
            rejectedVoicegroupCases.map(\.label)
        let defines = names.enumerated().map {
            "#define \($0.element.uppercased()) \($0.offset)"
        }.joined(separator: "\n")
        try (defines + "\n").write(
            toFile: projectDir + "/include/constants/songs.h",
            atomically: true, encoding: .utf8)
        // A read-only cry line gives the bank a slot the source model does
        // not cover with a parsed voice — the loaded-tone fallback feed.
        let vgPath = projectDir + "/sound/voicegroups/test_vg.inc"
        let vg = try String(contentsOfFile: vgPath, encoding: .utf8)
        try (vg + "\n    cry missing_cry_sample\n")
            .write(toFile: vgPath, atomically: true, encoding: .utf8)
    } catch {
        report.fail(id, "failed to stage stray/partial songs: \(error)")
        return
    }

    let service = ProjectService()
    do {
        let listings = try runBlocking {
            try await service.open(root: projectDir)
            return try await service.songs()
        }
        let labels = listings.map(\.label)

        // Every playable song lists in snapshot order: the two registered
        // fixture songs, the rejected voicegroup cases, the appended partial,
        // then the discovered stray. The mid-less filler never lists.
        report.expect(labels.contains("mus_session_test") &&
                      labels.contains("mus_session_test2") &&
                      labels.contains("mus_partial_test") &&
                      labels.contains("mus_stray_test"),
                      cppID: id,
                      message: "registered, partial and stray songs all list")
        report.expect(!labels.contains("mus_filler_test"), cppID: id,
                      message: "the mid-less table row is not playable")
        report.expectEqual(labels.count, listings.count, cppID: id,
                           what: "no playable song is dropped")

        guard let stray = listings.first(where: { $0.label == "mus_stray_test" }),
              let partial = listings.first(where: { $0.label == "mus_partial_test" }),
              let registered = listings.first(where: { $0.label == "mus_session_test" }) else {
            report.fail(id, "staged songs missing from the listing")
            return
        }
        // Identity: every id is its snapshot index — the numeric song ID for
        // registered rows, the appended index for the stray. The fixture is
        // deterministic: 9 staged table rows, filler at 9, partial at 10,
        // stray discovered at 11.
        report.expectEqual(10, partial.id, cppID: id,
                           what: "partial id is its song_table index")
        report.expectEqual(partial.id + 1, stray.id, cppID: id,
                           what: "unregistered id is the snapshot index")
        report.expectEqual(listings.firstIndex { $0.label == "mus_partial_test" },
                           listings.firstIndex { $0.id == partial.id }, cppID: id,
                           what: "listing order matches snapshot order")

        // Registration state and gaps.
        report.expectEqual(false, stray.registered, cppID: id,
                           what: "stray reports unregistered")
        report.expectEqual(["song_table.inc", "songs.h"], stray.registrationGaps, cppID: id,
                           what: "stray gaps name every missing file")
        report.expectEqual(true, partial.registered, cppID: id,
                           what: "partial reports registered")
        report.expectEqual(["songs.h"], partial.registrationGaps, cppID: id,
                           what: "partial gap names the missing define")
        report.expectEqual(true, registered.registered, cppID: id,
                           what: "fixture song reports registered")
        report.expectEqual([String](), registered.registrationGaps, cppID: id,
                           what: "fixture song has no gaps")

        // Metadata: the stray derives its constant and default player; the
        // partial keeps an empty constant until registration completes.
        report.expectEqual("MUS_STRAY_TEST", stray.constant, cppID: id,
                           what: "stray derives its constant from the label")
        report.expectEqual("MUSIC_PLAYER_BGM", stray.player, cppID: id,
                           what: "stray uses the default player")
        report.expectEqual("", partial.constant, cppID: id,
                           what: "partial has no constant until songs.h defines one")
        report.expectEqual("MUS_SESSION_TEST", registered.constant, cppID: id,
                           what: "registered constant comes from songs.h")
        report.expectEqual(true, stray.hasMid && stray.isPlayable, cppID: id,
                           what: "stray is playable")
        report.expectEqual(true, stray.registrationIncomplete, cppID: id,
                           what: "stray is registration-incomplete")
        report.expectEqual(true, partial.registrationIncomplete, cppID: id,
                           what: "partial is registration-incomplete")
        report.expectEqual(false, registered.registrationIncomplete, cppID: id,
                           what: "registered song is complete")
        report.expect(stray.midiPath.hasSuffix("sound/songs/midi/mus_stray_test.mid"),
                      cppID: id, message: "stray carries its .mid path")

        // Ordering: table songs precede discovered strays.
        report.expect(stray.id > partial.id, cppID: id,
                      message: "strays list after every table song")

        // songLabels() stays a playable-label view — strays included.
        let playableLabels = try runBlocking {
            try await service.songLabels()
        }
        report.expect(playableLabels.contains("mus_stray_test") &&
                      playableLabels.contains("mus_partial_test"),
                      cppID: id,
                      message: "songLabels includes unregistered and partial songs")

        // The presenter consumes the service feed directly: badges and
        // Register Song enablement follow the listing metadata.
        let presenter = SongListPresenter()
        presenter.setSongs(listings)
        guard let strayRow = (0..<presenter.rows.count)
                .first(where: { presenter.rows[$0].songId == stray.id })
                .map({ presenter.rows[$0] }),
              let partialRow = (0..<presenter.rows.count)
                .first(where: { presenter.rows[$0].songId == partial.id })
                .map({ presenter.rows[$0] }) else {
            report.fail(id, "service-fed rows missing from the presenter")
            return
        }
        report.expectEqual("mus_stray_test  ⚠ not registered", strayRow.text, cppID: id,
                           what: "service-fed stray wears the unregistered badge")
        report.expectEqual("mus_partial_test  ⚠ not fully registered", partialRow.text,
                           cppID: id, what: "service-fed partial wears the partial badge")
        report.expectEqual(true, presenter.canRegister(songId: stray.id), cppID: id,
                           what: "service-fed stray offers Register Song")
        report.expectEqual(true, presenter.canRegister(songId: partial.id), cppID: id,
                           what: "service-fed partial offers Register Song")
        report.expectEqual(false, presenter.canRegister(songId: registered.id), cppID: id,
                           what: "service-fed registered song does not")

        // The voice-list selector's choice feed (voice proof U001): the
        // catalog's groupArgs, sorted.
        let args = try runBlocking {
            try await service.voicegroupArgs()
        }
        report.expectEqual(["_test_vg"], args, cppID: id,
                           what: "voicegroupArgs publishes the catalog group args")

        // The loaded-tone fallback feed (voice proof U005): the staged cry
        // line is a read-only slot, so the bank publishes its immutable
        // tone — name, type byte and scalar envelope — where editable and
        // blank slots publish none.
        let opened = try runBlocking {
            try await service.openSong(label: "mus_session_test")
        }
        report.expectEqual(128, opened.bankSlots.count, cppID: id,
                           what: "the bank publishes every slot")
        let cry = opened.bankSlots[3]
        report.expectEqual(BankSlotKind.readOnlyVoice, cry.kind, cppID: id,
                           what: "the cry line is a read-only slot")
        report.expectEqual("missing_cry_sample", cry.tone?.name, cppID: id,
                           what: "the read-only slot publishes its loaded tone name")
        report.expectEqual(Int32(VoiceListSemantics.voiceCry), cry.tone?.type, cppID: id,
                           what: "the tone carries its raw type byte")
        report.expectEqual(BankToneAdsr(attack: 255, decay: 0, sustain: 255, release: 0),
                           cry.tone?.adsr, cppID: id,
                           what: "the tone carries its scalar envelope")
        report.expectEqual(false, cry.tone?.isSynth, cppID: id,
                           what: "a cry tone is not a synth")
        report.expectEqual(nil, opened.bankSlots[0].tone, cppID: id,
                           what: "editable slots publish no tone")
        report.expectEqual(nil, opened.bankSlots[4].tone, cppID: id,
                           what: "blank slots publish no tone")

        // The register/delete transaction (proof B012/B013): plan, confirm,
        // execute, refresh — the stray registers, lists, then deletes.
        let mutationId = "swiftcore/SongList::serviceMutations"
        let plan = try runBlocking {
            try await service.songRegistrationPlan(label: "mus_stray_test")
        }
        report.expectEqual("mus_stray_test", plan.label, cppID: mutationId,
                           what: "the plan resolves the label")
        report.expectEqual("MUS_STRAY_TEST", plan.constant, cppID: mutationId,
                           what: "the plan derives the constant")
        report.expectEqual("MUSIC_PLAYER_BGM", plan.player, cppID: mutationId,
                           what: "the plan defaults the player")
        report.expectEqual(stray.id, plan.songId, cppID: mutationId,
                           what: "the plan proposes the next table index")
        report.expectEqual(["song_table.inc", "songs.h"], plan.missingFiles, cppID: mutationId,
                           what: "the plan names the missing registration files")
        let newId = try runBlocking {
            try await service.registerSong(plan)
        }
        report.expectEqual(plan.songId, newId, cppID: mutationId,
                           what: "register assigns the planned song ID")
        let afterRegister = try runBlocking {
            try await service.songs()
        }
        guard let registeredStray = afterRegister.first(where: { $0.label == "mus_stray_test" })
        else {
            report.fail(mutationId, "registered stray missing from the refreshed listing")
            return
        }
        report.expectEqual(newId, registeredStray.id, cppID: mutationId,
                           what: "the refreshed listing carries the new song ID")
        report.expectEqual(true, registeredStray.registered, cppID: mutationId,
                           what: "the refreshed stray reports registered")
        report.expectEqual([String](), registeredStray.registrationGaps, cppID: mutationId,
                           what: "the refreshed stray has no gaps")

        // Song ID 0 is the engine fallback: the plan documents it and the
        // delete refuses.
        let fallbackPlan = try runBlocking {
            try await service.songDeletionPlan(label: "mus_session_test")
        }
        report.expectEqual(0, fallbackPlan.tableIndex, cppID: mutationId,
                           what: "the fallback song plans at table index 0")
        var fallbackThrew = false
        do {
            try runBlocking {
                try await service.deleteSong(label: "mus_session_test")
            }
        } catch {
            fallbackThrew = true
        }
        report.expectEqual(true, fallbackThrew, cppID: mutationId,
                           what: "deleting the engine fallback refuses")

        // Delete the now-registered stray: last table entry, removed
        // outright; the .mid lands in .porydaw/trash and the listing drops
        // the song.
        let deletePlan = try runBlocking {
            try await service.songDeletionPlan(label: "mus_stray_test")
        }
        report.expectEqual(newId, deletePlan.tableIndex, cppID: mutationId,
                           what: "the delete plan finds the table row")
        report.expectEqual(true, deletePlan.lastEntry, cppID: mutationId,
                           what: "the last table entry deletes outright")
        report.expectEqual(true, deletePlan.inSongsH, cppID: mutationId,
                           what: "the delete plan lists the songs.h define")
        report.expectEqual(nil, deletePlan.deletableVoicegroupName, cppID: mutationId,
                           what: "no voicegroup is deletable with the stray")
        try runBlocking {
            try await service.deleteSong(label: "mus_stray_test")
        }
        let afterDelete = try runBlocking {
            try await service.songs()
        }
        report.expectEqual(false, afterDelete.contains { $0.label == "mus_stray_test" },
                           cppID: mutationId,
                           what: "the deleted song leaves the refreshed listing")
        report.expect(FileManager.default.fileExists(
            atPath: projectDir + "/.porydaw/trash/mus_stray_test.mid"),
            cppID: mutationId, message: "the .mid moved to .porydaw/trash")

        // Unknown labels fail both plan halves.
        var planThrew = false
        do {
            _ = try runBlocking {
                try await service.songRegistrationPlan(label: "mus_no_such_song")
            }
        } catch {
            planThrew = true
        }
        report.expectEqual(true, planThrew, cppID: mutationId,
                           what: "an unknown label fails the registration plan")
    } catch {
        report.fail(id, "service listing failed: \(error)")
    }
    do {
        try runBlocking {
            await service.close()
        }
    } catch {
        report.fail(id, "service close failed: \(error)")
    }
}
