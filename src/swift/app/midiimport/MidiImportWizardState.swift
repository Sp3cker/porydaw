import Foundation
import PorydawCore
import PorydawProject

public struct ImportControllerRowValue: Equatable, Sendable {
    public let controller: String
    public let function: String
    public let events: String
    public let inGame: String
    public let needsAttention: Bool

    init(controller: String, function: String, count: Int, support: ImportSupport) {
        self.controller = controller
        self.function = function
        events = String(count)
        switch support {
        case .supported: inGame = "Yes"
        case .notExported: inGame = "No"
        case .needsReview: inGame = "Needs review"
        }
        needsAttention = support != .supported
    }
}

public struct ImportFinishRefusal: Error, Equatable, Sendable {
    public let title: String
    public let message: String
}

public struct ImportFinishPlan: Equatable, Sendable {
    public let label: String
    public let constant: String
    public let player: String
    public let config: SongConfig
    public let createVoicegroup: Bool
    public let rescale: Bool
    public let extendedClocks: Bool
}

/// Pure three-page import choices; the controller owns I/O and the source lifetime.
public struct MidiImportWizardState: Equatable, Sendable {
    public private(set) var page = 0
    public let windowTitle: String
    public let analysisPlayerNames: [String]
    public let identityPlayerNames: [String]
    public private(set) var playerIndex = 0
    public private(set) var summary: ImportAnalysisSummary
    public let offersRescale: Bool
    public private(set) var controllerRows: [ImportControllerRowValue]
    public private(set) var label: String
    public private(set) var constant: String
    public var nameHint: String {
        takenLabels.contains(label) ? "A song named \(label) already exists." : ""
    }
    public var identityComplete: Bool {
        !label.isEmpty && !constant.isEmpty && !takenLabels.contains(label)
    }
    public let voicegroupOptions: [String]
    public let canCreateVoicegroup: Bool
    public var rescale: Bool
    public var voicegroupText: String
    public var volume = 100
    public var reverb = kDefaultReverb
    public var priority = 0
    public var exactGate = true
    public var extendedClocks = false
    public var noCompression = false

    private let source: MidiFile
    private let project: SongImportProjectData
    private let takenLabels: Set<String>
    private var constantEdited = false

    public init(
        source: MidiFile, sourceFileName: String, project: SongImportProjectData,
        takenLabels: Set<String>
    ) {
        self.source = source
        self.project = project
        self.takenLabels = takenLabels
        windowTitle = "Import MIDI — \(sourceFileName)"
        analysisPlayerNames = project.players.map { MidiImport.playerRoleName($0.name, includeSymbol: false) }
        identityPlayerNames = project.players.map { MidiImport.playerRoleName($0.name, includeSymbol: true) }
        offersRescale = source.division % 24 != 0
        rescale = offersRescale
        label = MidiImport.suggestedSongLabel(sourceFileName: sourceFileName)
        constant = SongCatalog.constantForLabel(label)
        canCreateVoicegroup = project.canCreateVoicegroup
        voicegroupOptions =
            (project.canCreateVoicegroup ? ["(create a new voicegroup for this song)"] : [])
            + project.voicegroupArgs.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        voicegroupText =
            voicegroupOptions.isEmpty
            ? ""
            : voicegroupOptions[
                project.canCreateVoicegroup && voicegroupOptions.count > 1 ? 1 : 0]
        let player = project.players.first
        let analysis = MidiImport.analyze(
            source,
            trackBudget: MidiImport.trackLimit(playerTrackCount: player?.trackCount ?? -1),
            playerName: player?.name ?? "")
        summary = ImportAnalysisSummary(
            analysis: analysis,
            trackLimit: MidiImport.trackLimit(playerTrackCount: player?.trackCount ?? -1),
            wasFormat0: source.wasFormat0)
        controllerRows = Self.rows(for: analysis)
    }

    public var selectedSource: MidiFile { source }

    public mutating func selectPlayer(_ index: Int) {
        guard project.players.indices.contains(index) else { return }
        playerIndex = index
        let player = project.players[index]
        let limit = MidiImport.trackLimit(playerTrackCount: player.trackCount)
        let analysis = MidiImport.analyze(source, trackBudget: limit, playerName: player.name)
        summary = ImportAnalysisSummary(
            analysis: analysis, trackLimit: limit,
            wasFormat0: source.wasFormat0)
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
        guard page < 2, page != 1 || identityComplete else { return false }
        page += 1
        return true
    }

    @discardableResult public mutating func back() -> Bool {
        guard page > 0 else { return false }
        page -= 1
        return true
    }

    public func finishPlan() -> Result<ImportFinishPlan, ImportFinishRefusal> {
        guard page == 2, identityComplete, project.players.indices.contains(playerIndex) else {
            return .failure(
                ImportFinishRefusal(title: "Import MIDI", message: "Complete the song identity before finishing."))
        }
        let trimmed = voicegroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let create = canCreateVoicegroup && trimmed == "(create a new voicegroup for this song)"
        if create && project.voicegroupArgs.contains("_" + label) {
            return .failure(
                ImportFinishRefusal(
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
            ImportFinishPlan(
                label: label, constant: constant,
                player: project.players[playerIndex].name, config: config,
                createVoicegroup: create, rescale: offersRescale && rescale,
                extendedClocks: extendedClocks))
    }

    private static func rows(for analysis: ImportAnalysis) -> [ImportControllerRowValue] {
        analysis.controllers.map {
            ImportControllerRowValue(
                controller: "CC \($0.controller)", function: $0.label,
                count: $0.count, support: $0.support)
        }
            + analysis.xcmd.map {
                ImportControllerRowValue(
                    controller: "XCMD", function: $0.label,
                    count: $0.count, support: $0.support)
            }
    }
}
