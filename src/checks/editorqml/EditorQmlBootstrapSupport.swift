import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawAppCommands
import PorydawCore
import QtBridge
import QtBridgeCpp

extension EditorQmlBootstrap {
    func requestHistory(redo: Bool) -> Bool {
        guard let session else { return false }
        if redo {
            guard session.canRedo else { return false }
            session.requestRedo()
        } else {
            guard session.canUndo else { return false }
            session.requestUndo()
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            if redo ? session.canUndo : session.canRedo { return true }
        }
        return false
    }
    /// Opens the staged project through the production session path and drives
    /// the asynchronous work to a definite outcome.
    ///
    /// The core session checks pump the run loop the same way: a Qt Quick Test
    /// slot can run outside any Qt event loop, so a main-actor task is only
    /// serviced while something drains the main queue and a merely kicked-off
    /// open would never complete. The wait is bounded, and a failure names the
    /// session's own reason in the lane's captured output.
    func startImpl(songLabel: String) -> Bool {
        guard let session, !songLabel.isEmpty else { return false }
        EditorQmlBootstrap.stageSongLabel(songLabel)
        session.openProjectAndSong(path: projectRoot, label: songLabel)
        let initialError = session.lastSaveError
        let deadline = Date().addingTimeInterval(EditorQmlBootstrap.openTimeout)
        while Date() < deadline {
            if session.projectOpen && session.songOpen { return true }
            if !session.lastSaveError.isEmpty, session.lastSaveError != initialError { break }
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return reportOpenOutcome(session, songLabel: songLabel, initialError: initialError)
    }

    /// Bounded like the windowed harness's own session-open waits.
    private static let openTimeout: TimeInterval = 15

    /// A failure the session reported is a verdict, and the lane must show it as
    /// one. Running out of time is not: the open is still in flight, the suite's
    /// own bounded wait has not run yet, so the lane names what it saw and keeps
    /// the request alive for that wait instead of inventing a second timeout.
    private func reportOpenOutcome(
        _ session: ApplicationSession, songLabel: String,
        initialError: String
    ) -> Bool {
        let failure = session.lastSaveError
        let state = "projectOpen=\(session.projectOpen) songOpen=\(session.songOpen)"
        let reason =
            !failure.isEmpty && failure != initialError
            ? "failed (\(state)): \(failure)"
            : "is still in flight (\(state)) after \(EditorQmlBootstrap.openTimeout)s"
        FileHandle.standardError.write(
            Data(
                "editorqml-drawer: opening \"\(songLabel)\" at \(projectRoot) \(reason)\n".utf8))
        return failure.isEmpty || failure == initialError
    }
    /// Attaches a real `DrawerTestPage` in the kind's slot. Rejects an unknown
    /// kind, a URL the container would not resolve (blank, or no URL at all),
    /// an occupied slot and a call before the session exists, exactly as the
    /// container rejects them, so `true` means the attachment really happened.
    func attachTestSectionImpl(kind: Int, contentUrl: String) -> Bool {
        let trimmedUrl = contentUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session,
            let sectionKind = DrawerSectionKind(rawValue: kind),
            testPages[sectionKind] == nil,
            !trimmedUrl.isEmpty,
            URL(string: trimmedUrl) != nil
        else { return false }
        let page = DrawerTestPage(
            sectionKind: sectionKind,
            contentUrl: trimmedUrl,
            maximumBodyHeight: testMaximums[sectionKind],
            onCancel: { [weak self] in self?.pageCancelCount += 1 }
        )
        testPages[sectionKind] = page
        session.drawerPresenter().attachSection(page)
        return true
    }
    /// Drops the kind's page. The suite calls this only after the composition
    /// hosting those pages is destroyed — the lane's shape of production's
    /// rule that a page owner is released only once the host confirms teardown.
    /// The container cancels synchronously, so the cancel lands in
    /// `pageCancelCount` before this returns.
    func detachTestSectionImpl(kind: Int) {
        guard let session,
            let sectionKind = DrawerSectionKind(rawValue: kind),
            let page = testPages.removeValue(forKey: sectionKind)
        else { return }
        session.drawerPresenter().detachSection(page)
    }
}
