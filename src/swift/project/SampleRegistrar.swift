import Foundation

public struct SampleRegistrationError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) { self.message = message }
}

public enum SampleRegistrar {
    public struct Probe: Sendable, Equatable {
        public enum Pipeline: Sendable, Equatable { case wav2agb, legacyAif, unknown }

        public let pipeline: Pipeline
        public let incPath: String
        public let samplesDir: String
        public let refusal: String
        public var ok: Bool { pipeline == .wav2agb }
    }

    /// Examines the project's registration anchor and actual sample build rules.
    public static func probe(projectRoot: String) -> Probe {
        let incPath = projectRoot + "/sound/direct_sound_data.inc"
        let samplesDir = projectRoot + "/sound/direct_sound_samples"
        if !ProjectFileStore.exists(incPath) {
            return Probe(pipeline: .unknown, incPath: incPath, samplesDir: samplesDir,
                refusal: "cannot find sound/direct_sound_data.inc — samples are registered there. Set up pret's sample layout, then import again.")
        }
        var paths = [projectRoot + "/Makefile", projectRoot + "/makefile"]
        if let files = try? FileManager.default.contentsOfDirectory(atPath: projectRoot) {
            paths += files.filter { $0.hasSuffix(".mk") }.map { projectRoot + "/" + $0 }
        }
        if hasPatternRule(paths, ext: "wav", tool: "wav2agb") {
            return Probe(pipeline: .wav2agb, incPath: incPath, samplesDir: samplesDir, refusal: "")
        }
        if hasPatternRule(paths, ext: "aif", tool: "aif2pcm") {
            return Probe(pipeline: .legacyAif, incPath: incPath, samplesDir: samplesDir,
                refusal: "this project predates wav2agb: its samples build from .aif sources via aif2pcm. Port the sample pipeline to wav2agb (pret's current layout), then import again.")
        }
        return Probe(pipeline: .unknown, incPath: incPath, samplesDir: samplesDir,
            refusal: "cannot find a wav2agb build rule (%.bin: %.wav) in the project's make files; add pret's audio_rules.mk pattern rule, then import again.")
    }

    private static func hasPatternRule(_ paths: [String], ext: String, tool: String) -> Bool {
        guard let rule = try? Regex("%\\.bin\\s*:(?!=).*%\\.\(ext)\\s*$") else { return false }
        for path in paths {
            guard let data = try? ProjectFileStore.read(path) else { continue }
            let lines = ProjectFileStore.splitLines(data).lines
            for (index, raw) in lines.enumerated() {
                var line = raw
                if line.last == 13 { line.removeLast() }
                guard String(decoding: line, as: UTF8.self).contains(rule) else { continue }
                for recipe in lines.dropFirst(index + 1) {
                    guard recipe.first == 9 else { break }
                    if String(decoding: recipe, as: UTF8.self).lowercased().contains(tool) { return true }
                }
            }
        }
        return false
    }

    /// Returns the fork's refusal message, or nil for a valid, unused name.
    public static func validate(projectRoot: String, name: String, existingSymbols: [String]) -> String? {
        if name.isEmpty { return "sample name is empty." }
        guard let grammar = try? Regex("^[a-z0-9_]+$"), name.contains(grammar) else {
            return "sample names use lowercase letters, digits, and underscores only."
        }
        let symbol = "DirectSoundWaveData_" + name
        if existingSymbols.contains(symbol) { return "\(symbol) already exists in this project." }
        for ext in [".wav", ".bin", ".aif"] {
            if ProjectFileStore.exists(projectRoot + "/sound/direct_sound_samples/" + name + ext) {
                return "\(name)\(ext) already exists in sound/direct_sound_samples."
            }
        }
        return nil
    }

    /// Writes the WAV before atomically extending its assembly registration.
    public static func register(projectRoot: String, name: String, wav: Data) throws(SampleRegistrationError) {
        let layout = probe(projectRoot: projectRoot)
        guard layout.ok else { throw SampleRegistrationError(message: layout.refusal) }
        if let refusal = validate(projectRoot: projectRoot, name: name,
            existingSymbols: VoicegroupSource.directSoundSymbols(projectRoot)) {
            throw SampleRegistrationError(message: refusal)
        }
        do { try ProjectFileStore.mkpath(layout.samplesDir) }
        catch { throw SampleRegistrationError(message: "cannot create \(layout.samplesDir).") }
        let wavPath = layout.samplesDir + "/" + name + ".wav"
        do { try ProjectFileStore.writeAtomic(wavPath, data: wav) }
        catch { throw SampleRegistrationError(message: "cannot write \(wavPath).") }

        let content: Data
        do { content = try ProjectFileStore.read(layout.incPath) }
        catch { throw SampleRegistrationError(message: "cannot write \(layout.incPath).") }
        let lines = ProjectFileStore.splitLines(content)
        let eol = lines.crlf ? "\r\n" : "\n"
        var alignIndent = "\t"
        var incbinIndent = "\t"
        for raw in lines.lines {
            var line = raw
            if line.last == 13 { line.removeLast() }
            let text = String(decoding: line, as: UTF8.self)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let start = text.range(of: trimmed) else { continue }
            let indent = String(text[..<start.lowerBound])
            if trimmed.hasPrefix(".align") { alignIndent = indent }
            else if trimmed.hasPrefix(".incbin") { incbinIndent = indent }
        }
        var block = ""
        if !content.isEmpty && !lines.endsWithNewline { block += eol }
        if !content.isEmpty { block += eol }
        block += alignIndent + ".align 2" + eol
        block += "DirectSoundWaveData_" + name + "::" + eol
        block += incbinIndent + ".incbin \"sound/direct_sound_samples/" + name + ".bin\"" + eol
        var updated = content
        updated.append(contentsOf: block.utf8)
        do { try ProjectFileStore.writeAtomic(layout.incPath, data: updated) }
        catch { throw SampleRegistrationError(message: "cannot write \(layout.incPath).") }
    }
}
