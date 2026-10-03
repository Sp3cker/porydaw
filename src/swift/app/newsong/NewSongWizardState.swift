import Foundation
import PorydawCore
import PorydawProject

public struct NewSongFinishRefusal: Error, Equatable, Sendable {
    public let title: String
    public let message: String
}

/// Pure identity and sound choices for a blank song.
public struct NewSongWizardState: Equatable, Sendable {
    public private(set) var page = 0
    public let windowTitle: String
    public let identityPlayerNames: [String]
    public private(set) var playerIndex = 0
    public private(set) var label = ""
    public private(set) var constant = ""
    public var nameHint: String {
        takenLabels.contains(label) ? "A song named \(label) already exists." : ""
    }
    public var identityComplete: Bool {
        !label.isEmpty && !constant.isEmpty && !takenLabels.contains(label)
    }
    public let voicegroupOptions: [String]
    public let canCreateVoicegroup: Bool
    public var voicegroupText: String
    public var volume = 100
    public var reverb = kDefaultReverb
    public var priority = 0
    public var exactGate = true
    public var extendedClocks = false
    public var noCompression = false

    private let project: SongImportProjectData
    private let takenLabels: Set<String>
    private var constantEdited = false

    public init(project: SongImportProjectData, takenLabels: Set<String>) {
        self.project = project
        self.takenLabels = takenLabels
        windowTitle = "New Song"
        identityPlayerNames = project.players.map { MidiImport.playerRoleName($0.name, includeSymbol: true) }
        canCreateVoicegroup = project.canCreateVoicegroup
        voicegroupOptions =
            (project.canCreateVoicegroup ? ["(create a new voicegroup for this song)"] : [])
            + project.voicegroupArgs.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        voicegroupText =
            voicegroupOptions.isEmpty
            ? ""
            : voicegroupOptions[project.canCreateVoicegroup && voicegroupOptions.count > 1 ? 1 : 0]
    }

    public mutating func selectPlayer(_ index: Int) {
        guard project.players.indices.contains(index) else { return }
        playerIndex = index
    }

    @discardableResult public mutating func editLabel(_ proposed: String) -> String {
        label = SongListPresenter.acceptSongLabelEdit(previous: label, proposed: proposed)
        if !constantEdited { constant = SongCatalog.constantForLabel(label) }
        return label
    }

    public mutating func editConstant(_ text: String) {
        constant = text
        constantEdited = true
    }

    @discardableResult public mutating func next() -> Bool {
        guard page < 1, identityComplete else { return false }
        page += 1
        return true
    }

    @discardableResult public mutating func back() -> Bool {
        guard page > 0 else { return false }
        page -= 1
        return true
    }

    public func finishPlan() -> Result<SongImportRequest, NewSongFinishRefusal> {
        guard page == 1, identityComplete, project.players.indices.contains(playerIndex) else {
            return .failure(
                NewSongFinishRefusal(
                    title: "New Song", message: "Complete the song identity before finishing."))
        }
        let trimmed = voicegroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let create = canCreateVoicegroup && trimmed == "(create a new voicegroup for this song)"
        if create && project.voicegroupArgs.contains("_" + label) {
            return .failure(
                NewSongFinishRefusal(
                    title: "New Voicegroup",
                    message: "A voicegroup named voicegroup_\(label) already exists — pick it from the list instead."))
        }
        var config = SongConfig(
            voicegroupArgument: create
                ? "_" + label
                : VoiceListSemantics.voicegroupArg(fromDisplay: trimmed, knownArgs: project.voicegroupArgs),
            masterVolume: volume, reverb: reverb, priority: priority, exactGate: exactGate,
            extendedClocks: extendedClocks, noCompression: noCompression)
        config.rawFlags = SongFlags.merge(config)
        return .success(
            SongImportRequest(
                label: label, constant: constant, player: project.players[playerIndex].name,
                config: config, createVoicegroup: create, midi: MidiFile.blankSong()))
    }
}
