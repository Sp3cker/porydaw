import Foundation
import PorydawVoicegroup

public struct KitUsageScanError: Error, Equatable, Sendable, LocalizedError {
    public let file: String
    public let reason: String
    public var errorDescription: String? { "\(file): \(reason)" }
}

public enum KitUsageScanner {
    /// Resolves a loaded source's canonical parent declaration, not its filename alias.
    public static func canonicalSection(
        projectRoot: String, sourceRelativePath: String, sectionLabel: String
    ) throws -> String {
        if !sectionLabel.isEmpty { return sectionLabel }
        let path = projectRoot + "/" + sourceRelativePath
        let labels = VoicegroupSource.declarationLabels(in: Array(try ProjectFileStore.read(path)))
        guard labels.count == 1, let label = labels.first else {
            throw KitUsageScanError(file: path, reason: "Expected one voicegroup declaration; found \(labels.count).")
        }
        return label
    }

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
                guard
                    let section = try? canonicalSection(
                        projectRoot: projectRoot, sourceRelativePath: String(path.dropFirst(projectRoot.count + 1)),
                        sectionLabel: reference.sectionLabel), section != excludingSection
                else { continue }
                let voice = reference.voice
                if voice.symbol == subgroupSymbol
                    || (voice.macro == .keysplit && tableName != nil && voice.keysplitTable == tableName)
                {
                    sections.insert(section)
                }
            }
        }
        return sections.sorted()
    }
}
