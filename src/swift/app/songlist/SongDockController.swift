import Foundation
import QtBridge

/// Owns the Songs dock's plan/confirmation boundary. A song ID is resolved
/// against the current listing before every operation; row positions and
/// display strings are never used as navigation identity.
@MainActor
@QtBridgeable
public final class SongDockController {
    @QtIgnored public let presenter = SongListPresenter()
    @QtTracked public var confirmation = ""
    @QtTracked public var confirmationLabel = ""
    @QtTracked public var registrationConstant = ""
    @QtTracked public var confirmationDetail = ""
    @QtTracked public var deletableVoicegroup = ""
    @QtTracked public var busy = false

    private weak var session: ApplicationSession?
    private var service: ProjectService?
    private var registrationPlan: SongRegistrationPlan?
    private var deletionPlan: SongDeletionPlan?
    private var operation: Task<Void, Never>?

    public init() {
        presenter.onSongActivated = { [weak self] id in self?.open(id, newTab: false) }
        presenter.onSongOpenInNewTabRequested = { [weak self] id in self?.open(id, newTab: true) }
        presenter.onSongRegisterRequested = { [weak self] id in self?.prepare(id, deleting: false) }
        presenter.onSongDeleteRequested = { [weak self] id in self?.prepare(id, deleting: true) }
    }

    public func songListPresenter() -> SongListPresenter { presenter }

    @QtIgnored
    func attach(session: ApplicationSession) { self.session = session }

    @QtIgnored
    func install(service: ProjectService, songs: [SongListing]) {
        operation?.cancel()
        operation = nil
        busy = false
        clearConfirmation()
        self.service = service
        presenter.setSongs(songs)
        syncSelection()
    }

    @QtIgnored
    func detach() {
        operation?.cancel()
        operation = nil
        busy = false
        service = nil
        presenter.setSongs([])
        clearConfirmation()
    }

    @QtIgnored
    func syncSelection() {
        let label = session?.songTabs.selectedPage?.title
        presenter.setCurrentSong(songId: presenter.songListings.first { $0.label == label }?.id ?? -1)
    }

    private func open(_ songId: Int, newTab: Bool) {
        guard let song = presenter.listing(songId: songId) else { return }
        session?.openSongFromDock(label: song.label, newTab: newTab)
    }

    private func prepare(_ songId: Int, deleting: Bool) {
        guard !busy, confirmation.isEmpty, let service,
              let song = presenter.listing(songId: songId) else { return }
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                if deleting {
                    let plan = try await service.songDeletionPlan(label: song.label)
                    guard !Task.isCancelled, self.service === service else { return }
                    if plan.tableIndex == 0 {
                        self.session?.operationFailed(message: "\(song.label) is the first usable table entry (song ID 0); the engine's fallback. It cannot be deleted.")
                    } else {
                        self.deletionPlan = plan
                        self.confirmationLabel = song.label
                        self.deletableVoicegroup = plan.deletableVoicegroupDisplay ?? ""
                        self.confirmationDetail = self.deletionDetails(plan)
                        self.confirmation = "delete"
                    }
                } else {
                    let plan = try await service.songRegistrationPlan(label: song.label)
                    guard !Task.isCancelled, self.service === service else { return }
                    self.registrationPlan = plan
                    self.confirmationLabel = song.label
                    self.registrationConstant = plan.constant
                    self.confirmationDetail = plan.missingFiles.isEmpty ? "" :
                        "The following registration files need updates:\n  - " + plan.missingFiles.joined(separator: "\n  - ")
                    self.confirmation = "register"
                }
            } catch {
                if !Task.isCancelled, self.service === service {
                    self.session?.operationFailed(message: String(describing: error))
                }
            }
            if !Task.isCancelled, self.service === service { self.busy = false }
        }
    }

    public func cancelConfirmation() { clearConfirmation() }

    private func hasUnsavedSong(_ label: String) -> Bool {
        session?.songTabs.tab(label: label)?.dirty == true
    }

    public func acceptConfirmation(alsoDeleteVoicegroup: Bool) {
        guard !busy, let service else { return }
        let registration = registrationPlan
        let deletion = deletionPlan
        let label = confirmationLabel
        guard (confirmation == "register" && registration != nil) ||
              (confirmation == "delete" && deletion != nil) else { return }
        if deletion != nil, hasUnsavedSong(label) {
            session?.operationFailed(message: "Save or close \(label) before deleting its MIDI file.")
            return
        }
        clearConfirmation()
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                if let registration {
                    _ = try await service.registerSong(registration)
                } else if let deletion {
                    try await service.deleteSong(label: label, voicegroupName:
                        alsoDeleteVoicegroup ? deletion.deletableVoicegroupName : nil)
                }
                guard !Task.isCancelled, self.service === service else { return }
                let songs = try await service.songs()
                guard !Task.isCancelled, self.service === service else { return }
                self.presenter.setSongs(songs)
                self.session?.refreshSongLabels(songs.map(\.label))
                if deletion != nil, let tab = self.session?.songTabs.tab(label: label) {
                    self.session?.songTabs.requestClose(tabId: tab.tabId)
                }
                self.syncSelection()
            } catch {
                if !Task.isCancelled, self.service === service {
                    self.session?.operationFailed(message: String(describing: error))
                }
            }
            if !Task.isCancelled, self.service === service { self.busy = false }
        }
    }

    private func clearConfirmation() {
        registrationPlan = nil
        deletionPlan = nil
        confirmation = ""
        confirmationLabel = ""
        registrationConstant = ""
        confirmationDetail = ""
        deletableVoicegroup = ""
    }

    private func deletionDetails(_ plan: SongDeletionPlan) -> String {
        var details = ["Its .mid moves to .porydaw/trash.",
                       plan.lastEntry ? "Its song_table.inc line is removed outright." :
                        "Its song_table.inc entry becomes a reusable free slot, so no other song's ID changes."]
        if plan.inSongsH { details.append("songs.h") }
        if plan.inLdScript { details.append("ld_script.ld") }
        if plan.inCharmap { details.append("charmap.txt") }
        if plan.inDebugMenu { details.append("src/debug.c") }
        return details.map { "* " + $0 }.joined(separator: "\n")
    }
}
