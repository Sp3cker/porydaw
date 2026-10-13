import Foundation
import PorydawVoicegroup

public enum KitUsageScanner {
    /// Returns sorted, unique canonical declaration labels (e.g. voicegroup_fixture_rich).
    /// `excludingSection` uses the same canonical label convention.
    public static func usage(
        projectRoot: String, subgroupSymbol: String, tableName: String?, excludingSection: String
    ) -> [String] {
        let layout = ProjectLayout(projectRoot: projectRoot).ensuringDeepScan()
        var paths = Set(layout.monolithicFiles)
        for directory in layout.voicegroupDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for name in entries {
                let lower = name.lowercased()
                guard lower.hasSuffix(".inc") || lower.hasSuffix(".s") else { continue }
                paths.insert(directory + "/" + name)
            }
        }
        var sections: Set<String> = []
        for path in paths {
            guard let bytes = try? ProjectFileStore.read(path) else { continue }
            for reference in VoicegroupSource.kitReferences(in: Array(bytes)) {
                guard reference.sectionLabel != excludingSection else { continue }
                let voice = reference.voice
                if voice.symbol == subgroupSymbol
                    || (voice.macro == .keysplit && tableName != nil && voice.keysplitTable == tableName)
                {
                    sections.insert(reference.sectionLabel)
                }
            }
        }
        return sections.sorted()
    }
}
