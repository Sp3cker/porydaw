import Foundation

public struct NewSongPlayer: Sendable {
    public let symbol: String
    public let displayName: String

    public init(symbol: String, displayName: String) {
        self.symbol = symbol
        self.displayName = displayName
    }
}

public struct NewSongCatalog: Sendable {
    public let songLabels: [String]
    public let players: [NewSongPlayer]
    public let voicegroupArgs: [String]
    public let canCreateVoicegroup: Bool

    public init(
        songLabels: [String], players: [NewSongPlayer], voicegroupArgs: [String],
        canCreateVoicegroup: Bool
    ) {
        self.songLabels = songLabels
        self.players = players
        self.voicegroupArgs = voicegroupArgs
        self.canCreateVoicegroup = canCreateVoicegroup
    }
}

public struct NewSongRequest: Sendable {
    public let label: String
    public let constant: String
    public let player: String
    public let voicegroupArg: String
    public let masterVolume: Int
    public let reverb: Int
    public let priority: Int
    public let exactGate: Bool
    public let extendedClocks: Bool
    public let noCompression: Bool
    public let newVoicegroupName: String

    public init(
        label: String, constant: String, player: String, voicegroupArg: String,
        masterVolume: Int, reverb: Int, priority: Int, exactGate: Bool,
        extendedClocks: Bool, noCompression: Bool, newVoicegroupName: String
    ) {
        self.label = label
        self.constant = constant
        self.player = player
        self.voicegroupArg = voicegroupArg
        self.masterVolume = masterVolume
        self.reverb = reverb
        self.priority = priority
        self.exactGate = exactGate
        self.extendedClocks = extendedClocks
        self.noCompression = noCompression
        self.newVoicegroupName = newVoicegroupName
    }
}

struct NewSongDraft {
    static let createVoicegroupText = "(create a new voicegroup for this song)"

    let playerNames: [String]
    let voicegroupNames: [String]

    private(set) var name: String = ""
    private(set) var constant: String = ""
    private(set) var playerIndex: Int = 0
    private(set) var voicegroupIndex: Int
    private(set) var voicegroupText: String
    private(set) var masterVolume: Int = 100
    private(set) var reverb: Int = 50
    private(set) var priority: Int = 0
    private(set) var exactGate: Bool = true
    private(set) var extendedClocks: Bool = false
    private(set) var noCompression: Bool = false

    private let catalog: NewSongCatalog
    private let players: [NewSongPlayer]
    private var constantWasEdited = false

    init(catalog: NewSongCatalog) {
        self.catalog = catalog
        players = catalog.players.isEmpty
            ? [
                NewSongPlayer(
                    symbol: "MUSIC_PLAYER_BGM",
                    displayName: "Background music (MUSIC_PLAYER_BGM)")
            ]
            : catalog.players
        playerNames = players.map(\.displayName)

        let existingNames = catalog.voicegroupArgs.map(voicegroupDisplayName)
        voicegroupNames = catalog.canCreateVoicegroup
            ? [Self.createVoicegroupText] + existingNames
            : existingNames
        if catalog.canCreateVoicegroup && !existingNames.isEmpty {
            voicegroupIndex = 1
            voicegroupText = existingNames[0]
        } else if let first = voicegroupNames.first {
            voicegroupIndex = 0
            voicegroupText = first
        } else {
            voicegroupIndex = -1
            voicegroupText = ""
        }
    }

    mutating func reset() {
        self = NewSongDraft(catalog: catalog)
    }

    mutating func editName(_ text: String) {
        name = text.lowercased()
        if !constantWasEdited {
            constant = name.uppercased()
        }
    }

    mutating func editConstant(_ text: String) {
        constantWasEdited = true
        constant = text
    }

    mutating func selectPlayer(_ index: Int) {
        guard players.indices.contains(index) else { return }
        playerIndex = index
    }

    mutating func selectVoicegroup(_ index: Int) {
        guard voicegroupNames.indices.contains(index) else { return }
        voicegroupIndex = index
        voicegroupText = voicegroupNames[index]
    }

    mutating func editVoicegroup(_ text: String) {
        voicegroupText = text
        voicegroupIndex = voicegroupNames.firstIndex(of: text) ?? -1
    }

    mutating func setMasterVolume(_ value: Int) {
        masterVolume = clampedMidiValue(value)
    }

    mutating func setReverb(_ value: Int) {
        reverb = clampedMidiValue(value)
    }

    mutating func setPriority(_ value: Int) {
        priority = clampedMidiValue(value)
    }

    mutating func setExactGate(_ value: Bool) {
        exactGate = value
    }

    mutating func setExtendedClocks(_ value: Bool) {
        extendedClocks = value
    }

    mutating func setNoCompression(_ value: Bool) {
        noCompression = value
    }

    func identityValidation() -> (valid: Bool, error: String) {
        guard !name.isEmpty, !constant.isEmpty else { return (false, "") }
        guard isValidSongLabel(name) else {
            return (
                false,
                "Use lowercase letters, numbers, and underscores; start with a letter or underscore."
            )
        }
        guard !catalog.songLabels.contains(name) else {
            return (false, "A song named \(name) already exists.")
        }
        return (true, "")
    }

    func soundValidation() -> (valid: Bool, error: String) {
        guard isCreatingVoicegroup,
            catalog.voicegroupArgs.contains("_\(name)")
        else { return (true, "") }
        return (
            false,
            "A voicegroup named voicegroup_\(name) already exists — pick it from the list instead."
        )
    }

    func request() -> NewSongRequest {
        let creatingVoicegroup = isCreatingVoicegroup
        let voicegroupArg = creatingVoicegroup
            ? "_\(name)"
            : normalizedVoicegroupArg(
                voicegroupText.trimmingCharacters(in: .whitespacesAndNewlines),
                knownArgs: catalog.voicegroupArgs)
        return NewSongRequest(
            label: name,
            constant: constant,
            player: players[playerIndex].symbol,
            voicegroupArg: voicegroupArg,
            masterVolume: masterVolume,
            reverb: reverb,
            priority: priority,
            exactGate: exactGate,
            extendedClocks: extendedClocks,
            noCompression: noCompression,
            newVoicegroupName: creatingVoicegroup ? name : "")
    }

    private var isCreatingVoicegroup: Bool {
        catalog.canCreateVoicegroup && voicegroupText == Self.createVoicegroupText
    }
}

private func isValidSongLabel(_ value: String) -> Bool {
    guard let first = value.utf8.first, isLowercaseLetter(first) || first == asciiUnderscore else {
        return false
    }
    return value.utf8.dropFirst().allSatisfy {
        isLowercaseLetter($0) || isDigit($0) || $0 == asciiUnderscore
    }
}

private func voicegroupDisplayName(_ arg: String) -> String {
    arg.hasPrefix("_") ? String(arg.dropFirst()) : arg
}

private func normalizedVoicegroupArg(_ text: String, knownArgs: [String]) -> String {
    guard !text.isEmpty, !text.hasPrefix("_") else { return text }
    if !knownArgs.contains("_\(text)"), knownArgs.contains(text) {
        return text
    }
    return "_\(text)"
}

private func clampedMidiValue(_ value: Int) -> Int {
    min(max(value, 0), 127)
}

private func isLowercaseLetter(_ byte: UInt8) -> Bool {
    byte >= asciiLowercaseA && byte <= asciiLowercaseZ
}

private func isDigit(_ byte: UInt8) -> Bool {
    byte >= asciiZero && byte <= asciiNine
}

private let asciiLowercaseA = Character("a").asciiValue!
private let asciiLowercaseZ = Character("z").asciiValue!
private let asciiZero = Character("0").asciiValue!
private let asciiNine = Character("9").asciiValue!
private let asciiUnderscore = Character("_").asciiValue!
