import QtBridge

// Read-only observations for the demo smoke. Never rendered as application UI.
@MainActor
@QtBridgeable
public final class NewSongDemoResult {
    public var completedCount: Int = 0
    public var accepted: Bool = false
    public var label: String = ""
    public var constant: String = ""
    public var player: String = ""
    public var voicegroupArg: String = ""
    public var newVoicegroupName: String = ""
    public var masterVolume: Int = 0
    public var reverb: Int = 0
    public var priority: Int = 0
    public var exactGate: Bool = false
    public var extendedClocks: Bool = false
    public var noCompression: Bool = false

    public init() {}

    @QtIgnored
    func record(_ request: NewSongRequest?) {
        accepted = request != nil
        label = request?.label ?? ""
        constant = request?.constant ?? ""
        player = request?.player ?? ""
        voicegroupArg = request?.voicegroupArg ?? ""
        newVoicegroupName = request?.newVoicegroupName ?? ""
        masterVolume = request?.masterVolume ?? 0
        reverb = request?.reverb ?? 0
        priority = request?.priority ?? 0
        exactGate = request?.exactGate ?? false
        extendedClocks = request?.extendedClocks ?? false
        noCompression = request?.noCompression ?? false
        completedCount += 1
        if let request {
            print("NEW_SONG_WIZARD accepted label=\(request.label) constant=\(request.constant) player=\(request.player) voicegroup=\(request.voicegroupArg); demo does not write project files")
        } else {
            print("NEW_SONG_WIZARD cancelled")
        }
    }
}
// Demo composition only. The reusable wizard receives values and returns a
// typed request; a production workspace will own catalog freshness and commit.
func newSongDemoCatalog() -> NewSongCatalog {
    NewSongCatalog(
        songLabels: ["mus_route101"],
        players: [
            NewSongPlayer(symbol: "MUSIC_PLAYER_BGM", displayName: "Background music (MUSIC_PLAYER_BGM)"),
            NewSongPlayer(symbol: "MUSIC_PLAYER_SE", displayName: "Sound effect (MUSIC_PLAYER_SE)"),
        ],
        voicegroupArgs: ["_main", "_se", "_mus_existing_bank"],
        canCreateVoicegroup: true)
}

