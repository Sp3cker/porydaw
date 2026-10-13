import Foundation
import PorydawVoicegroup

/// Resolves sample references through current parsed voicegroup texts, including staged overlays.
public enum SampleUsageScanner {
    /// Created subgroups count only when reachable from another voicegroup.
    /// Parsed overlay values, keyed by canonical declaration, override that section's disk text.
    /// - Throws: A source read failure; callers must not offer deletion on an incomplete scan.
    public static func referenced(
        projectRoot: String, candidates: Set<String>, overlay: [String: [VgVoice?]],
        createdSubgroups: Set<String>
    ) throws -> Set<String> {
        let paths = try ProjectFileStore.voicegroupFiles(projectRoot: projectRoot, recursive: true)
        var groups: [String: [VgVoice?]] = [:]
        for path in paths {
            let bytes = Array(try ProjectFileStore.read(path))
            let labels = VoicegroupSource.declarationLabels(in: bytes)
            for label in labels {
                let canonical = try KitUsageScanner.canonicalSection(
                    bytes: bytes, path: path, sectionLabel: label)
                if let voices = overlay[canonical] {
                    groups[canonical] = voices
                    continue
                }
                let source = VoicegroupSource()
                var error: String?
                let location = VoicegroupLocation(filePath: path, sectionLabel: label)
                if !source.open(location: location, error: &error) {
                    guard labels.count == 1,
                        source.open(location: VoicegroupLocation(filePath: path, sectionLabel: ""), error: &error)
                    else { throw ProjectFileStoreError.cannotRead(path: path) }
                }
                groups[canonical] = (0..<128).map { (slot: Int) -> VgVoice? in source.voiceAt(slot: slot) }
            }
        }
        groups.merge(overlay) { _, current in current }
        var pending = groups.keys.filter { !createdSubgroups.contains($0) }
        var visited: Set<String> = []
        var used: Set<String> = []
        while let symbol = pending.popLast() {
            guard visited.insert(symbol).inserted, let voices = groups[symbol] else { continue }
            for entry in voices {
                guard let voice = entry else { continue }
                if voice.macro == .keysplitAll || voice.macro == .keysplit {
                    let canonical = groups[voice.symbol] != nil ? voice.symbol : "voicegroup_" + voice.symbol
                    pending.append(canonical)
                } else if voice.symbol.hasPrefix("DirectSoundWaveData_") {
                    let name = String(voice.symbol.dropFirst("DirectSoundWaveData_".count))
                    if candidates.contains(name) { used.insert(name) }
                }
            }
        }
        return used
    }
}
