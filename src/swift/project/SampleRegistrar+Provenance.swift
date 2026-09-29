import Foundation
import PorydawSample

public struct CommittedSample: Sendable {
    public let name: String
    public let wav: Data
    public let wavPath: String
    public let sidecar: SampleSidecar?
}

extension SampleRegistrar {
    /// Replaces the WAV for an existing registered symbol without touching its assembly entry.
    public static func update(projectRoot: String, name: String, wav: Data) throws(SampleRegistrationError) {
        let layout = probe(projectRoot: projectRoot)
        guard layout.ok else { throw SampleRegistrationError(message: layout.refusal) }
        let symbol = "DirectSoundWaveData_" + name
        guard VoicegroupSource.directSoundSymbols(projectRoot).contains(symbol) else {
            throw SampleRegistrationError(message: "\(symbol) is not registered in this project; use Import Sample to add new samples.")
        }
        let path = layout.samplesDir + "/" + name + ".wav"
        guard ProjectFileStore.exists(path) else {
            throw SampleRegistrationError(message: "\(name).wav does not exist in sound/direct_sound_samples — only samples with a .wav source can be updated.")
        }
        do { try ProjectFileStore.writeAtomic(path, data: wav) }
        catch { throw SampleRegistrationError(message: "cannot write \(path).") }
    }

    /// Returns the sample's version-one sidecar path.
    public static func sidecarPath(projectRoot: String, name: String) -> String {
        projectRoot + "/.porydaw/samples/" + name + ".json"
    }

    /// Writes the sidecar atomically and maintains the project-local ignore rule.
    public static func writeSidecar(projectRoot: String, name: String, _ sidecar: SampleSidecar)
        throws(SampleRegistrationError)
    {
        let path = sidecarPath(projectRoot: projectRoot, name: name)
        do { try ProjectFileStore.mkpath(projectRoot + "/.porydaw/samples") }
        catch { throw SampleRegistrationError(message: "cannot write \(path).") }
        ensureSampleGitignore(projectRoot)
        do { try ProjectFileStore.writeAtomic(path, data: sidecar.jsonData()) }
        catch { throw SampleRegistrationError(message: "cannot write \(path).") }
    }

    /// Reads a valid sidecar, or nil when it is missing or invalid.
    public static func readSidecar(projectRoot: String, name: String) -> SampleSidecar? {
        guard let data = try? ProjectFileStore.read(sidecarPath(projectRoot: projectRoot, name: name)) else {
            return nil
        }
        return SampleSidecar.decode(data)
    }

    /// Invalidates a sidecar without affecting the committed WAV.
    public static func removeSidecar(projectRoot: String, name: String) {
        try? ProjectFileStore.remove(sidecarPath(projectRoot: projectRoot, name: name))
    }

    /// Reads the committed WAV and its optional provenance after probing the project layout.
    public static func readCommitted(projectRoot: String, name: String)
        throws(SampleRegistrationError) -> CommittedSample
    {
        let layout = probe(projectRoot: projectRoot)
        guard layout.ok else { throw SampleRegistrationError(message: layout.refusal) }
        let path = layout.samplesDir + "/" + name + ".wav"
        guard let wav = try? ProjectFileStore.read(path) else {
            throw SampleRegistrationError(message: "\(name).wav does not exist in sound/direct_sound_samples.")
        }
        guard !wav.isEmpty else { throw SampleRegistrationError(message: "Cannot read \(path).") }
        return CommittedSample(name: name, wav: wav, wavPath: path,
            sidecar: readSidecar(projectRoot: projectRoot, name: name))
    }

    private static func ensureSampleGitignore(_ root: String) {
        guard ProjectFileStore.exists(root + "/.git") else { return }
        let path = root + "/.gitignore"
        var bytes = (try? ProjectFileStore.read(path)) ?? Data()
        let lines = ProjectFileStore.splitLines(bytes)
        for raw in lines.lines {
            let line = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if [".porydaw", ".porydaw/", "/.porydaw", "/.porydaw/"].contains(line) { return }
        }
        let eol = lines.crlf ? "\r\n" : "\n"
        if !bytes.isEmpty && !lines.endsWithNewline { bytes.append(contentsOf: eol.utf8) }
        bytes.append(contentsOf: (".porydaw/" + eol).utf8)
        try? ProjectFileStore.writeAtomic(path, data: bytes)
    }
}
