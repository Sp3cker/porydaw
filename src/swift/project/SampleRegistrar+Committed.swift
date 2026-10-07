import Foundation
import PorydawVoicegroup

public struct CommittedSample: Sendable {
    public let name: String
    public let wav: Data
    public let wavPath: String
}

extension SampleRegistrar {
    /// Replaces the WAV for an existing registered symbol without touching its assembly entry.
    public static func update(projectRoot: String, name: String, wav: Data) throws(SampleRegistrationError) {
        let layout = probe(projectRoot: projectRoot)
        guard layout.ok else { throw SampleRegistrationError(message: layout.refusal) }
        let symbol = "DirectSoundWaveData_" + name
        guard VoicegroupSource.directSoundSymbols(projectRoot).contains(symbol) else {
            throw SampleRegistrationError(
                message: "\(symbol) is not registered in this project; use Import Sample to add new samples.")
        }
        let path = layout.samplesDir + "/" + name + ".wav"
        guard ProjectFileStore.exists(path) else {
            throw SampleRegistrationError(
                message:
                    "\(name).wav does not exist in sound/direct_sound_samples — only samples with a .wav source can be updated."
            )
        }
        do { try ProjectFileStore.writeAtomic(path, data: wav) } catch {
            throw SampleRegistrationError(message: "cannot write \(path).")
        }
    }

    /// Reads the committed WAV after probing the project layout.
    public static func readCommitted(
        projectRoot: String, name: String
    )
        throws(SampleRegistrationError) -> CommittedSample
    {
        let layout = probe(projectRoot: projectRoot)
        guard layout.ok else { throw SampleRegistrationError(message: layout.refusal) }
        let path = layout.samplesDir + "/" + name + ".wav"
        guard let wav = try? ProjectFileStore.read(path) else {
            throw SampleRegistrationError(message: "\(name).wav does not exist in sound/direct_sound_samples.")
        }
        guard !wav.isEmpty else { throw SampleRegistrationError(message: "Cannot read \(path).") }
        return CommittedSample(name: name, wav: wav, wavPath: path)
    }
}
