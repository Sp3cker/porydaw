import Foundation
import PorydawDocument
import PorydawKitStudio
import PorydawSampleUI

/// One open Split Studio window: its editor, audition player, save progress and project footprint.
/// Replacing or releasing the window drops all of it at once.
@MainActor
final class KitStudioWindow {
    /// Where a save stands; the workflow publishes it as `saving` and the overwrite prompt.
    enum Save {
        case idle
        case confirmingOverwrite(prompt: String)
        case writing(Task<Void, Never>, names: Set<String>)
    }

    let presenter: KitStudioPresenter
    let footprint: KitStudioFootprint
    let pcm: PcmAuditionPlayer
    var save: Save = .idle
    var playingSlice: Int?

    init(presenter: KitStudioPresenter, footprint: KitStudioFootprint, pcm: PcmAuditionPlayer) {
        self.presenter = presenter
        self.footprint = footprint
        self.pcm = pcm
    }

    /// Slice names an in-flight save is writing; the slice-name validator treats them as taken.
    var writingNames: Set<String> {
        if case .writing(_, let names) = save { return names }
        return []
    }

    /// A save is confirming an overwrite or writing; another save waits for it to settle.
    var saveInProgress: Bool {
        if case .idle = save { return false }
        return true
    }

    /// Ends the window's work: an unfinished save stops at its next step and audition closes.
    func close() {
        if case .writing(let task, _) = save { task.cancel() }
        pcm.close()
    }
}

/// What one window owns in the project: the kit it edits, voicegroups it created and sample files it wrote.
@MainActor
final class KitStudioFootprint {
    /// A kit loaded from a song voice; saving under its name rewrites it through its session.
    struct EditTarget {
        let name: String
        let group: VoicegroupSession
        var expected: KitEditValue
    }

    /// The inputs a slice's audio renders from.
    struct RenderKey: Equatable {
        let source: Int
        let rate: Double
        let slice: KitSourceSession.Slice
    }

    /// One slice's rendered sample file.
    struct SampleFile {
        let name: String
        let key: RenderKey
        let wav: Data
    }

    var edit: EditTarget?
    var createdVoicegroups: Set<String> = []
    /// The last audio this window registered or committed per sample file; a batch that fails midway
    /// records nothing and leaves its WAVs to orphan cleanup.
    var written: [String: SampleFile] = [:]

    init(edit: EditTarget?) { self.edit = edit }

    func owns(voicegroup name: String) -> Bool { edit?.name == name || createdVoicegroups.contains(name) }
}
