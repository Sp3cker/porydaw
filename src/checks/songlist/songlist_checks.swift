import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// SongListPresenter checks mirroring the retired SongListPanel widget
// surface (src/ui/songlistpanel.{h,cpp}, now oracle-only). Every predicate
// asserts observable list outcomes — ordering, badges, filter state,
// selection, activation IDs — never widget internals.
//
// Controller registration: call runSongListModelChecks(report) from the
// projectSession suite (or a dedicated suite) inside swift_core_check.

@MainActor
private func songListing(_ id: Int, _ label: String, constant: String = "",
                         registered: Bool = true, gaps: [String] = [],
                         playable: Bool = true) -> SongListing {
    SongListing(id: id, label: label,
                constant: constant.isEmpty ? label.uppercased() : constant,
                player: "MUSIC_PLAYER_BGM", midiPath: "/p/sound/songs/midi/\(label).mid",
                trackBudget: 16, hasMid: playable, hasCfg: true,
                registered: registered, registrationGaps: gaps)
}

@MainActor
private func songListFixture() -> [SongListing] {
    [
        songListing(0, "mus_route101"),
        songListing(1, "mus_route102"),
        songListing(2, "se_door"),
        songListing(3, "se_bell"),
        songListing(4, "ph_letter_a"),
        songListing(5, "noscore"),
        songListing(6, "mus_stray", registered: false, gaps: ["song_table.inc", "songs.h"]),
        songListing(7, "mus_partial", gaps: ["songs.h"]),
        songListing(8, "mus_ghost", playable: false), // registered but no .mid
    ]
}

@MainActor
private func rowLabels(_ presenter: SongListPresenter) -> [String] {
    (0..<presenter.rows.count).map { presenter.rows[$0].label }
}


@MainActor
private func categoryPrefixes(_ presenter: SongListPresenter) -> [String] {
    (0..<presenter.categories.count).map { presenter.categories[$0].prefix }
}

@MainActor
private func categoryNames(_ presenter: SongListPresenter) -> [String] {
    (0..<presenter.categories.count).map { presenter.categories[$0].name }
}

@MainActor
private func selectCategory(_ presenter: SongListPresenter, _ prefix: String) {
    for index in 0..<presenter.categories.count where presenter.categories[index].prefix == prefix {
        presenter.selectCategory(index: index)
        return
    }
}

// MARK: - Playable gate, badges and count

@MainActor
private func songListPlayableGateAndBadges(_ report: CheckReport) {
    let id = "swiftcore/SongList::playableGateAndBadges"
    let presenter = SongListPresenter()
    presenter.setSongs(songListFixture())

    // setSongs drops non-playable entries; strays and partials stay.
    report.expectEqual(8, presenter.totalCount, cppID: id,
                       what: "unregistered and partial songs list; the mid-less entry drops")
    report.expectEqual(
        ["mus_route101", "mus_route102", "se_door", "se_bell", "ph_letter_a", "noscore",
         "mus_stray", "mus_partial"],
        rowLabels(presenter), cppID: id, what: "snapshot order preserved")
    report.expectEqual("8 songs", presenter.countText, cppID: id,
                       what: "unfiltered count caption")

    let stray = presenter.rows[6]
    report.expectEqual("mus_stray  ⚠ not registered", stray.text, cppID: id,
                       what: "unregistered badge text")
    report.expectEqual(true, stray.warning, cppID: id, what: "unregistered row warns")
    report.expectEqual("song_table.inc, songs.h", stray.registrationGapText, cppID: id,
                       what: "unregistered tooltip lists every missing file")
    let partial = presenter.rows[7]
    report.expectEqual("mus_partial  ⚠ not fully registered", partial.text, cppID: id,
                       what: "partial badge text")
    report.expectEqual(true, partial.warning, cppID: id, what: "partial row warns")
    report.expectEqual("songs.h", partial.registrationGapText, cppID: id,
                       what: "partial tooltip names the missing file")
    report.expectEqual(false, presenter.rows[0].warning, cppID: id,
                       what: "fully registered row stays plain")

    // Register Song enablement: incomplete registrations only.
    report.expectEqual(true, presenter.canRegister(songId: 6), cppID: id,
                       what: "stray offers Register Song")
    report.expectEqual(true, presenter.canRegister(songId: 7), cppID: id,
                       what: "partial offers Register Song")
    report.expectEqual(false, presenter.canRegister(songId: 0), cppID: id,
                       what: "complete registration disables Register Song")
}

// MARK: - Categories

@MainActor
private func songListCategories(_ report: CheckReport) {
    let id = "swiftcore/SongList::categories"
    let presenter = SongListPresenter()
    presenter.setSongs(songListFixture())

    // mus_ has four playable entries, se_ two; ph_ and the underscore-less
    // label are singletons and pool into Other.
    report.expectEqual(["", "mus_", "se_", SongListPresenter.otherPrefix],
                       categoryPrefixes(presenter), cppID: id,
                       what: "categories are multi-song prefixes, biggest first, Other last")
    report.expectEqual(["All (8)", "Music (mus_) (4)", "Sound effects (se_) (2)", "Other (2)"],
                       categoryNames(presenter), cppID: id,
                       what: "category names carry friendly labels and counts")

    selectCategory(presenter, "se_")
    report.expectEqual(["se_door", "se_bell"], rowLabels(presenter), cppID: id,
                       what: "category filters to its prefix")
    report.expectEqual("2 of 8 songs", presenter.countText, cppID: id,
                       what: "filtered count caption")
    report.expectEqual("se_", presenter.categoryPrefix(), cppID: id,
                       what: "categoryPrefix reports the combo data")

    selectCategory(presenter, SongListPresenter.otherPrefix)
    report.expectEqual(["ph_letter_a", "noscore"], rowLabels(presenter), cppID: id,
                       what: "Other pools singleton prefixes and underscore-less labels")

    // A category that disappears on the next setSongs falls back to All.
    selectCategory(presenter, "se_")
    presenter.setSongs([songListing(0, "mus_a"), songListing(1, "mus_b")])
    report.expectEqual(0, presenter.categoryIndex, cppID: id,
                       what: "vanished category falls back to All")
    report.expectEqual("", presenter.categoryPrefix(), cppID: id,
                       what: "fallback reports the All prefix")
    report.expectEqual(["mus_a", "mus_b"], rowLabels(presenter), cppID: id,
                       what: "fallback shows every song")
}

// MARK: - Search

@MainActor
private func songListSearch(_ report: CheckReport) {
    let id = "swiftcore/SongList::search"
    let presenter = SongListPresenter()
    presenter.setSongs(songListFixture())

    // Per-word AND over label + constant.
    presenter.updateSearch(text: "mus route")
    report.expectEqual(["mus_route101", "mus_route102"], rowLabels(presenter), cppID: id,
                       what: "multi-word query requires every word")
    presenter.updateSearch(text: "route stray")
    report.expectEqual([], rowLabels(presenter), cppID: id,
                       what: "no song contains both words")
    report.expectEqual("0 of 8 songs", presenter.countText, cppID: id,
                       what: "empty result count caption")

    // The constant participates: MUS_STRAY's constant matches "stray".
    presenter.updateSearch(text: "mus_stray")
    report.expectEqual(["mus_stray"], rowLabels(presenter), cppID: id,
                       what: "constant text matches")

    // Single-word fuzzy fallback: subsequence, not substring.
    presenter.updateSearch(text: "musrival")
    report.expectEqual([], rowLabels(presenter), cppID: id,
                       what: "non-subsequence finds nothing")
    presenter.updateSearch(text: "msray")
    report.expectEqual(["mus_stray"], rowLabels(presenter), cppID: id,
                       what: "subsequence query finds mus_stray")
    // Fuzzy applies to single-word queries only.
    presenter.updateSearch(text: "ms ray")
    report.expectEqual([], rowLabels(presenter), cppID: id,
                       what: "multi-word queries never fall back to fuzzy")

    // Search composes with the category.
    presenter.updateSearch(text: "")
    selectCategory(presenter, "mus_")
    presenter.updateSearch(text: "route")
    report.expectEqual(["mus_route101", "mus_route102"], rowLabels(presenter), cppID: id,
                       what: "search narrows inside the category")

    // Clearing restores the full category.
    presenter.updateSearch(text: "  ")
    report.expectEqual(4, presenter.rowCount, cppID: id,
                       what: "whitespace-only search is empty")
}

// MARK: - Sort

@MainActor
private func songListSort(_ report: CheckReport) {
    let id = "swiftcore/SongList::sort"
    let presenter = SongListPresenter()
    presenter.setSongs([
        songListing(0, "mus_beta"),
        songListing(1, "mus_Alpha"),
        songListing(2, "mus_alpha"), // case tie with id 1; id order wins
        songListing(3, "se_door"),
    ])

    presenter.selectSort(index: 1)
    report.expectEqual(["mus_Alpha", "mus_alpha", "mus_beta", "se_door"],
                       rowLabels(presenter), cppID: id,
                       what: "A–Z is case-insensitive with an ID tie-break")
    presenter.selectSort(index: 0)
    report.expectEqual(["mus_beta", "mus_Alpha", "mus_alpha", "se_door"],
                       rowLabels(presenter), cppID: id,
                       what: "ID order restores snapshot order")
}

// MARK: - Current song, selection and activation

@MainActor
private func songListSelectionAndActivation(_ report: CheckReport) {
    let id = "swiftcore/SongList::selectionAndActivation"
    let presenter = SongListPresenter()
    presenter.setSongs(songListFixture())

    var activated: [Int] = []
    var newTab: [Int] = []
    var registered: [Int] = []
    var deleted: [Int] = []
    presenter.onSongActivated = { activated.append($0) }
    presenter.onSongOpenInNewTabRequested = { newTab.append($0) }
    presenter.onSongRegisterRequested = { registered.append($0) }
    presenter.onSongDeleteRequested = { deleted.append($0) }

    // The loaded song selects and reveals.
    presenter.setCurrentSong(songId: 1)
    report.expectEqual(1, presenter.selectedSongId, cppID: id,
                       what: "setCurrentSong selects the loaded song")
    report.expectEqual(1, presenter.revealSongId, cppID: id,
                       what: "setCurrentSong scrolls the row into view")
    report.expectEqual(true, presenter.rows[1].current, cppID: id,
                       what: "the loaded row carries the current flag")

    // Selection survives a rebuild while the search stays empty.
    selectCategory(presenter, "mus_")
    report.expectEqual(1, presenter.selectedSongId, cppID: id,
                       what: "rebuild re-selects the loaded song")

    // Mid-search the selection clears so Enter takes the first match.
    presenter.updateSearch(text: "route")
    report.expectEqual(-1, presenter.selectedSongId, cppID: id,
                       what: "search clears the selection")
    presenter.activateSelection()
    report.expectEqual([0], activated, cppID: id,
                       what: "Enter activates the first visible match")

    // A filtered-out loaded song deselects; -1 deselects outright.
    presenter.updateSearch(text: "")
    selectCategory(presenter, "se_")
    report.expectEqual(-1, presenter.selectedSongId, cppID: id,
                       what: "filtered-out loaded song deselects")
    presenter.setCurrentSong(songId: -1)
    report.expectEqual(-1, presenter.selectedSongId, cppID: id,
                       what: "-1 deselects")

    // Activation and context actions carry the native song ID.
    selectCategory(presenter, "")
    presenter.activateSong(songId: 6)
    presenter.requestOpenInNewTab(songId: 6)
    presenter.requestRegister(songId: 6)
    presenter.requestDelete(songId: 6)
    report.expectEqual([0, 6], activated, cppID: id,
                       what: "activation emits the native song ID")
    report.expectEqual([6], newTab, cppID: id, what: "open-in-new-tab emits the native ID")
    report.expectEqual([6], registered, cppID: id, what: "register emits the native ID")
    report.expectEqual([6], deleted, cppID: id, what: "delete emits the native ID")

    // Activating an id that isn't visible is a no-op.
    presenter.updateSearch(text: "route101")
    presenter.activateSong(songId: 6)
    report.expectEqual([0, 6], activated, cppID: id,
                       what: "invisible ids cannot activate")

    // Context actions only target visible rows; Register additionally needs
    // an incomplete registration (the native action's enablement).
    presenter.requestOpenInNewTab(songId: 6)
    presenter.requestRegister(songId: 6)
    presenter.requestDelete(songId: 6)
    report.expectEqual([6], newTab, cppID: id,
                       what: "invisible ids cannot open in a new tab")
    report.expectEqual([6], registered, cppID: id,
                       what: "invisible ids cannot register")
    report.expectEqual([6], deleted, cppID: id,
                       what: "invisible ids cannot delete")
    presenter.updateSearch(text: "")
    presenter.requestRegister(songId: 0)
    report.expectEqual([6], registered, cppID: id,
                       what: "a fully registered song cannot register")
}

// MARK: - Filter restore

@MainActor
private func songListRestoreFilters(_ report: CheckReport) {
    let id = "swiftcore/SongList::restoreFilters"
    let presenter = SongListPresenter()

    // Before any project, the restored category reports as pending so a
    // project-less run doesn't wipe it.
    presenter.restoreFilters(search: "route", sort: 1, category: "se_")
    report.expectEqual("route", presenter.searchText, cppID: id,
                       what: "restored search text")
    report.expectEqual(1, presenter.sortIndex, cppID: id, what: "restored sort")
    report.expectEqual("se_", presenter.categoryPrefix(), cppID: id,
                       what: "pending category reports before songs arrive")

    // Once songs arrive the pending category applies.
    presenter.setSongs(songListFixture())
    report.expectEqual("se_", presenter.categoryPrefix(), cppID: id,
                       what: "pending category applies on first rebuild")
    report.expectEqual([], rowLabels(presenter), cppID: id,
                       what: "restored search and category compose")

    // A restored category the project lacks falls back to All.
    let fresh = SongListPresenter()
    fresh.restoreFilters(search: "", sort: 0, category: "xy_")
    fresh.setSongs(songListFixture())
    report.expectEqual(0, fresh.categoryIndex, cppID: id,
                       what: "unknown restored category falls back to All")
    report.expectEqual("", fresh.categoryPrefix(), cppID: id,
                       what: "fallback clears the pending prefix")

    // Out-of-range sort indexes are ignored.
    let sorted = SongListPresenter()
    sorted.restoreFilters(search: "", sort: 7, category: "")
    report.expectEqual(0, sorted.sortIndex, cppID: id,
                       what: "out-of-range sort index is ignored")
}

// MARK: - Entry point

@MainActor
internal func runSongListModelChecks(_ report: CheckReport) {
    songListPlayableGateAndBadges(report)
    songListCategories(report)
    songListSearch(report)
    songListSort(report)
    songListSelectionAndActivation(report)
    songListRestoreFilters(report)
}
