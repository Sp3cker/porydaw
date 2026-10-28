import Foundation
import PorydawAppPresentation
import PorydawDocument
import QtBridge

/// One visible row in the Songs list: the label plus the registration badge
/// SongListPanel paints. `songId` is the SongInfo identity (numeric song ID
/// when registered, snapshot index for strays) — the same value every
/// activation/context callback carries.
@MainActor
@QtBridgeable
public final class SongListRow {
    public var songId: Int
    public var label: String
    /// Display text: the label plus "  ⚠ not registered" / "  ⚠ not fully
    /// registered" when the registration is incomplete.
    public var text: String
    /// The amber-foreground state: unregistered stray or partial registration.
    public var warning: Bool
    /// The registration files still missing the entry, joined for the tooltip.
    public var registrationGapText: String
    public var selected: Bool
    /// The loaded song the panel tracks across rebuilds.
    public var current: Bool

    init(
        songId: Int, label: String, text: String, warning: Bool,
        registrationGapText: String, selected: Bool, current: Bool
    ) {
        self.songId = songId
        self.label = label
        self.text = text
        self.warning = warning
        self.registrationGapText = registrationGapText
        self.selected = selected
        self.current = current
    }
}

/// One entry in the category dropdown. `prefix` is the combo's data role:
/// "" for All, "<other>" for the pooled singleton/underscore-less bucket,
/// otherwise the shared label prefix ("mus_", "se_", ...).
@MainActor
@QtBridgeable
public final class SongListCategory {
    public var name: String
    public var prefix: String

    init(name: String, prefix: String) {
        self.name = name
        self.prefix = prefix
    }
}

/// The Songs dock's filtered, sorted catalog and selection contract.
/// Uses SearchQuery for filtering; defaults to newest MIDI modification first.
@MainActor
@QtBridgeable
public final class SongListPresenter {
    /// The synthetic Other bucket's combo data, matching the native sentinel.
    public static let otherPrefix = "<other>"

    public var rows: QListModel<SongListRow> = QListModel()
    public var categories: QListModel<SongListCategory> = QListModel()
    public var menuRows: QListModel<MenuRow> = QListModel()
    @QtTracked public var rowCount = 0
    @QtTracked public var totalCount = 0
    /// "%1 songs" or "%1 of %2 songs" while filtered.
    @QtTracked public var countText = ""
    /// QML reads filter state; mutations must use the methods below to rebuild.
    @QtTracked public var searchText = ""
    /// 0 = ID order, 1 = A–Z, 2 = Last modified (newest first, missing dates last).
    @QtTracked public var sortIndex = 2
    @QtTracked public var categoryIndex = 0
    /// The list's current row: the loaded song while the search is empty,
    /// cleared otherwise. -1 when nothing is selected.
    @QtTracked public var selectedSongId = -1
    /// The loaded song, re-selected on rebuilds. -1 deselects.
    @QtTracked public var currentSongId = -1
    /// Incremented by focusSearch(); the surface focuses and selects the
    /// search field on change.
    @QtTracked public var searchFocusRequest = 0
    /// Incremented when setCurrentSong scrolls a row into view; revealSongId
    /// names the row.
    @QtTracked public var revealRequest = 0
    @QtTracked public var revealSongId = -1

    @QtIgnored public var onSongActivated: ((Int) -> Void)?
    @QtIgnored public var onSongOpenInNewTabRequested: ((Int) -> Void)?
    @QtIgnored public var onSongRegisterRequested: ((Int) -> Void)?
    @QtIgnored public var onSongDeleteRequested: ((Int) -> Void)?
    @QtIgnored public var onSongDuplicateRequested: ((Int) -> Void)?

    private var songs: [SongListing] = []
    private var visible: [SongListing] = []
    /// The unfiltered snapshot input: table entries with or without MIDI
    /// plus unregistered strays. The taken hint reads here, not the feed.
    private var allListings: [SongListing] = []
    private var knownPrefixes: [String] = []
    /// Restored category awaiting its first rebuild; a category the project
    /// doesn't have falls back to All.
    private var pendingCategory = ""

    public init() {
        // The native combo ships one placeholder All entry until the first
        // project arrives.
        categories.append(SongListCategory(name: "All", prefix: ""))
    }

    // MARK: - Content

    /// Replaces the contents (non-playable songs are dropped) while keeping
    /// the current search text, sort, and — if it still exists — category.
    @QtIgnored
    public func setSongs(_ newSongs: [SongListing]) {
        let category = categoryPrefix()
        allListings = newSongs
        songs = newSongs.filter(\.isPlayable)
        rebuildCategories()
        if songs.isEmpty { pendingCategory = category }
        rebuildList()
    }

    /// The playable listings currently held, in snapshot order.
    @QtIgnored
    public var songListings: [SongListing] { songs }

    /// The listing behind a song ID, for context-action handlers.
    @QtIgnored
    public func listing(songId: Int) -> Optional<SongListing> {
        songs.first { $0.id == songId }
    }

    /// Stable identity at a filtered row position, for QML keyboard navigation.
    public func songId(at index: Int) -> Int {
        visible.indices.contains(index) ? visible[index].id : -1
    }

    public func songLabel(at index: Int) -> String {
        visible.indices.contains(index) ? visible[index].label : ""
    }

    public func categoryName(at index: Int) -> String {
        index >= 0 && index < categories.count ? categories[index].name : ""
    }
    /// QML and Swift enter through the same mutation path so the rows rebuild.
    public func updateSearch(text: String) {
        searchText = text
        rebuildList()
    }
    public func selectSort(index: Int) {
        sortIndex = index
        rebuildList()
    }
    public func selectCategory(index: Int) {
        categoryIndex = index
        rebuildList()
    }

    // MARK: - Filter state (persisted across runs by the shell)

    /// The active category's combo data: the pending restored category until
    /// a project's songs arrive, so a project-less run doesn't wipe it.
    public func categoryPrefix() -> String {
        pendingCategory.isEmpty ? currentCategoryPrefix() : pendingCategory
    }

    /// Restores persisted filters. The category stays pending until songs are
    /// set; one it doesn't have falls back to All.
    public func restoreFilters(
        search: String, sort sortIndex: Int,
        category categoryPrefix: String
    ) {
        pendingCategory = categoryPrefix
        if sortIndex >= 0 && sortIndex < 3 {
            self.sortIndex = sortIndex
        }
        searchText = search
        rebuildList()
    }

    public func restoreFromPreferences() {
        let store = PreferencesStore()
        restoreFilters(
            search: store.string(key: "songFilterText", fallback: ""),
            sort: store.int(key: "songFilterSort", fallback: 2),
            category: store.string(key: "songFilterCategory", fallback: ""))
    }

    /// Persists the current filters using the shell's existing preference keys.
    @QtIgnored
    public func persistFilters(to store: PreferencesStore) {
        store.setString(key: "songFilterText", value: searchText)
        store.setInt(key: "songFilterSort", value: sortIndex)
        store.setString(key: "songFilterCategory", value: categoryPrefix())
    }

    /// Focuses the search field and selects its text (surface-side effect).
    public func focusSearch() {
        searchFocusRequest += 1
    }

    // MARK: - Selection and activation

    /// Marks the loaded song: selects it, scrolls it into view, and keeps it
    /// selected across rebuilds. -1 (or a filtered-out id) deselects.
    public func setCurrentSong(songId: Int) {
        publish(\.currentSongId, songId)
        if visible.contains(where: { $0.id == songId }) {
            publish(\.selectedSongId, songId)
            publish(\.revealSongId, songId)
            revealRequest += 1
        } else {
            publish(\.selectedSongId, -1)
        }
        syncRowFlags()
    }

    /// Row activation (double-click / Enter on a row): emits the native ID.
    public func activateSong(songId: Int) {
        guard visible.contains(where: { $0.id == songId }) else { return }
        onSongActivated?(songId)
    }

    /// Enter in the search box: the selected match, or the first visible row.
    public func activateSelection() {
        if let selected = visible.first(where: { $0.id == selectedSongId }) {
            onSongActivated?(selected.id)
        } else if let first = visible.first {
            onSongActivated?(first.id)
        }
    }

    /// Single-click selection without activation.
    public func selectSong(songId: Int) {
        guard visible.contains(where: { $0.id == songId }) else { return }
        selectedSongId = songId
        syncRowFlags()
    }

    // MARK: - Context actions (all carry the native song ID)

    /// Context-menu "Open" — plain activation replaces the current tab's song.
    public func requestOpen(songId: Int) {
        activateSong(songId: songId)
    }

    /// Context-menu "Open in New Tab". Only a visible row can be targeted —
    /// the native menu is built from the item under the cursor.
    public func requestOpenInNewTab(songId: Int) {
        guard visible.contains(where: { $0.id == songId }) else { return }
        onSongOpenInNewTabRequested?(songId)
    }

    /// Context-menu "Register Song" — offered on songs whose registration is
    /// missing entries (unregistered strays and partial registrations
    /// alike). Only a visible, registration-incomplete row emits, matching
    /// the native action's enablement.
    public func requestRegister(songId: Int) {
        guard let song = visible.first(where: { $0.id == songId }),
            song.registrationIncomplete
        else { return }
        onSongRegisterRequested?(songId)
    }

    /// Context-menu "Delete Song…" — the shell confirms and performs it.
    /// Only a visible row can be targeted.
    public func requestDelete(songId: Int) {
        guard visible.contains(where: { $0.id == songId }) else { return }
        onSongDeleteRequested?(songId)
    }

    /// Context-menu "Duplicate Song" — instant copy through the New Song
    /// intake. Only a visible row can be targeted.
    public func requestDuplicate(songId: Int) {
        guard visible.contains(where: { $0.id == songId }) else { return }
        onSongDuplicateRequested?(songId)
    }

    /// Register Song enablement: any song with missing registration entries.
    public func canRegister(songId: Int) -> Bool {
        songs.first { $0.id == songId }?.registrationIncomplete ?? false
    }

    public func prepareMenu(songId: Int) {
        menuRows.reset(to: [
            MenuRow(actionId: 0, text: "Open"),
            MenuRow(actionId: 1, text: "Open in New Tab"),
            MenuRow(actionId: 5, text: "Duplicate Song"),
            MenuRow(actionId: 2, enabled: false, separator: true),
            MenuRow(actionId: 3, text: "Register Song", enabled: canRegister(songId: songId)),
            MenuRow(actionId: 4, text: "Delete Song…"),
        ])
    }

    public func menuRow(index: Int) -> Optional<MenuRow> {
        guard menuRows.indices.contains(index) else { return nil }
        return menuRows[index]
    }

    // MARK: - New Song name laws (fork newsongwizard identity field)

    @QtIgnored public func registeredLabels() -> Set<String> {
        Set(allListings.lazy.filter(\.registered).map(\.label))
    }

    public func songLabelTaken(label: String) -> Bool {
        allListings.contains { $0.registered && $0.label == label }
    }

    // MARK: - Rebuilds (SongListPanel::rebuildCategories/rebuildList)

    private func currentCategoryPrefix() -> String {
        guard categoryIndex >= 0 && categoryIndex < categories.count else { return "" }
        return categories[categoryIndex].prefix
    }

    private func rebuildCategories() {
        var counts: [String: Int] = [:]
        for song in songs {
            counts[Self.prefix(of: song.label), default: 0] += 1
        }

        // Prefixes with at least two songs become categories, biggest first;
        // singletons and underscore-less labels pool into Other.
        knownPrefixes = []
        var other = 0
        for (prefix, count) in counts {
            if !prefix.isEmpty && count >= 2 {
                knownPrefixes.append(prefix)
            } else {
                other += count
            }
        }
        knownPrefixes.sort { a, b in
            let countA = counts[a] ?? 0
            let countB = counts[b] ?? 0
            return countA != countB ? countA > countB : a < b
        }

        let previous = pendingCategory.isEmpty ? currentCategoryPrefix() : pendingCategory
        pendingCategory = ""  // one shot: a missing category falls back to All
        var built = [SongListCategory(name: "All (\(songs.count))", prefix: "")]
        for prefix in knownPrefixes {
            built.append(
                SongListCategory(
                    name: "\(Self.categoryName(prefix)) (\(counts[prefix] ?? 0))", prefix: prefix))
        }
        if other > 0 {
            built.append(SongListCategory(name: "Other (\(other))", prefix: Self.otherPrefix))
        }
        categories.reset(to: built)
        categoryIndex = built.firstIndex { $0.prefix == previous } ?? 0
    }

    private func matchesFilters(_ song: SongListing, query: SearchQuery) -> Bool {
        let category = currentCategoryPrefix()
        if category == Self.otherPrefix {
            if knownPrefixes.contains(Self.prefix(of: song.label)) {
                return false
            }
        } else if !category.isEmpty && !song.label.hasPrefix(category) {
            return false
        }
        if query.isEmpty {
            return true
        }
        return query.matches(song.label, song.constant)
    }

    private func rebuildList() {
        let query = SearchQuery(searchText)
        var shown = songs.filter { (song: SongListing) -> Bool in matchesFilters(song, query: query) }
        if sortIndex == 1 {
            shown.sort { a, b in
                let order = a.label.caseInsensitiveCompare(b.label)
                return order != .orderedSame ? order == .orderedAscending : a.id < b.id
            }
        } else if sortIndex == 2 {
            shown.sort { a, b in
                switch (a.modifiedAt, b.modifiedAt) {
                case let (dateA?, dateB?) where dateA != dateB:
                    return dateA > dateB
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return a.id < b.id
                }
            }
        }
        visible = shown

        var built: [SongListRow] = []
        built.reserveCapacity(shown.count)
        for song in shown {
            let partial = song.registered && !song.registrationGaps.isEmpty
            var text = song.label
            if !song.registered {
                text += "  ⚠ not registered"
            } else if partial {
                text += "  ⚠ not fully registered"
            }
            built.append(
                SongListRow(
                    songId: song.id, label: song.label, text: text,
                    warning: !song.registered || partial,
                    registrationGapText: song.registrationGaps.joined(separator: ", "),
                    selected: false, current: false))
        }
        rows.reset(to: built)
        rowCount = built.count
        totalCount = songs.count
        countText =
            shown.count == songs.count
            ? "\(songs.count) songs"
            : "\(shown.count) of \(songs.count) songs"

        // Keep the loaded song selected across rebuilds — except mid-search,
        // where the selection must stay clear so Enter takes the first match.
        if currentSongId >= 0 && query.isEmpty,
            shown.contains(where: { $0.id == currentSongId })
        {
            selectedSongId = currentSongId
        } else {
            selectedSongId = -1
        }
        syncRowFlags()
    }

    private func syncRowFlags() {
        for index in 0..<rows.count {
            let row = rows[index]
            let selected = row.songId == selectedSongId
            let current = row.songId == currentSongId
            if row.selected != selected || row.current != current {
                row.selected = selected
                row.current = current
                rows[index] = row
            }
        }
    }

    // MARK: - Native helpers (songlistpanel.cpp anonymous namespace)

    /// A song's category is its label up to and including the first
    /// underscore; labels without one fall into the Other bucket.
    private static func prefix(of label: String) -> String {
        guard let underscore = label.firstIndex(of: "_"), underscore > label.startIndex else {
            return ""
        }
        return String(label[...underscore])
    }

    /// Friendly names for the prefixes every Gen 3 decomp shares; anything
    /// else shows as the raw prefix.
    private static func categoryName(_ prefix: String) -> String {
        switch prefix {
        case "mus_": return "Music (mus_)"
        case "se_": return "Sound effects (se_)"
        case "ph_": return "Bard phonemes (ph_)"
        default: return prefix + "*"
        }
    }
}
