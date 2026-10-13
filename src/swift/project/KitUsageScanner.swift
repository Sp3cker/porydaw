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
        return try canonicalSection(
            bytes: Array(try ProjectFileStore.read(path)), path: path, sectionLabel: sectionLabel)
    }

    /// Resolves a canonical declaration from bytes already read by a scanner.
    public static func canonicalSection(bytes: [UInt8], path: String, sectionLabel: String) throws -> String {
        if !sectionLabel.isEmpty { return sectionLabel }
        let labels = VoicegroupSource.declarationLabels(in: bytes)
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
        let paths = (try? ProjectFileStore.voicegroupFiles(projectRoot: projectRoot, recursive: false)) ?? []
        var sections: Set<String> = []
        for path in paths {
            guard let bytes = try? ProjectFileStore.read(path) else { continue }
            let content = Array(bytes)
            for reference in VoicegroupSource.kitReferences(in: content) {
                guard
                    let section = try? canonicalSection(
                        bytes: content, path: path, sectionLabel: reference.sectionLabel),
                    section != excludingSection
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
